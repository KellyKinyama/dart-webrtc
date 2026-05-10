// G.711 A-law (PCMA) codec + RTP packetization helpers.
//
// PCMA is a static-payload-type-8 audio codec defined by RFC 3551 §4.5.14.
// The payload is just a stream of 8-bit A-law samples — one sample per
// byte, no framing. RTP wraps each 20 ms slice (160 samples at 8 kHz)
// in a standard 12-byte header with the timestamp clock = sample rate.
//
// This file exposes:
//   * `linearToAlaw` / `alawToLinear` — sample-level conversions.
//   * `pcmToAlaw` / `alawToPcm`       — buffer-level conversions.
//   * `PcmaRtpPacketizer`             — bytes → RTP wire packets.
//   * `decodePcmaRtpPayload`          — RTP payload bytes → 16-bit PCM.

import 'dart:typed_data';

/// PCMA static RTP payload type (RFC 3551).
const int kPcmaPayloadType = 8;

/// PCMA sample rate in Hz.
const int kPcmaClockRate = 8000;

/// One PCMA sample is one byte; default packetization is 20 ms = 160 samples.
const int kPcmaSamplesPer20Ms = 160;

// ---------------------------------------------------------------------------
// Sample-level A-law <-> linear conversions.
//
// Reference: ITU-T G.711, "Pseudo-code for A-law to linear conversion".
// ---------------------------------------------------------------------------

/// Encode one signed 16-bit linear PCM sample to an 8-bit A-law byte.
int linearToAlaw(int pcm16) {
  // Clamp to int16 range.
  if (pcm16 > 32767) pcm16 = 32767;
  if (pcm16 < -32768) pcm16 = -32768;

  int sign = 0x80;
  int sample = pcm16;
  if (sample < 0) {
    sample = -sample;
    sign = 0x00;
  }
  // A-law encodes a 13-bit magnitude; drop the bottom 3 bits.
  if (sample > 32635) sample = 32635;

  int exponent;
  int mantissa;
  if (sample >= 256) {
    exponent = 7;
    for (int mask = 0x4000; (sample & mask) == 0 && exponent > 0; mask >>= 1) {
      exponent--;
    }
    mantissa = (sample >> (exponent + 3)) & 0x0F;
    final encoded = ((exponent << 4) | mantissa) | sign;
    return encoded ^ 0x55;
  } else {
    mantissa = sample >> 4;
    return (mantissa | sign) ^ 0x55;
  }
}

/// Decode one A-law byte back to a signed 16-bit linear PCM sample.
int alawToLinear(int alaw) {
  alaw ^= 0x55;
  final sign = alaw & 0x80;
  final exponent = (alaw & 0x70) >> 4;
  final mantissa = alaw & 0x0F;
  int sample;
  if (exponent == 0) {
    sample = (mantissa << 4) + 8;
  } else {
    sample = ((mantissa << 4) + 0x108) << (exponent - 1);
  }
  return sign != 0 ? sample : -sample;
}

/// Encode a buffer of 16-bit signed PCM samples to A-law bytes.
Uint8List pcmToAlaw(Int16List pcm) {
  final out = Uint8List(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    out[i] = linearToAlaw(pcm[i]);
  }
  return out;
}

/// Decode A-law bytes to 16-bit signed PCM samples.
Int16List alawToPcm(Uint8List alaw) {
  final out = Int16List(alaw.length);
  for (var i = 0; i < alaw.length; i++) {
    out[i] = alawToLinear(alaw[i]);
  }
  return out;
}

// ---------------------------------------------------------------------------
// RTP packetization.
// ---------------------------------------------------------------------------

/// Builds RTP packets carrying PCMA payloads.
///
/// One instance per outbound stream — it owns the rolling 16-bit sequence
/// number and 32-bit RTP timestamp.
class PcmaRtpPacketizer {
  /// SSRC for this stream.
  final int ssrc;

  /// Static payload type. Defaults to 8 (PCMA).
  final int payloadType;

  int _seq;
  int _timestamp;

  PcmaRtpPacketizer({
    required this.ssrc,
    this.payloadType = kPcmaPayloadType,
    int initialSequenceNumber = 0,
    int initialTimestamp = 0,
  })  : _seq = initialSequenceNumber & 0xFFFF,
        _timestamp = initialTimestamp & 0xFFFFFFFF;

