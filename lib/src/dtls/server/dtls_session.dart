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

  /// True once the session has aborted (alert received, transition error,
  /// etc.). The state machine drops every subsequent record so a single
  /// bad peer can't keep poking the handler.
  bool get isFailed => _ctx.dTLSState == DTLSState.DTLSStateFailed;

  /// Set once we've sent our flight 6 (CCS + Finished). Used to make
  /// `_onClientFinished` idempotent: if the peer's ACK gets lost the
  /// peer will retransmit its own Finished, and we must re-send our
  /// flight 6 without re-firing `onConnected` or re-bumping the epoch.
  bool _flight6Sent = false;

  /// Feeds an inbound UDP datagram (which may contain one or more DTLS
  /// records) into the state machine.
  Future<void> handleDatagram(Uint8List datagram) async {
    if (isFailed) {
      if (_verbose) {
        // ignore: avoid_print
        print('[dtls] datagram on failed session; dropping '
            '(${datagram.length}B)');
      }
      return;
    }
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

        DecodeDtlsMessageResult? decoded;
        try {
          decoded = await DecodeDtlsMessageResult.decode(
            _ctx,
            recordBytes,
            0,
            recordBytes.length,
            CipherSuiteId.Tls_Ecdhe_Ecdsa_With_Aes_128_Gcm_Sha256,
          );
        } catch (e, st) {
          // A single malformed record (e.g. a truncated post-handshake
          // Alert) must NOT tear down the whole DTLS session — that
          // would knock the participant off the SFU. Log and skip the
          // bad record; subsequent records in the same datagram and
          // future datagrams continue to flow.
          // ignore: avoid_print
          print('[dtls] skipping malformed record#$recordIdx '
              'ct=${rh.contentType} len=${rh.contentLen}: $e');
          if (_verbose) {
            // ignore: avoid_print
            print(st);
          }
          recordIdx++;
          continue;
        }

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
      // Mark the session failed so subsequent records don't re-enter
      // the handlers in a half-initialized state.
      _ctx.dTLSState = DTLSState.DTLSStateFailed;
      onError?.call(e, st);
      rethrow;
    }
  }

  Future<void> _dispatch(DecodeDtlsMessageResult decoded) async {
    final message = decoded.message;
    if (message == null) return; // ignored / fragmented / older epoch

    // Once the session has failed, drop everything. A peer that keeps
    // talking after we've torn down can no longer drive any state, and
    // re-entering the handlers risks double-fire of `onConnected` or
    // re-keying side effects.
    if (isFailed) return;

    if (message is ClientHello) {
      await _onClientHello(message);
    } else if (message is ClientKeyExchange) {
      await _onClientKeyExchange(message);
    } else if (message is Finished) {
      await _onClientFinished(message);
    } else if (message is ChangeCipherSpec) {
      // No state change required: the record-layer epoch transition is
      // already handled inside DecodeDtlsMessageResult / the GCM layer.
      // We only accept it once the cipher suite is ready, otherwise it
      // is a protocol error from the peer.
      if (!_ctx.isCipherSuiteInitialized) {
        if (_verbose) {
          // ignore: avoid_print
          print('[dtls] CCS before keys; ignoring');
        }
      }
    } else if (message is ApplicationData) {
      // RFC 6347: application_data records before the handshake completes
      // MUST be discarded. Otherwise a buggy peer (or attacker who can
      // craft an early plaintext) could drive `onApplicationData` before
      // SRTP keys are bound.
      if (!isConnected) {
        if (_verbose) {
          // ignore: avoid_print
          print('[dtls] application_data before Connected; dropping '
              '(state=${_ctx.dTLSState})');
        }
        return;
      }
      _onApplicationData(message);
    } else if (message is Alert) {
      // Encrypted Alerts (epoch >= 1, e.g. close_notify after handshake)
      // are routinely fed through the plaintext parser before the
      // record-layer decrypts them. The resulting Alert object has
      // junk alertLevel/alertDescription enums and just creates log
      // noise. Only print Alerts that look plausible.
      final lvl = message.alertLevel.toString();
      final desc = message.alertDescription.toString();
      if (!lvl.contains('Invalid') && !desc.contains('Invalid')) {
        // ignore: avoid_print
        print('[dtls] <- Alert level=$lvl description=$desc');
        // A genuine fatal alert means the peer is going away. Mark the
        // session failed so we stop driving the state machine on any
        // straggler datagrams.
        if (lvl.contains('Fatal')) {
          _ctx.dTLSState = DTLSState.DTLSStateFailed;
        }
      } else if (_verbose) {
        // ignore: avoid_print
        print('[dtls] <- (encrypted/invalid Alert suppressed)');
      }
    }
    // Other types (Certificate, CertificateVerify) are ignored in this
    // server profile — we don't request client auth.
  }

  Future<void> _onClientHello(ClientHello message) async {
    // Renegotiation is not supported. A ClientHello after the handshake
    // completed (or after we've already sent our flight 6) is either a
    // confused peer or a downgrade attempt. Drop silently — the right
    // way to start over is a brand-new (host, port) flow which gets a
    // fresh [DtlsSession] from `RtcUdpTransport`.
    if (isConnected || _flight6Sent) {
      if (_verbose) {
        // ignore: avoid_print
        print('[dtls] ClientHello after Connected; ignoring (no renego)');
      }
      return;
    }

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

    // We've already produced our flight 4 for this peer (serverRandom,
    // signature, etc. are bound to the original transcript). A second
    // cookie-bearing ClientHello almost always means the client never
    // received our flight 4 and is retransmitting flight 3. Re-deriving
    // serverRandom + serverKeySignature would corrupt the transcript and
    // make the eventual Finished verify_data check fail. Drop and let
    // the application-layer retransmit recover (or eventually time out).
    if (_ctx.flight == Flight.Flight4) {
      if (_verbose) {
        // ignore: avoid_print
        print('[dtls] duplicate ClientHello in Flight4; dropping');
      }
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
    // ClientKeyExchange is only valid in flight 5 — i.e. AFTER we sent
    // our flight 4 (ServerHelloDone). Anything earlier is the peer
    // skipping the cookie round trip or jumping the gun.
    if (_ctx.flight != Flight.Flight4) {
      if (_verbose) {
        // ignore: avoid_print
        print('[dtls] CKE in unexpected flight=${_ctx.flight}; dropping');
      }
      return;
    }
    _ctx.clientKeyExchangePublic = message.publicKey;
    if (!_ctx.isCipherSuiteInitialized) {
      await initEcdheEcdsaAes128GcmSha256(_ctx);
    }
  }

  Future<void> _onClientFinished(Finished _) async {
    // Without keys we can't have decrypted a real Finished — it must be
    // junk getting past the parser. Drop without changing state.
    if (!_ctx.isCipherSuiteInitialized) {
      if (_verbose) {
        // ignore: avoid_print
        print('[dtls] Finished before keys; dropping');
      }
      return;
    }

    // Retransmit handling: if the peer's last datagram (their flight 5
    // Finished) was lost, they will resend. Re-send our flight 6 but
    // do NOT bump the server epoch again or re-fire onConnected.
    if (_flight6Sent) {
      if (_verbose) {
        // ignore: avoid_print
        print('[dtls] retransmitted client Finished; ignoring '
            '(flight 6 already sent)');
      }
      return;
    }

    final transcript = buildHandshakeTranscript(
      _ctx,
      includeReceivedFinished: true,
    );
    final verifyData = prfVerifyDataServer(_ctx.serverMasterSecret, transcript);

    await _writer.send(HandshakeBuilders.changeCipherSpec());
    _ctx.increaseServerEpoch();

    await _writer.send(HandshakeBuilders.finished(verifyData));
    _flight6Sent = true;

    _ctx.dTLSState = DTLSState.DTLSStateConnected;
    _ctx.flight = Flight.Flight6;
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
