import 'dart:io';
import 'dart:typed_data';
import 'package:pointycastle/src/platform_check/platform_check.dart';

import 'rtp2.dart'; // Assuming rtp2.dart provides the Packet and Header classes
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

  Future<Uint8List> decryptRtpPacket(
      Packet rtpPacket, Uint8List encryptedRtpPacket) async {
    if (gcm == null) {
      throw Exception("GCM cipher not initialized for decryption.");
    }

    final ssrcState = _getSrtpSsrcState(rtpPacket.header.ssrc);
    final rocResult = ssrcState.rolloverCount(rtpPacket.header.sequenceNumber);
    final roc = rocResult.roc;
    rocResult.updateRoc();

    final headerBytes = rtpPacket.header.marshal(); // Assuming marshal returns Uint8List
    final payloadBytes = encryptedRtpPacket.sublist(headerBytes.length);

    final decryptedPayload = gcm!.decrypt(
        gcm!.getSRTPKey(),
        gcm!.getSRTPSalt(),
        roc,
        rtpPacket.header.sequenceNumber,
        headerBytes,
        payloadBytes,
        protectionProfile.aeadAuthTagLength());

    return decryptedPayload;
  }

  Future<Uint8List> encryptRtpPacket(Packet rtpPacket) async {
    if (gcm == null) {
      throw Exception("GCM cipher not initialized for encryption.");
    }

    final ssrcState = _getSrtpSsrcStateForEncryption(rtpPacket.header.ssrc);

    // Update sequence number and rollover counter for encryption
    ssrcState.incrementSequenceNumber();
    if (rtpPacket.header.sequenceNumber != ssrcState.sequenceNumber) {
      // This case handles initial setup or if an external force changes the sequence number
      rtpPacket.header.sequenceNumber = ssrcState.sequenceNumber;
    }

    final roc = ssrcState.rolloverCounter;

    final headerBytes = rtpPacket.header.marshal(); // Assuming marshal returns Uint8List
    final payloadBytes = rtpPacket.payload;

    final encryptedPayloadWithTag = gcm!.encrypt(
        gcm!.getSRTPKey(),
        gcm!.getSRTPSalt(),
        roc,
        rtpPacket.header.sequenceNumber,
        headerBytes,
        payloadBytes,
        protectionProfile.aeadAuthTagLength());

    // Combine header and encrypted payload with tag
    final Uint8List encryptedPacket = Uint8List(headerBytes.length + encryptedPayloadWithTag.length);
    encryptedPacket.setAll(0, headerBytes);
    encryptedPacket.setAll(headerBytes.length, encryptedPayloadWithTag);

    return encryptedPacket;
  }

  Future<Uint8List> decryptRtcpPacket(
      Uint8List rtcpPacket, Uint8List encryptedRtcpPacket) async {
    if (gcm == null) {
      throw Exception("GCM cipher not initialized for decryption.");
    }

    // RTCP decryption is slightly different as there's no sequence number in the same way as RTP.
    // The SRTP specification defines a special handling for RTCP with SRTP.
    // For GCM, the header is part of the AAD. The ROC and sequence number are implicitly handled
    // by the RTCP packet's length and a fixed part of the nonce.
    // This is a simplified approach, a full RTCP SRTP implementation needs careful adherence to RFC 3711 and RFC 7714.

    // Extract SSRC from RTCP packet (assuming it's at offset 4 for common RTCP packet types)
    final ssrc = ByteData.view(rtcpPacket.buffer)
        .getUint32(RTCP_SSRC_OFFSET, Endian.big);
    final ssrcState = _getSrtpSsrcState(ssrc); // Use the same SSRC state for both

    // The RTCP packet itself (excluding the authentication tag) forms the AAD for GCM.
    // The nonce for RTCP is also derived from the master salt and a fixed value.
    // For simplicity, let's assume the full RTCP packet (before the implicit trailer) is the AAD.

    final headerAndPayload = encryptedRtcpPacket.sublist(0, encryptedRtcpPacket.length - protectionProfile.aeadAuthTagLength());
    final tag = encryptedRtcpPacket.sublist(encryptedRtcpPacket.length - protectionProfile.aeadAuthTagLength());

    // For RTCP, the nonce uses a specific derivation, often based on the SSRC and ROC for RTCP.
    // RFC 3711 Section 3.2.1 specifies the session key derivation for RTCP.
    // RFC 7714 Section 3.3 for GCM nonce construction for RTCP.
    // This is a placeholder and needs to be implemented accurately.

    // A common approach for RTCP is to use a fixed value (0x00) for the sequence number in nonce derivation for RTCP.
    final decryptedPayload = gcm!.decrypt(
        gcm!.getSRTCPKey(),
        gcm!.getSRTCPSalt(),
        ssrcState.rolloverCounter, // Use the ROC from the SSRC state
        0x00, // Fixed sequence number for RTCP nonce derivation (as per RFC)
        headerAndPayload, // Full RTCP packet (excluding auth tag) as AAD
        encryptedRtcpPacket, // Pass the whole encrypted packet with tag
        protectionProfile.aeadAuthTagLength());

    return decryptedPayload;
  }

  Future<Uint8List> encryptRtcpPacket(Uint8List rtcpPacket) async {
    if (gcm == null) {
      throw Exception("GCM cipher not initialized for encryption.");
    }

    // Extract SSRC from RTCP packet (assuming it's at offset 4 for common RTCP packet types)
    final ssrc = ByteData.view(rtcpPacket.buffer)
        .getUint32(RTCP_SSRC_OFFSET, Endian.big);
    final ssrcState = _getSrtpSsrcStateForEncryption(ssrc); // Use encryption SSRC state

    // Increment RTCP rollover counter if necessary (based on RTCP compound packet rules and SRTP context)
    // This is a simplified approach, a full RTCP SRTP implementation needs careful adherence to RFC 3711 and RFC 7714.
    ssrcState.incrementRtcpRolloverCounter();

    // The full RTCP packet forms the AAD for GCM.
    final headerAndPayload = rtcpPacket;

    final encryptedPayloadWithTag = gcm!.encrypt(
        gcm!.getSRTCPKey(),
        gcm!.getSRTCPSalt(),
        ssrcState.rtcpRolloverCounter,
        0x00, // Fixed sequence number for RTCP nonce derivation
        headerAndPayload,
        rtcpPacket, // The payload to encrypt is the RTCP packet itself
        protectionProfile.aeadAuthTagLength());

    return encryptedPayloadWithTag;
  }
}

