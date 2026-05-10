import 'dart:typed_data';

import '../../dtls3/extensions.dart';
import '../crypto/crypto_ccm.dart';
import '../crypto/crypto_ccm8.dart';

import '../crypto/crypto_gcm5.dart';
import '../dtls_state.dart';
import '../enums.dart';
// import 'extension.dart';
import 'handshake.dart';

import '../key_exchange_algorithm.dart';
import 'extensions/extensions.dart';
import 'tls_random.dart';

class HandshakeContext {
  Flight flight = Flight.Flight0;

  late Uint8List serverKeySignature;

  DTLSState dTLSState = DTLSState.DTLSStateNew;

  late ProtocolVersion protocolVersion;

  late Uint8List cookie;

  late int cipherSuite;

  late TlsRandom clientRandom;

  late TlsRandom serverRandom;

  late Uint8List serverPublicKey;

  late Uint8List serverPrivateKey;

  late int curve;

  late Uint8List expectedFingerprintHash;

  List<Uint8List> clientCertificates = [];

  var clientKeyExchangePublic;

  bool isCipherSuiteInitialized = false;

  Map<HandshakeType, Uint8List> HandshakeMessagesReceived = {};

  /// Reassembly buffers for fragmented handshake messages, keyed by the
  /// handshake `message_sequence` field. Each entry holds the full message
  /// body being reconstructed plus a covered-range bitmap.
  final Map<int, HandshakeReassembly> handshakeFragments = {};

  Map<HandshakeType, Uint8List> HandshakeMessagesSent = {};

  late Uint8List serverMasterSecret;

  int serverSequenceNumber = 0;

  int serverHandshakeSequenceNumber = 0;

  late Uint8List extensionsData;

  void increaseServerSequence() {
    serverSequenceNumber++;
  }

  void increaseServerHandshakeSequence() {
    serverHandshakeSequenceNumber++;
  }

  int serverEpoch = 0;

  bool UseExtendedMasterSecret = false;

  late int srtpProtectionProfile;

  int clientEpoch = 0;

  late Uint8List session_id;

  Uint8List? keyingMaterialCache;

  Map<ExtensionTypeValue, Extension> extensions = {};

  var compression_methods;

  late GCM gcm;

  late CCM ccm;

  late CCM8 ccm8;
  void increaseServerEpoch() {
    serverEpoch++;
    serverSequenceNumber = 0;
  }

  // https://github.com/pion/dtls/blob/bee42643f57a7f9c85ee3aa6a45a4fa9811ed122/state.go#L182
  Uint8List exportKeyingMaterial(int length)
// ([]byte, error)
  {
    if (keyingMaterialCache != null) {
      return keyingMaterialCache!;
    }
    final encodedClientRandom = clientRandom.raw();
    final encodedServerRandom = serverRandom.marshal();
    // var err error
    print(
        "Exporting keying material from DTLS context (<u>expected length: $length)...");
    keyingMaterialCache = generateKeyingMaterial(
        serverMasterSecret, encodedClientRandom, encodedServerRandom, length);
    // if err != nil {
    // 	return nil, err
    // }
    return keyingMaterialCache!;
  }
}

/// State for reassembling a single fragmented DTLS handshake message.
///
/// DTLS allows a handshake message to be split across multiple records
/// (RFC 6347 §4.2.3). Each fragment carries the same `message_sequence`
/// and the total `length`, plus its own `fragment_offset` /
/// `fragment_length` window into the full body. We accept fragments in
/// any order, deduplicate overlap, and surface the message only once
/// every byte of the body has been delivered at least once.
class HandshakeReassembly {
  final int handshakeTypeValue;
  final int totalLength;
  final Uint8List body;
  // Inclusive-exclusive `[start, end)` ranges that have been received.
  final List<List<int>> coveredRanges = [];

  HandshakeReassembly(this.handshakeTypeValue, this.totalLength)
      : body = Uint8List(totalLength);

  /// Copies [fragmentBytes] into [body] at [fragmentOffset] and returns
  /// true once the entire body has been covered. Out-of-range fragments
  /// are silently clipped.
  bool addFragment(int fragmentOffset, Uint8List fragmentBytes) {
    if (fragmentOffset >= totalLength) return _isComplete();
    final end = fragmentOffset + fragmentBytes.length > totalLength
        ? totalLength
        : fragmentOffset + fragmentBytes.length;
    final copyLen = end - fragmentOffset;
    body.setRange(fragmentOffset, end, fragmentBytes);

    // Merge into coveredRanges.
    coveredRanges.add([fragmentOffset, fragmentOffset + copyLen]);
    coveredRanges.sort((a, b) => a[0].compareTo(b[0]));
    final merged = <List<int>>[];
    for (final r in coveredRanges) {
      if (merged.isEmpty || r[0] > merged.last[1]) {
        merged.add([r[0], r[1]]);
      } else if (r[1] > merged.last[1]) {
        merged.last[1] = r[1];
      }
    }
    coveredRanges
      ..clear()
      ..addAll(merged);

    return _isComplete();
  }

  bool _isComplete() =>
      coveredRanges.length == 1 &&
      coveredRanges[0][0] == 0 &&
      coveredRanges[0][1] == totalLength;
}
