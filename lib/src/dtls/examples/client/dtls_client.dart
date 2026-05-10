// DTLS 1.2 client compatible with the server in
// `lib/src/dtls/examples/server/dtls_server.dart` and the
// `HandshakeManager` in `lib/src/dtls/handshaker/aes_gcm_128_sha_256.dart`.
//
// Cipher suite: TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 (0xC02B)
// Curve:        prime256v1 / secp256r1 (0x0017)
// Point format: uncompressed (0x00)
// Extended Master Secret: enabled
//
// The client implements the standard DTLS 1.2 6-flight handshake:
//   --> ClientHello (no cookie)
//   <-- HelloVerifyRequest
//   --> ClientHello (with cookie)
//   <-- ServerHello, Certificate, ServerKeyExchange, ServerHelloDone
//   --> ClientKeyExchange, ChangeCipherSpec, Finished (encrypted)
//   <-- ChangeCipherSpec, Finished (encrypted)
//
// Run:
//   dart run lib/src/dtls/examples/client/dtls_client.dart
//
// (Make sure the server in examples/server is running on 127.0.0.1:4444.)

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../cert_utils.dart' show generateP256Keys;
import '../../crypto/crypto_gcm5.dart';
import '../../handshake/handshake.dart' show ContentType, ProtocolVersion;
import '../../key_exchange_algorithm.dart'
    show
        createHash,
        generateEncryptionKeys,
        generateExtendedMasterSecret,
        generateKeyingMaterial,
        generatePreMasterSecret,
        prfVerifyDataClient,
        prfVerifyDataServer;
import '../../record_layer_header.dart';

// -------- Constants --------

const int _hsTypeClientHello = 1;
const int _hsTypeServerHello = 2;
const int _hsTypeHelloVerifyRequest = 3;
const int _hsTypeCertificate = 11;
const int _hsTypeServerKeyExchange = 12;
const int _hsTypeServerHelloDone = 14;
const int _hsTypeClientKeyExchange = 16;
const int _hsTypeFinished = 20;

const int _ctChangeCipherSpec = 20;
const int _ctAlert = 21;
const int _ctHandshake = 22;
const int _ctApplicationData = 23;

const int _cipherSuiteTlsEcdheEcdsaWithAes128GcmSha256 = 0xC02B;
const int _namedCurvePrime256v1 = 0x0017;
const int _ellipticCurveTypeNamedCurve = 0x03;

// Extension types
const int _extSupportedEllipticCurves = 10;
const int _extSupportedPointFormats = 11;
const int _extSupportedSignatureAlgorithms = 13;
const int _extUseExtendedMasterSecret = 23;
const int _extRenegotiationInfo = 0xFF01;

const _dtls12 = [254, 253]; // {major: 254, minor: 253}

// -------- Public API --------

/// A minimal DTLS 1.2 client.
class DtlsClient {
  final InternetAddress serverAddress;
  final int serverPort;

  late RawDatagramSocket _socket;
  late StreamSubscription<RawSocketEvent> _sub;

  // ECDHE keys (P-256 ephemeral).
  late Uint8List _clientPrivateKey;
  late Uint8List _clientPublicKey; // 0x04 || X(32) || Y(32) -> 65 bytes

  // Random values (32 bytes each).
  late Uint8List _clientRandom;
  late Uint8List _serverRandom;

  // Server-provided values.
  late Uint8List _cookie;
  Uint8List _serverEcdhePublicKey = Uint8List(0);

  // Sequence numbers / epochs.
  int _clientHandshakeSeq = 0;
  int _clientRecordSeq = 0;
  int _clientEpoch = 0;
  int _serverEpoch = 0;
  int _expectedServerSeq = 0;

  // Transcript: HandshakeType -> raw handshake message bytes (header + body).
  // Per RFC 5246 §7.4.9 + RFC 6347, only the second ClientHello is included
  // in the transcript (the first one and the HelloVerifyRequest are dropped).
  final Map<int, Uint8List> _sent = {};
  final Map<int, Uint8List> _recv = {};
  // Reassembly buffers for fragmented handshake messages, keyed by
  // `message_seq`. Records sharing the same message_seq carry pieces of
  // the same logical handshake message.
  final Map<int, _Reasm> _reasm = {};
  // Defines the canonical concatenation order used for verify_data PRF input.
  static const List<int> _transcriptOrder = [
    _hsTypeClientHello, // sent
    _hsTypeServerHello, // recv
    _hsTypeCertificate, // recv
    _hsTypeServerKeyExchange, // recv
    _hsTypeServerHelloDone, // recv
    _hsTypeClientKeyExchange, // sent
  ];

