import 'dart:io';
import 'dart:typed_data';

import 'package:dartls/src/rtp/rtp_packet.dart';
import 'package:dartls/src/srtp/crypto_gcm.dart';

import 'protection_profiles.dart';

class SRTPContext {
  // Addr              *net.UDPAddr
  RawDatagramSocket conn; //              *net.UDPConn
  ProtectionProfile protectionProfile;
 late GCM gcm;
  Map<int, SrtpSSRCState> srtpSSRCStates; //   map[uint32]*srtpSSRCState

  SRTPContext(this.conn, this.protectionProfile, this.srtpSSRCStates);

  // https://github.com/pion/srtp/blob/3c34651fa0c6de900bdc91062e7ccb5992409643/context.go#L159
  SrtpSSRCState getSRTPSSRCState(int ssrc) {
    SrtpSSRCState? s = srtpSSRCStates[ssrc];
    if (s != null) {
      return s;
    }

    s = srtpSSRCStates[ssrc] = SrtpSSRCState(ssrc);
    return s;
  }

// https://github.com/pion/srtp/blob/3c34651fa0c6de900bdc91062e7ccb5992409643/srtp.go#L8
  Future<Uint8List> decryptRTPPacket(RtpPacket packet) async {
    final s = getSRTPSSRCState(packet.header.ssrc);
    final (roc, updateROC) = s.nextRolloverCount(packet.header.sequenceNumber);
    final result = await gcm.decrypt(packet, roc);
    // if err != nil {
    // 	return nil, err
    // }
    updateROC();
    return result.sublist(packet.headerSize);
    ;
  }
}

class SrtpSSRCState {
  int ssrc; //                 uint32
  late int index; //                uint64
  late bool rolloverHasProcessed; // bool
  SrtpSSRCState(this.ssrc);

  (int, Function) nextRolloverCount(int sequenceNumber) {
    final seq = sequenceNumber;
    final localRoc = index >> 16;
    final localSeq = index & (seqNumMax - 1);

    int guessRoc = localRoc;
    int difference = 0;

    if (rolloverHasProcessed) {
      // When localROC is equal to 0, and entering seq-localSeq > seqNumMedian
      // judgment, it will cause guessRoc calculation error
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

    return (
      guessRoc,
      () {
        if (!rolloverHasProcessed) {
          index |= sequenceNumber;
          rolloverHasProcessed = true;
          return;
        }
        if (difference > 0) {
          index += difference;
        }
      }
    );
  }
}
