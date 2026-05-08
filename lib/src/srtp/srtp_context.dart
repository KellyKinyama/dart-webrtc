import 'dart:typed_data';

import 'rtp2.dart'; // Changed import
import 'constants.dart';
import 'crypto_gcm.dart';
import 'protection_profiles.dart';

class SRTPContext {
  // final InternetAddress addr;
  // final RawDatagramSocket conn;
  final ProtectionProfile protectionProfile;

  /// Cipher used to decrypt traffic *received* from the peer.
  GCM? inboundGcm;

  /// Cipher used to encrypt traffic *sent* to the peer.
  GCM? outboundGcm;

  /// Backward-compatible alias. Older call sites assigned a single `gcm`
  /// cipher and used it for both directions; we mirror writes to both
  /// inbound and outbound so existing code keeps working.
  GCM? get gcm => inboundGcm;
  set gcm(GCM? v) {
    inboundGcm = v;
    outboundGcm ??= v;
  }

  final Map<int, SsrcState> srtpSsrcStates; // For decryption
  final Map<int, SsrcStateEncryption>
      srtpSsrcStatesEncryption; // For encryption

  /// Per-SSRC outbound SRTCP index counter (31-bit, monotonically increasing).
  final Map<int, int> _srtcpOutIndex = {};

  SRTPContext({
    // required this.addr,
    // required this.conn,
    required this.protectionProfile,
  })  : srtpSsrcStates = {},
        srtpSsrcStatesEncryption = {}; // Initialize new map

  // For decryption
  SsrcState _getSrtpSsrcState(int ssrc) {
    if (srtpSsrcStates.containsKey(ssrc)) {
      return srtpSsrcStates[ssrc]!;
    }
    final s = SsrcState(ssrc: ssrc);
    srtpSsrcStates[ssrc] = s;
    return s;
  }

  // For encryption
  SsrcStateEncryption _getSrtpSsrcStateForEncryption(int ssrc) {
    if (srtpSsrcStatesEncryption.containsKey(ssrc)) {
      return srtpSsrcStatesEncryption[ssrc]!;
    }
    final s = SsrcStateEncryption(ssrc: ssrc);
    srtpSsrcStatesEncryption[ssrc] = s;
    return s;
  }

  Future<Uint8List> decryptRtpPacket(Packet packet) async {
    final cipher = inboundGcm;
    if (cipher == null) {
      throw Exception("GCM cipher not initialized for SRTPContext (inbound)");
    }

    final SsrcState s = _getSrtpSsrcState(packet.header.ssrc);
    final RolloverCountResult rocResult =
        s.nextRolloverCount(packet.header.sequenceNumber);

    // The decrypt method in GCM returns the full decrypted packet (header + payload)
    final Uint8List result = await cipher.decrypt(packet, rocResult.roc);
    rocResult.updateRoc(); // Update decryption ROC after successful decryption
    // Return only the payload portion
    // return Uint8List.fromList(result.sublist(packet.headerSize));
    return result;
  }

  Future<Uint8List> encryptRtpPacket(Packet packet) async {
    final cipher = outboundGcm;
    if (cipher == null) {
      throw Exception("GCM cipher not initialized for SRTPContext (outbound)");
    }

    final SsrcStateEncryption s =
        _getSrtpSsrcStateForEncryption(packet.header.ssrc);

    // Update the ROC and sequence number for encryption
    // This logic ensures a monotonically increasing 48-bit index.
    if (s.lastSequenceNumber != -1 &&
        packet.header.sequenceNumber <= s.lastSequenceNumber) {
      // Sequence number has wrapped around (or reset unexpectedly), increment ROC
      s.roc++;
    }
    s.lastSequenceNumber = packet.header.sequenceNumber;

    final Uint8List result = await cipher.encrypt(packet, s.roc);
    return result;
  }

  /// Encrypt a full RTCP packet [rtcp] using the outbound cipher. The
  /// per-SSRC SRTCP index is allocated automatically.
  Future<Uint8List> encryptRtcpPacket(Uint8List rtcp) async {
    final cipher = outboundGcm;
    if (cipher == null) {
      throw Exception('GCM cipher not initialized for SRTPContext (outbound)');
    }
    if (rtcp.length < 8) {
      throw Exception('RTCP packet too short');
    }
    final ssrc = ByteData.sublistView(rtcp, 4, 8).getUint32(0, Endian.big);
    final next = ((_srtcpOutIndex[ssrc] ?? 0) + 1) & 0x7FFFFFFF;
    _srtcpOutIndex[ssrc] = next;
    return cipher.encryptRtcp(rtcp, next);
  }

  /// Decrypt a full SRTCP packet [srtcp] using the inbound cipher.
  Future<Uint8List> decryptRtcpPacket(Uint8List srtcp) async {
    final cipher = inboundGcm;
    if (cipher == null) {
      throw Exception('GCM cipher not initialized for SRTPContext (inbound)');
    }
    return cipher.decryptRtcp(srtcp);
  }
}

class SsrcState {
  final int ssrc;
  int index;
  bool rolloverHasProcessed;

  SsrcState({
    required this.ssrc,
    this.index = 0,
    this.rolloverHasProcessed = false,
  });

  RolloverCountResult nextRolloverCount(int sequenceNumber) {
    final int seq = sequenceNumber;
    final int localRoc = index >> 16;
    final int localSeq = index & (seqNumMax - 1);

    int guessRoc = localRoc;
    int difference = 0;

    if (rolloverHasProcessed) {
      if (index > seqNumMedian) {
        if (localSeq < seqNumMedian) {
          if (seq - localSeq > seqNumMedian) {
            guessRoc = localRoc - 1;
            difference = seq - localSeq - seqNumMax;
          } else {
            guessRoc = localRoc;
            difference = seq - localSeq;
          }
        } else {
          if (localSeq - seqNumMedian > seq) {
            guessRoc = localRoc + 1;
            difference = seq - localSeq + seqNumMax;
          } else {
            guessRoc = localRoc;
            difference = seq - localSeq;
          }
        }
      } else {
        // localRoc is equal to 0
        difference = seq - localSeq;
      }
    }

    Function updateRoc = () {
      if (!rolloverHasProcessed) {
        index |= sequenceNumber;
        rolloverHasProcessed = true;
        return;
      }
      if (difference > 0) {
        index += difference;
      }
    };

    return RolloverCountResult(guessRoc, updateRoc);
  }
}

class RolloverCountResult {
  final int roc;
  final Function updateRoc;

  RolloverCountResult(this.roc, this.updateRoc);
}

class SsrcStateEncryption {
  final int ssrc;
  int roc; // Roll-over counter
  int lastSequenceNumber; // Last sequence number seen for encryption

  SsrcStateEncryption({
    required this.ssrc,
    this.roc = 0,
    this.lastSequenceNumber = -1, // -1 indicates no sequence number seen yet
  });
}