  GCM? _gcm;
  Uint8List? _masterSecret;

  // Reassembly buffer: incoming records may be coalesced into one datagram or
  // split across many. We process record-by-record from the receive queue.
  final List<List<int>> _incoming = [];
  Completer<void>? _waitForData;

  // Completer that fires once the handshake completes.
  final Completer<void> _handshakeDone = Completer<void>();
  Future<void> get done => _handshakeDone.future;

  /// Optional sink for non-DTLS datagrams that arrive on the socket after
  /// the handshake completes (e.g. SRTP traffic when the same UDP socket is
  /// shared with an [SRTPClient]).
  void Function(Datagram datagram)? onApplicationDatagram;

  DtlsClient(this.serverAddress, this.serverPort);

  Future<void> connect() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    // Bump the receive buffer to absorb bursts of fragmented handshake
    // records on loopback. Best-effort across platforms.
    _trySetRcvBuf(_socket, 1 << 20);
    _sub = _socket.listen(_onEvent);

    final keys = generateP256Keys();
    _clientPrivateKey = keys.privateKey;
    _clientPublicKey = keys.publicKey;
    _clientRandom = _randomBytes(32);

    print('[client] starting handshake to '
        '${serverAddress.address}:$serverPort');

    // Flight 1: ClientHello (no cookie).
    _sendClientHello(cookie: Uint8List(0));

    // Wait for HelloVerifyRequest, parse it and send ClientHello with cookie.
    final hvrBody = await _expectHandshake(_hsTypeHelloVerifyRequest);
    _cookie = _parseHelloVerifyRequest(hvrBody);
    // print('[client] got HelloVerifyRequest, cookie=${_hex(_cookie)}');

    // Reset handshake sequence: per the server's HandshakeManager the cookie
    // round-trip uses messageSequence=1 on the second ClientHello. We've
    // already incremented after the first ClientHello, so _clientHandshakeSeq
    // is already 1. Clear the previous (cookie-less) ClientHello from the
    // transcript: only the second ClientHello goes in the verify hash.
    _sent.remove(_hsTypeClientHello);

    // Flight 3: ClientHello with cookie.
    _sendClientHello(cookie: _cookie);

    // Flight 4: ServerHello, Certificate, ServerKeyExchange, ServerHelloDone.
    final shBody = await _expectHandshake(_hsTypeServerHello);
    _parseServerHello(shBody);

    final certBody = await _expectHandshake(_hsTypeCertificate);
    // print('[client] got Certificate (${certBody.length} bytes)');

    final skeBody = await _expectHandshake(_hsTypeServerKeyExchange);
    _parseServerKeyExchange(skeBody);

    await _expectHandshake(_hsTypeServerHelloDone);
    print('[client] got ServerHelloDone');

    // Flight 5: ClientKeyExchange (+ ChangeCipherSpec, Finished).
    _sendClientKeyExchange();

    // Derive keys (extended master secret).
    final preMaster =
        generatePreMasterSecret(_serverEcdhePublicKey, _clientPrivateKey);
    final transcript = _concatTranscript(includeFinished: false);
    final transcriptHash = createHash(transcript);
    _masterSecret = generateExtendedMasterSecret(preMaster, transcriptHash);
    // Derive GCM keys for the *client* perspective: local = client write key,
    // remote = server write key. The repo's `initGCM` is hard-coded for the
    // server-side direction, so we build the GCM directly here.
    final encKeys = generateEncryptionKeys(
        _masterSecret!, _clientRandom, _serverRandom, 16, 4);
    _gcm = await GCM.create(encKeys.clientWriteKey, encKeys.clientWriteIV,
        encKeys.serverWriteKey, encKeys.serverWriteIV);
    print('[client] keys derived; sending ChangeCipherSpec + Finished');