  /// Current 16-bit sequence number (next packet uses this value).
  int get sequenceNumber => _seq;

  /// Current 32-bit RTP timestamp (next packet uses this value).
  int get timestamp => _timestamp;

  /// Wrap a single A-law payload (one frame's worth of samples) in an RTP
  /// packet and advance the sequence number / timestamp counters.
  ///
  /// The timestamp is incremented by `samples.length` because the PCMA
  /// clock rate is 1 tick per sample.
  Uint8List packetize(Uint8List alawPayload, {bool marker = false}) {
    final packet = Uint8List(12 + alawPayload.length);
    final view = ByteData.view(packet.buffer);

    // V=2, P=0, X=0, CC=0
    packet[0] = 0x80;
    // M | PT
    packet[1] = ((marker ? 1 : 0) << 7) | (payloadType & 0x7F);
    view.setUint16(2, _seq, Endian.big);
    view.setUint32(4, _timestamp, Endian.big);
    view.setUint32(8, ssrc, Endian.big);
    packet.setRange(12, packet.length, alawPayload);

    _seq = (_seq + 1) & 0xFFFF;
    _timestamp = (_timestamp + alawPayload.length) & 0xFFFFFFFF;
    return packet;
  }
}

/// Parsed RTP packet view (just enough fields for PCMA depacketization).
class PcmaRtpPacket {
  final int payloadType;
  final int sequenceNumber;
  final int timestamp;
  final int ssrc;
  final bool marker;
  final Uint8List payload;

  const PcmaRtpPacket({
    required this.payloadType,
    required this.sequenceNumber,
    required this.timestamp,
    required this.ssrc,
    required this.marker,
    required this.payload,
  });
}

/// Parse a raw RTP packet and surface the PCMA payload + key header fields.
///
/// Returns null if the buffer is too short to be a valid RTP packet.
/// Honors the CSRC count, the X (extension) bit and the P (padding) bit so
/// that arbitrary upstream packetizers round-trip cleanly.
PcmaRtpPacket? parsePcmaRtpPacket(Uint8List bytes) {
  if (bytes.length < 12) return null;
  final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);

  final b0 = bytes[0];
  final version = (b0 >> 6) & 0x03;
  if (version != 2) return null;
  final padding = ((b0 >> 5) & 0x01) == 1;
  final extension = ((b0 >> 4) & 0x01) == 1;
  final csrcCount = b0 & 0x0F;

  final b1 = bytes[1];
  final marker = ((b1 >> 7) & 0x01) == 1;
  final payloadType = b1 & 0x7F;
  final sequenceNumber = view.getUint16(2, Endian.big);
  final timestamp = view.getUint32(4, Endian.big);
  final ssrc = view.getUint32(8, Endian.big);

  var payloadStart = 12 + csrcCount * 4;
  if (extension) {
    if (bytes.length < payloadStart + 4) return null;
    final extLenWords = view.getUint16(payloadStart + 2, Endian.big);
    payloadStart += 4 + extLenWords * 4;
  }
  if (payloadStart > bytes.length) return null;

  var payloadEnd = bytes.length;
  if (padding) {
    if (payloadEnd <= payloadStart) return null;
    final padLen = bytes[payloadEnd - 1];
    payloadEnd -= padLen;
    if (payloadEnd < payloadStart) return null;
  }

  return PcmaRtpPacket(
    payloadType: payloadType,
    sequenceNumber: sequenceNumber,
    timestamp: timestamp,
    ssrc: ssrc,
    marker: marker,
    payload: Uint8List.sublistView(bytes, payloadStart, payloadEnd),
  );
}

/// Convenience: parse an RTP packet and decode its PCMA payload to PCM.
/// Returns null if the packet is malformed or the payload type doesn't
/// match [expectedPayloadType] (default = 8, the static PCMA PT).
Int16List? decodePcmaRtpPayload(
  Uint8List rtpBytes, {
  int expectedPayloadType = kPcmaPayloadType,
}) {
  final pkt = parsePcmaRtpPacket(rtpBytes);
  if (pkt == null) return null;
  if (pkt.payloadType != expectedPayloadType) return null;
  return alawToPcm(pkt.payload);
}
