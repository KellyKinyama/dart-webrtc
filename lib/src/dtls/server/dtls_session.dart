// Per-peer DTLS handshake session for the server side.
//
// Owns the [HandshakeContext], drives the message-driven state machine and
// fires the `onConnected` / `onApplicationData` callbacks once the
// handshake is complete.

import '../crypto.dart';
import '../dtls_message.dart';
import '../dtls_state.dart';
import '../enums.dart';
import '../handshake/alert.dart';
import '../handshake/application.dart';
import '../handshake/change_cipher_spec.dart';
import '../handshake/client_hello.dart';
import '../handshake/client_key_exchange.dart';
import '../handshake/finished.dart';
import '../handshake/handshake_context.dart';
import '../handshake/tls_random.dart';
import '../key_exchange_algorithm.dart';
import '../record_layer_header.dart';
import '../tests/verify_ecdsa_256_cert1.dart';

import 'cipher_suite_init.dart';
import 'cookie.dart';
import 'handshake_builders.dart';
import 'record_io.dart';
import 'transcript.dart';

import 'dart:typed_data';
import 'dart:io' show Platform;

final bool _verbose = (() {
  final v = Platform.environment['WEBRTC_DEBUG'];
  return v != null && v.isNotEmpty && v != '0' && v.toLowerCase() != 'false';
})();

/// Callback invoked when an `application_data` record is decrypted from
/// this peer.
typedef ApplicationDataHandler = void Function(Uint8List data);

/// Single DTLS association on the server side.
///
/// Each [DtlsSession] holds its own [HandshakeContext] (so multiple peers
/// can be served concurrently) and is fed inbound datagrams via
/// [handleDatagram]. The owning [DtlsServer] is responsible for routing
/// datagrams to the correct session.
class DtlsSession {
  final EcdsaCert _serverCert;
  final HandshakeContext _ctx = HandshakeContext();
  late final RecordWriter _writer;

  /// Fired once the DTLS handshake completes successfully.
  void Function()? onConnected;

  /// Fired for every decrypted application_data record.
  ApplicationDataHandler? onApplicationData;

  /// Fired if the handshake aborts due to an error.
  void Function(Object error, StackTrace stackTrace)? onError;

  DtlsSession({
    required EcdsaCert serverCert,
    required void Function(List<int> bytes) sendRaw,
    int maxHandshakeFragmentLength = defaultMaxHandshakeFragmentLength,
  }) : _serverCert = serverCert {
    _writer = RecordWriter(
      context: _ctx,
      sendRaw: sendRaw,
      maxHandshakeFragmentLength: maxHandshakeFragmentLength,
    );
  }

  HandshakeContext get context => _ctx;

  bool get isConnected => _ctx.dTLSState == DTLSState.DTLSStateConnected;