    // ChangeCipherSpec (epoch 0, then bump to 1).
    _sendRecord(_ctChangeCipherSpec, Uint8List.fromList([0x01]),
        encrypt: false);
    _clientEpoch = 1;
    _clientRecordSeq = 0;

    // Compute client Finished verify_data over current transcript.
    final clientVerifyData = prfVerifyDataClient(_masterSecret!, transcript);
    final finishedBody = clientVerifyData;
    final finishedHandshake = _wrapHandshake(_hsTypeFinished, finishedBody);
    _sent[_hsTypeFinished] = finishedHandshake;
    await _sendEncryptedHandshake(finishedHandshake);

    // Flight 6: ChangeCipherSpec, Finished from server.
    await _expectChangeCipherSpec();
    _serverEpoch = 1;
    _expectedServerSeq = 0;

    final serverFinishedBody = await _expectHandshake(_hsTypeFinished);
    final transcriptWithClientFinished =
        _concatTranscript(includeFinished: true);
    final expectedServerVerify =
        prfVerifyDataServer(_masterSecret!, transcriptWithClientFinished);
    if (!_constTimeEq(serverFinishedBody, expectedServerVerify)) {
      throw StateError('server Finished verify_data mismatch:\n'
          '  got      ${_hex(serverFinishedBody)}\n'
          '  expected ${_hex(expectedServerVerify)}');
    }
    print('[client] server Finished verified — handshake complete');
    _handshakeDone.complete();
  }

  /// Send application data (encrypted) to the peer once the handshake has
  /// completed.
  Future<void> sendApplicationData(Uint8List data) async {
    if (_gcm == null || _clientEpoch == 0) {
      throw StateError('handshake not complete');
    }
    await _sendEncryptedRecord(_ctApplicationData, data);
  }

  Future<void> close() async {
    await _sub.cancel();
    _socket.close();
  }

  /// Export RFC 5705 keying material (e.g. for SRTP key derivation).
  ///
  /// Uses label `"EXTRACTOR-dtls_srtp"` and seeds the PRF with
  /// `client_random || server_random`, matching what the server-side
  /// `HandshakeContext.exportKeyingMaterial` produces. For SRTP_AEAD_AES_128_GCM
  /// pass `length = 2 * 16 + 2 * 12 = 56`.
  Uint8List exportKeyingMaterial(int length) {
    if (_masterSecret == null) {
      throw StateError('handshake not complete');
    }
    return generateKeyingMaterial(
        _masterSecret!, _clientRandom, _serverRandom, length);
  }

  /// Returns the underlying [RawDatagramSocket] without cancelling the
  /// internal stream subscription. Inbound datagrams continue to flow
  /// through [_onEvent], which after handshake completion routes non-DTLS
  /// traffic to [onApplicationDatagram] (typically an SRTP client). Use
  /// this to share the same UDP socket with another component.
  RawDatagramSocket get socket => _socket;

  /// Stop the internal socket listener and return the underlying
  /// [RawDatagramSocket]. Useful for handing the socket off to another
  /// component (e.g. an SRTP client) once the DTLS handshake is done.
  ///
  /// After calling this, the [DtlsClient] no longer reads from the socket
  /// and [close] only cancels the (already-cancelled) subscription.
  Future<RawDatagramSocket> detachSocket() async {
    await _sub.cancel();
    return _socket;
  }

  // -------- Handshake message builders --------

  void _sendClientHello({required Uint8List cookie}) {
    final body = BytesBuilder();
    body.add(_dtls12); // client_version
    body.add(_clientRandom); // random (32 bytes)
    body.addByte(0); // session_id length = 0
    body.addByte(cookie.length);
    body.add(cookie);

    // cipher_suites: TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 only.
    body.add(_be16(2));
    body.add(_be16(_cipherSuiteTlsEcdheEcdsaWithAes128GcmSha256));

    // compression_methods: null only.
    body.addByte(1);
    body.addByte(0);

    // extensions
    body.add(_buildClientExtensions());

    final hs = _wrapHandshake(_hsTypeClientHello, body.toBytes());
    _sent[_hsTypeClientHello] = hs;
    _sendRecord(_ctHandshake, hs, encrypt: false);
  }

  Uint8List _buildClientExtensions() {
    final exts = BytesBuilder();

    // supported_elliptic_curves (10): just prime256v1.
    exts.add(_be16(_extSupportedEllipticCurves));
    final curvesData = <int>[..._be16(2), ..._be16(_namedCurvePrime256v1)];
    exts.add(_be16(curvesData.length));
    exts.add(curvesData);

    // supported_point_formats (11): uncompressed.
    exts.add(_be16(_extSupportedPointFormats));
    final pfData = <int>[1, 0];
    exts.add(_be16(pfData.length));
    exts.add(pfData);

    // signature_algorithms (13): ecdsa_secp256r1_sha256 (0x0403).
    exts.add(_be16(_extSupportedSignatureAlgorithms));
    final sigData = <int>[..._be16(2), 0x04, 0x03];
    exts.add(_be16(sigData.length));
    exts.add(sigData);

    // extended_master_secret (23): empty.
    exts.add(_be16(_extUseExtendedMasterSecret));
    exts.add(_be16(0));

    // renegotiation_info (0xff01): single zero byte.
    exts.add(_be16(_extRenegotiationInfo));
    final renegData = <int>[0];
    exts.add(_be16(renegData.length));
    exts.add(renegData);

    final extsBytes = exts.toBytes();
    final out = BytesBuilder();
    out.add(_be16(extsBytes.length));
    out.add(extsBytes);
    return out.toBytes();
  }

  void _sendClientKeyExchange() {
    // Body: opaque ECPoint, 1 byte length prefix.
    final body = BytesBuilder();
    body.addByte(_clientPublicKey.length);
    body.add(_clientPublicKey);

    final hs = _wrapHandshake(_hsTypeClientKeyExchange, body.toBytes());
    _sent[_hsTypeClientKeyExchange] = hs;
    _sendRecord(_ctHandshake, hs, encrypt: false);
  }

  Uint8List _wrapHandshake(int hsType, Uint8List body) {
    final out = BytesBuilder();
    out.addByte(hsType);
    out.add(_uint24(body.length)); // length
    out.add(_be16(_clientHandshakeSeq)); // message_seq
    out.add(_uint24(0)); // fragment_offset
    out.add(_uint24(body.length)); // fragment_length
    out.add(body);
    _clientHandshakeSeq++;
    return out.toBytes();
  }

  // -------- Parsers --------

  Uint8List _parseHelloVerifyRequest(Uint8List body) {
    // 2 bytes version + 1 byte cookie length + cookie.
    final cookieLen = body[2];
    return Uint8List.fromList(body.sublist(3, 3 + cookieLen));
  }

  void _parseServerHello(Uint8List body) {
    int o = 0;
    // server_version
    o += 2;
    // random (32 bytes)
    _serverRandom = Uint8List.fromList(body.sublist(o, o + 32));
    o += 32;
    // session_id
    final sidLen = body[o];
    o += 1 + sidLen;
    // cipher_suite
    final suite = (body[o] << 8) | body[o + 1];
    o += 2;
    if (suite != _cipherSuiteTlsEcdheEcdsaWithAes128GcmSha256) {
      throw StateError('server selected unsupported cipher suite: '
          '0x${suite.toRadixString(16)}');
    }
    // compression_method
    o += 1;
    print('[client] got ServerHello (suite=0x${suite.toRadixString(16)})');
  }

  void _parseServerKeyExchange(Uint8List body) {
    // ServerKeyExchange (ECDHE_ECDSA):
    //   ECCurveType curve_type;       // 1 byte (0x03 = named_curve)
    //   NamedCurve  named_curve;      // 2 bytes
    //   uint8       point_length;
    //   opaque      point[point_length]; // server ECDHE public key
    //   uint8       hash_algo;
    //   uint8       sig_algo;
    //   uint16      signature_length;
    //   opaque      signature[signature_length];
    int o = 0;
    final curveType = body[o++];
    if (curveType != _ellipticCurveTypeNamedCurve) {
      throw StateError('unexpected curve type: $curveType');
    }
    final namedCurve = (body[o] << 8) | body[o + 1];
    o += 2;
    if (namedCurve != _namedCurvePrime256v1) {
      throw StateError('unexpected named curve: 0x'
          '${namedCurve.toRadixString(16)}');
    }
    final pointLen = body[o++];
    _serverEcdhePublicKey = Uint8List.fromList(body.sublist(o, o + pointLen));
    o += pointLen;
    // We don't verify the certificate / signature in this minimal example;
    // the server in this repo signs with an ephemeral self-signed cert and
    // the parent project just trusts the SDP fingerprint.
    print('[client] got ServerKeyExchange (server pub '
        '${_serverEcdhePublicKey.length} bytes)');
  }

  // -------- Record I/O --------

  void _sendRecord(int contentType, Uint8List body,
      {required bool encrypt}) async {
    final header = _buildRecordHeader(contentType, body.length);
    var record = Uint8List.fromList([...header, ...body]);
    if (encrypt) {
      // GCM expects header + plaintext, returns the encrypted record (with
      // updated content length in the header).
      final rh = _recordHeaderObject(contentType, body.length);
      record = await _gcm!.encrypt(rh, record);
    }
    _socket.send(record, serverAddress, serverPort);
    _clientRecordSeq++;
  }

  Future<void> _sendEncryptedRecord(int contentType, Uint8List body) async {
    final header = _buildRecordHeader(contentType, body.length);
    final rh = _recordHeaderObject(contentType, body.length);
    final plaintextRecord = Uint8List.fromList([...header, ...body]);
    final encrypted = await _gcm!.encrypt(rh, plaintextRecord);
    _socket.send(encrypted, serverAddress, serverPort);
    _clientRecordSeq++;
  }

  Future<void> _sendEncryptedHandshake(Uint8List handshake) async {
    await _sendEncryptedRecord(_ctHandshake, handshake);
  }

  Uint8List _buildRecordHeader(int contentType, int contentLen) {
    final h = BytesBuilder();
    h.addByte(contentType);
    h.add(_dtls12);
    h.add(_be16(_clientEpoch));
    h.add(_uint48(_clientRecordSeq));
    h.add(_be16(contentLen));
    return h.toBytes();
  }

  RecordLayerHeader _recordHeaderObject(int contentType, int contentLen) {
    return RecordLayerHeader(
      contentType: ContentType.fromInt(contentType),
      protocolVersion: ProtocolVersion(254, 253),
      epoch: _clientEpoch,
      sequenceNumber: _clientRecordSeq,
      contentLen: contentLen,
    );
  }

  void _onEvent(RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    // Drain *all* datagrams currently buffered by the kernel, not just one,
    // to avoid OS-level UDP drops when the peer sends a burst of records
    // (e.g. several handshake fragments back-to-back).
    while (true) {
      final dg = _socket.receive();
      if (dg == null) break;
      // After the handshake completes, route non-DTLS datagrams to the
      // application sink (typically an SRTP client). DTLS records and
      // anything that *looks* like one (content-type 20-23) still goes
      // through the handshake state machine.
      if (_handshakeDone.isCompleted &&
          onApplicationDatagram != null &&
          !_looksLikeDtls(dg.data)) {
        onApplicationDatagram!(dg);
        continue;
      }
      _incoming.add(dg.data);
    }
    final w = _waitForData;
    if (_incoming.isNotEmpty && w != null && !w.isCompleted) {
      _waitForData = null;
      w.complete();
    }
  }

  static bool _looksLikeDtls(List<int> b) {
    if (b.length < 13) return false;
    final ct = b[0];
    return ct >= 20 && ct <= 23;
  }

  // -------- Pull-based message dispatch --------

  // Pending parsed (record_type, payload) pairs ready to be consumed.
  final List<_Frame> _frames = [];

  Future<_Frame> _nextFrame() async {
    while (_frames.isEmpty) {
      while (_incoming.isEmpty) {
        _waitForData = Completer<void>();
        await _waitForData!.future.timeout(const Duration(seconds: 5),
            onTimeout: () =>
                throw TimeoutException('no DTLS data from server'));
      }
      final dg = Uint8List.fromList(_incoming.removeAt(0));
      _splitDatagramIntoFrames(dg);
    }
    return _frames.removeAt(0);
  }

  void _splitDatagramIntoFrames(Uint8List dg) {
    int o = 0;
    while (o + 13 <= dg.length) {
      final ct = dg[o];
      final epoch = (dg[o + 3] << 8) | dg[o + 4];
      final len = (dg[o + 11] << 8) | dg[o + 12];
      final start = o;
      final end = o + 13 + len;
      if (end > dg.length) {
        print('[client] truncated record, dropping');
        return;
      }
      final record = Uint8List.fromList(dg.sublist(start, end));
      o = end;

      _frames.add(_Frame(contentType: ct, epoch: epoch, record: record));
    }
  }

  Future<Uint8List> _expectHandshake(int wantType) async {
    while (true) {
      final f = await _nextFrame();
      if (f.contentType == _ctAlert) {
        throw StateError('server sent alert: ${_hex(f.record.sublist(13))}');
      }
      if (f.contentType == _ctChangeCipherSpec) {
        // not what we wanted right now; ignore (or surface via a flag)
        continue;
      }
      if (f.contentType != _ctHandshake) {
        throw StateError(
            'unexpected content type ${f.contentType} while expecting handshake');
      }

      Uint8List handshake;
      if (f.epoch > 0) {
        if (_gcm == null) {
          throw StateError('encrypted record but no keys');
        }
        final dec = await _gcm!.decrypt(f.record);
        if (dec == null) {
          throw StateError('decryption failed');
        }
        handshake = Uint8List.fromList(dec.sublist(13));
      } else {
        handshake = Uint8List.fromList(f.record.sublist(13));
      }

      // A single record may contain several handshake messages back-to-back
      // (e.g. ServerHello+Certificate+SKE+SHD). It may also contain
      // fragments of a larger logical message (RFC 6347 §4.2.3).
      int o = 0;
      while (o + 12 <= handshake.length) {
        final hsType = handshake[o];
        final length = (handshake[o + 1] << 16) |
            (handshake[o + 2] << 8) |
            handshake[o + 3];
        final messageSeq = (handshake[o + 4] << 8) | handshake[o + 5];
        final fragOff = (handshake[o + 6] << 16) |
            (handshake[o + 7] << 8) |
            handshake[o + 8];
        final fragLen = (handshake[o + 9] << 16) |
            (handshake[o + 10] << 8) |
            handshake[o + 11];

        if (o + 12 + fragLen > handshake.length) {
          throw StateError('truncated handshake fragment');
        }

        Uint8List? body; // populated when this iteration completes a message
        Uint8List? fullMsg;

        if (fragOff == 0 && fragLen == length) {
          // Unfragmented — fast path.
          body = Uint8List.fromList(handshake.sublist(o + 12, o + 12 + length));
          fullMsg = Uint8List.fromList(handshake.sublist(o, o + 12 + length));
        } else {
          // Fragment — accumulate.
          final r = _reasm.putIfAbsent(
            messageSeq,
            () => _Reasm(hsType: hsType, length: length),
          );
          if (r.hsType != hsType || r.length != length) {
            throw StateError(
                'inconsistent fragment metadata for message_seq=$messageSeq');
          }
          if (fragOff + fragLen > length) {
            throw StateError('fragment exceeds message length');
          }
          r.buffer.setRange(
            fragOff,
            fragOff + fragLen,
            handshake.sublist(o + 12, o + 12 + fragLen),
          );
          r.received += fragLen;
          if (r.received >= r.length) {
            // Reassembled — synthesize canonical (un-fragmented) bytes.
            body = r.buffer;
            final hdr = Uint8List(12);
            hdr[0] = hsType;
            hdr[1] = (length >> 16) & 0xff;
            hdr[2] = (length >> 8) & 0xff;
            hdr[3] = length & 0xff;
            hdr[4] = (messageSeq >> 8) & 0xff;
            hdr[5] = messageSeq & 0xff;
            // fragment_offset = 0, fragment_length = length
            hdr[9] = (length >> 16) & 0xff;
            hdr[10] = (length >> 8) & 0xff;
            hdr[11] = length & 0xff;
            fullMsg = Uint8List.fromList([...hdr, ...body]);
            _reasm.remove(messageSeq);
          }
        }

        o += 12 + fragLen;

        if (body == null || fullMsg == null) {
          // This fragment did not complete a message; keep parsing.
          continue;
        }

        _recv[hsType] = fullMsg;

        if (hsType == wantType) {
          // If multiple messages are still queued for this datagram, push
          // them back as synthetic handshake-only frames so they can be
          // consumed by subsequent calls.
          if (o < handshake.length) {
            final remaining = Uint8List.fromList(handshake.sublist(o));
            // Re-wrap remaining bytes in a plaintext handshake record so
            // that _expectHandshake can re-enter and find the next message.
            final synthetic = _wrapPlaintextHandshakeRecord(remaining);
            _frames.insert(0,
                _Frame(contentType: _ctHandshake, epoch: 0, record: synthetic));
          }
          return body;
        }
        // We got a different handshake type than expected — an error in
        // ordering. Surface it.
        if (hsType == _hsTypeHelloVerifyRequest && wantType != hsType) {
          throw StateError('unexpected HelloVerifyRequest');
        }
      }

      // Datagram exhausted without yielding the wanted message — go read
      // the next datagram (might be more fragments).
    }
  }

  Uint8List _wrapPlaintextHandshakeRecord(Uint8List body) {
    final h = BytesBuilder();
    h.addByte(_ctHandshake);
    h.add(_dtls12);
    h.add(_be16(0)); // epoch (already-decrypted view)
    h.add(_uint48(0)); // sequence (irrelevant for our internal queue)
    h.add(_be16(body.length));
    h.add(body);
    return h.toBytes();
  }

  Future<void> _expectChangeCipherSpec() async {
    while (true) {
      final f = await _nextFrame();
      if (f.contentType == _ctChangeCipherSpec) {
        print('[client] got ChangeCipherSpec');
        return;
      }
      if (f.contentType == _ctAlert) {
        throw StateError('server sent alert: ${_hex(f.record.sublist(13))}');
      }
      // Any other type is unexpected here.
      throw StateError(
          'unexpected content type ${f.contentType} while expecting CCS');
    }
  }

  // -------- Helpers --------

  Uint8List _concatTranscript({required bool includeFinished}) {
    final bb = BytesBuilder();
    for (final t in _transcriptOrder) {
      // sent vs received is determined by which map it lives in.
      final s = _sent[t];
      final r = _recv[t];
      final msg = s ?? r;
      if (msg == null) {
        throw StateError('transcript missing handshake type $t');
      }
      bb.add(msg);
    }
    if (includeFinished) {
      final fin = _sent[_hsTypeFinished];
      if (fin == null) throw StateError('client Finished not in transcript');
      bb.add(fin);
    }
    return bb.toBytes();
  }

  static List<int> _be16(int v) => [(v >> 8) & 0xFF, v & 0xFF];

  static List<int> _uint24(int v) =>
      [(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

  static List<int> _uint48(int v) => [
        (v >> 40) & 0xFF,
        (v >> 32) & 0xFF,
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ];

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static bool _constTimeEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }
}