class SsrcState {
  final int ssrc;
  int rolloverCounter;
  int sequenceNumber; // Last seen sequence number

  SsrcState({required this.ssrc, this.rolloverCounter = 0, this.sequenceNumber = 0});

  RolloverCountResult rolloverCount(int seq) {
    int guessRoc = rolloverCounter;
    int difference = 0;

    if (sequenceNumber == 0) {
      // First packet seen
      sequenceNumber = seq;
    } else {
      if (seq - sequenceNumber > seqNumMedian) {
        if (sequenceNumber < seqNumMedian) {
          guessRoc--;
          difference = seq - sequenceNumber - seqNumMax;
        } else {
          guessRoc = rolloverCounter;
          difference = seq - sequenceNumber;
        }
      } else if (sequenceNumber - seqNumMedian > seq) {
        guessRoc++;
        difference = seq - sequenceNumber + seqNumMax;
      } else {
        guessRoc = rolloverCounter;
        difference = seq - sequenceNumber;
      }
    }

    Function updateRoc = () {
      if (difference > 0) {
        sequenceNumber = seq;
        rolloverCounter += difference;
      } else if (difference < 0) {
        // This case should ideally not happen for a valid SRTP stream
        // where sequence numbers are increasing. If it does, it might indicate
        // a replay or out-of-order packet.
        // For decryption, we only update if the new packet is "more recent"
        // in terms of ROC or sequence number.
        if (guessRoc > rolloverCounter ||
            (guessRoc == rolloverCounter && seq > sequenceNumber)) {
          rolloverCounter = guessRoc;
          sequenceNumber = seq;
        }
      } else {
        sequenceNumber = seq;
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
  int rolloverCounter;
  int sequenceNumber; // Next sequence number to use for encryption
  int rtcpRolloverCounter; // Rollover counter for RTCP encryption

  SsrcStateEncryption({
    required this.ssrc,
    this.rolloverCounter = 0,
    this.sequenceNumber = 0,
    this.rtcpRolloverCounter = 0,
  });

  void incrementSequenceNumber() {
    sequenceNumber++;
    if (sequenceNumber >= seqNumMax) {
      sequenceNumber = 0;
      rolloverCounter++;
    }
  }

  void incrementRtcpRolloverCounter() {
    rtcpRolloverCounter++;
  }
}