  /// Feeds an inbound UDP datagram (which may contain one or more DTLS
  /// records) into the state machine.
  Future<void> handleDatagram(Uint8List datagram) async {
    if (_verbose) {
      // ignore: avoid_print
      print('[dtls] handleDatagram ENTER len=${datagram.length} '
          'flight=${_ctx.flight} state=${_ctx.dTLSState}');
    }
    try {
      var offset = 0;
      var recordIdx = 0;
      while (offset < datagram.length) {
        final (rh, _, _) = RecordLayerHeader.unmarshal(
          datagram,
          offset: offset,
          arrayLen: datagram.length - offset,
        );
        final end =
            offset + RecordLayerHeader.RECORD_LAYER_HEADER_SIZE + rh.contentLen;
        final recordBytes = datagram.sublist(offset, end);
        offset = end;

        if (_verbose) {
          // ignore: avoid_print
          print('[dtls] decoding record#$recordIdx ct=${rh.contentType} '
              'epoch=${rh.epoch} len=${rh.contentLen}');
        }

        final decoded = await DecodeDtlsMessageResult.decode(
          _ctx,
          recordBytes,
          0,
          recordBytes.length,
          CipherSuiteId.Tls_Ecdhe_Ecdsa_With_Aes_128_Gcm_Sha256,
        );

        if (_verbose) {
          // ignore: avoid_print
          print('[dtls] decoded record#$recordIdx -> '
              '${decoded.message?.runtimeType ?? 'null'}');
        }
        recordIdx++;

        await _dispatch(decoded);
      }
      if (_verbose) {
        // ignore: avoid_print
        print('[dtls] handleDatagram DONE flight=${_ctx.flight}');
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('[dtls] handleDatagram error: $e\n$st');
      onError?.call(e, st);
      rethrow;
    }
  }

  Future<void> _dispatch(DecodeDtlsMessageResult decoded) async {
    final message = decoded.message;
    if (message == null) return; // ignored / fragmented / older epoch

    if (message is ClientHello) {
      await _onClientHello(message);
    } else if (message is ClientKeyExchange) {
      await _onClientKeyExchange(message);
    } else if (message is Finished) {
      await _onClientFinished(message);
    } else if (message is ChangeCipherSpec) {
      // No state change required: the record-layer epoch transition is
      // already handled inside DecodeDtlsMessageResult / the GCM layer.
    } else if (message is ApplicationData) {
      _onApplicationData(message);
    } else if (message is Alert) {
      // ignore: avoid_print
      print('[dtls] <- Alert level=${message.alertLevel} '
          'description=${message.alertDescription}');
    }
    // Other types (Certificate, CertificateVerify, Alert) are ignored in
    // this server profile — we don't request client auth and we don't
    // surface alerts to user code.
  }

  Future<void> _onClientHello(ClientHello message) async {
    _ctx.session_id = Uint8List.fromList(message.session_id);
    _ctx.compression_methods = message.compression_methods;
    _ctx.extensions = message.extensions;
    _ctx.extensionsData = message.extensionsData!;

    if (_ctx.flight == Flight.Flight0 || message.cookie.isEmpty) {
      // First ClientHello (no cookie yet) — reply with HelloVerifyRequest.
      _ctx.dTLSState = DTLSState.DTLSStateConnecting;
      _ctx.protocolVersion = message.client_version;
      _ctx.cookie = generateDtlsCookie();
      _ctx.clientRandom = message.random;
      _ctx.flight = Flight.Flight2;
      await _writer.send(HandshakeBuilders.helloVerifyRequest(_ctx));
      return;
    }

    // Second ClientHello (with cookie) — produce server flight 4.
    final negotiated = _negotiateCipherSuite(message.cipher_suites);
    _ctx.cipherSuite = negotiated.value;

    _ctx.serverRandom = TlsRandom.defaultInstance()..populate();
    _ctx.serverPublicKey = _serverCert.publickKey;
    _ctx.serverPrivateKey = _serverCert.privateKey;

    final clientRandomBytes = _ctx.clientRandom.raw();
    final serverRandomBytes = _ctx.serverRandom.marshal();
    _ctx.serverKeySignature = generateKeySignature(
      clientRandomBytes,
      serverRandomBytes,
      _ctx.serverPublicKey,
      _ctx.serverPrivateKey,
    );

    _ctx.flight = Flight.Flight4;

    await _writer.send(HandshakeBuilders.serverHello(_ctx));
    await _writer.send(HandshakeBuilders.certificate(_serverCert));
    await _writer.send(HandshakeBuilders.serverKeyExchange(_ctx));
    await _writer.send(HandshakeBuilders.serverHelloDone());
  }

  Future<void> _onClientKeyExchange(ClientKeyExchange message) async {
    _ctx.clientKeyExchangePublic = message.publicKey;
    if (!_ctx.isCipherSuiteInitialized) {
      await initEcdheEcdsaAes128GcmSha256(_ctx);
    }
  }

  Future<void> _onClientFinished(Finished _) async {
    final transcript = buildHandshakeTranscript(
      _ctx,
      includeReceivedFinished: true,
    );
    final verifyData = prfVerifyDataServer(_ctx.serverMasterSecret, transcript);

    await _writer.send(HandshakeBuilders.changeCipherSpec());
    _ctx.increaseServerEpoch();

    await _writer.send(HandshakeBuilders.finished(verifyData));

    _ctx.dTLSState = DTLSState.DTLSStateConnected;
    onConnected?.call();
  }

  void _onApplicationData(ApplicationData message) {
    onApplicationData?.call(message.applicationData);
  }

  CipherSuiteId _negotiateCipherSuite(List<CipherSuiteId> offered) {
    const supported = CipherSuiteId.Tls_Ecdhe_Ecdsa_With_Aes_128_Gcm_Sha256;
    if (offered.contains(supported)) return supported;
    throw StateError('no mutually supported cipher suite; offered=$offered');
  }
}