class _Frame {
  final int contentType;
  final int epoch;
  final Uint8List record;
  _Frame(
      {required this.contentType, required this.epoch, required this.record});
}

/// Per-`message_seq` reassembly buffer for fragmented handshake messages.
class _Reasm {
  final int hsType;
  final int length;
  final Uint8List buffer;
  int received = 0;
  _Reasm({required this.hsType, required this.length})
      : buffer = Uint8List(length);
}

/// Best-effort enlargement of the UDP receive buffer.
void _trySetRcvBuf(RawDatagramSocket s, int size) {
  // SOL_SOCKET / SO_RCVBUF differ across platforms.
  // Linux:   level=1   option=8
  // macOS:   level=0xffff option=0x1002
  // Windows: level=0xffff option=0x1002
  final attempts = <List<int>>[
    if (Platform.isLinux) [1, 8],
    if (Platform.isMacOS || Platform.isWindows) [0xffff, 0x1002],
  ];
  for (final lvlOpt in attempts) {
    try {
      s.setRawOption(RawSocketOption.fromInt(lvlOpt[0], lvlOpt[1], size));
      return;
    } catch (_) {
      // try next
    }
  }
}

// -------- Demo entry point --------

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : '127.0.0.1';
  final port = args.length > 1 ? int.parse(args[1]) : 4444;

  final client = DtlsClient(InternetAddress(host), port);
  try {
    await client.connect();
    print('[client] handshake OK');
    // Send a small piece of application data after the handshake.
    await client.sendApplicationData(
        Uint8List.fromList('hello from dart dtls client'.codeUnits));
    await Future<void>.delayed(const Duration(seconds: 1));
  } finally {
    await client.close();
  }
}
