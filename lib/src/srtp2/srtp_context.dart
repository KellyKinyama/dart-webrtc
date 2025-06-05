import 'dart:io';
import 'dart:typed_data';

import 'rtp_packet.dart';
import 'constants.dart';
import 'crypto_gcm.dart';
import 'protection_profiles.dart';

class SRTPContext {
  final InternetAddress addr;
  final RawDatagramSocket conn;
  final ProtectionProfile protectionProfile;
  GCM? gcm;
  final Map<int, SsrcState> srtpSsrcStates; // For decryption
  final Map<int, SsrcStateEncryption>
      srtpSsrcStatesEncryption; // For encryption

  SRTPContext({
    required this.addr,
    required this.conn,
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
    if (gcm == null) {
      throw Exception("GCM cipher not initialized for SRTPContext");
    }

    final SsrcState s = _getSrtpSsrcState(packet.header.ssrc);
    final RolloverCountResult rocResult =
        s.nextRolloverCount(packet.header.sequenceNumber);

    final Uint8List result = await gcm!.decrypt(packet, rocResult.roc);
    rocResult.updateRoc(); // Update decryption ROC after successful decryption
    return Uint8List.fromList(result.sublist(packet.headerSize));
  }

  Future<Uint8List> encryptRtpPacket(Packet packet) async {
    if (gcm == null) {
      throw Exception("GCM cipher not initialized for SRTPContext");
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

    final Uint8List result = await gcm!.encrypt(packet, s.roc);
    return result;
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
  int roc; // Rollover counter for encryption
  int lastSequenceNumber; // Last sequence number sent for this SSRC

  SsrcStateEncryption({
    required this.ssrc,
    this.roc = 0, // Start ROC at 0 for new streams
    this.lastSequenceNumber = -1, // -1 indicates no packet sent yet
  });
}
