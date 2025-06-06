import 'dart:typed_data';
import 'rtp2.dart';

// Assuming you have Header and Extension classes and related constants/errors defined as in the previous response.
// If not, please make sure they are in the same file or imported correctly.

// If you haven't already, define your RtpError class:
class RtpError implements Exception {
  final String message;
  const RtpError(this.message);

  @override
  String toString() => 'RtpError: $message';

  static const RtpError headerSizeInsufficient =
      RtpError('Header size insufficient');
  static const RtpError headerSizeInsufficientForExtension =
      RtpError('Header size insufficient for extension');
  static const RtpError malformedExtension =
      RtpError('Malformed RTP extension');
  static const RtpError shortPacket =
      RtpError('Short packet'); // Corresponds to ErrShortPacket
}

/// Represents an RTP Packet
/// NOTE: raw is not directly stored in Dart, as Uint8List views handle this.
class Packet {
  Header header;
  Uint8List payload;

  Packet({
    required this.header,
    required this.payload,
  });

  // Default constructor for convenience, similar to Rust's Default trait
  factory Packet.createEmpty() {
    return Packet(
        header: Header(
          version: 0,
          padding: false,
          extension: false,
          marker: false,
          payloadType: 0,
          sequenceNumber: 0,
          timestamp: 0,
          ssrc: 0,
        ),
        payload: Uint8List(0));
  }

  @override
  String toString() {
    String out = "RTP PACKET:\n";
    out += "\tVersion: ${header.version}\n";
    out += "\tMarker: ${header.marker}\n";
    out += "\tPayload Type: ${header.payloadType}\n";
    out += "\tSequence Number: ${header.sequenceNumber}\n";
    out += "\tTimestamp: ${header.timestamp}\n";
    out += "\tSSRC: ${header.ssrc} (${header.ssrc.toRadixString(16)})\n";
    out += "\tPayload Length: ${payload.length}\n";
    return out;
  }

  /// Unmarshal parses the passed byte slice and stores the result in the Packet this method is called upon
  /// Returns the unmarshalled Packet or throws an RtpError.
  static Packet unmarshal(Uint8List rawPacket) {
    // Rust's `Header::unmarshal(raw_packet)?` means:
    // 1. Call Header::unmarshal, passing the *same* mutable buffer.
    // 2. Header::unmarshal will read its portion and advance the buffer's internal cursor.
    // 3. If Header::unmarshal returns an error, propagate it.
    //
    // In Dart, we replicate this by explicitly managing the offset.

    final (header, headerLen) = Header.unmarshal(rawPacket, initialOffset: 0);

    // After unmarshalling the header, the 'remaining' part of the rawPacket is the payload.
    // Rust's `raw_packet.remaining()` is equivalent to `rawPacket.length - headerLen`.
    int payloadLen = rawPacket.length - headerLen;

    // Rust's `raw_packet.copy_to_bytes(payload_len)` copies the remaining bytes.
    // In Dart, we can get a sublist (copy) or a view (no copy) of the remaining bytes.
    // For payload, a copy is often safer if the original buffer might be reused/modified.
    // If performance is critical and payload won't be mutated, use Uint8List.view.
    Uint8List payload = rawPacket.sublist(headerLen, headerLen + payloadLen);

    if (header.padding) {
      if (payloadLen > 0) {
        // Rust: let padding_len = payload[payload_len - 1] as usize;
        // In Dart, payloadLen - 1 is the last byte index.
        final int paddingLen = payload[payloadLen - 1];

        if (paddingLen <= payloadLen) {
          return Packet(
            header: header,
            // Rust: payload.slice(..payload_len - padding_len)
            // Dart: Creates a sublist from the start up to (but not including) the padding bytes.
            payload: payload.sublist(0, payloadLen - paddingLen),
          );
        } else {
          throw RtpError.shortPacket;
        }
      } else {
        // Payload length is 0 but padding flag is set, which is an error.
        throw RtpError.shortPacket;
      }
    } else {
      // No padding, so the entire remaining part is the actual payload.
      return Packet(header: header, payload: payload);
    }
  }
}

// --- Example Usage (similar to main in previous response) ---
void main() {
  // Test case with a one-byte extension (from previous example)
  // V=2, P=0, X=1, CC=0, M=1, PT=96, Seq=1, TS=1000, SSRC=12345
  // Extension: 0xBEDE (one-byte profile), length 1 (1*4=4 bytes)
  // Extension data: 0x11 (ID 1, L=1), 0x22 (payload). Then 0x33, 0x00 (padding to align to 4-byte words)
  // Total Header Length: 12 (fixed) + 4 (ext header) + 4 (ext data) = 20 bytes
  // Add some dummy payload data after the header.
  final Uint8List rtpPacketWithOneByteExtensionAndPayload = Uint8List.fromList([
    // Header (20 bytes total)
    0x80, 0x60, 0x00, 0x01, // V P X CC | M PT | Seq
    0x00, 0x00, 0x03, 0xE8, // Timestamp
    0x00, 0x00, 0x30, 0x39, // SSRC
    0xBE, 0xDE, 0x00,
    0x01, // Extension Profile (0xBEDE), Length (1 word = 4 bytes)
    0x11, 0x22, 0x33,
    0x00, // Extension data (ID 1, L=1. Payload 0x22. Then 0x33, 0x00 padding)
    // Payload (5 bytes, example)
    0xDE, 0xAD, 0xBE, 0xEF, 0x01
  ]);

  print('--- Test Unmarshal Packet with One-Byte Extension and Payload ---');
  try {
    final Packet packet =
        Packet.unmarshal(rtpPacketWithOneByteExtensionAndPayload);
    print('Successfully unmarshalled RTP Packet:');
    print(packet);

    // Verify header details (inherited from previous tests)
    assert(packet.header.version == 2);
    assert(packet.header.extension == true);
    assert(packet.header.payloadType == 96);
    assert(packet.header.sequenceNumber == 1);
    assert(packet.header.ssrc == 12345);
    assert(packet.header.extensionProfile == ExtensionProfile.OneByte);
    assert(packet.header.extensions.length == 1);
    assert(packet.header.extensions[0].id == 1);
    assert(packet.header.extensions[0].payload[0] == 0x22);
    assert(packet.header.extensionsPadding ==
        2); // 0x33, 0x00 are padding in ext data

    // Verify payload
    assert(packet.payload.length == 5);
    assert(packet.payload[0] == 0xDE);
    assert(packet.payload[4] == 0x01);

    print(
        '\nAssertions passed for Packet unmarshal (one-byte extension, no padding flag)!');
  } on RtpError catch (e) {
    print('RTP Unmarshal Error: ${e.message}');
  } catch (e) {
    print('An unexpected error occurred: $e');
  }

  print('\n--- Test Unmarshal Packet with Padding Flag ---');
  // Example packet with padding flag set.
  // The last byte of the payload indicates padding length.
  // Total packet length: 12 (fixed header) + 5 (payload) = 17 bytes
  // Padding length is 3 (last byte of payload).
  // Actual payload will be 5 - 3 = 2 bytes.
  final Uint8List rtpPacketWithPadding = Uint8List.fromList([
    // Header (12 bytes) - V=2, P=1, X=0, CC=0, M=0, PT=97, Seq=2, TS=2000, SSRC=54321
    0xA0, 0x61, 0x00, 0x02, // V=2, P=1, X=0, CC=0 | M=0, PT=97 | Seq=2
    0x00, 0x00, 0x07, 0xD0, // Timestamp (2000)
    0x00, 0x00, 0xD4, 0x31, // SSRC (54321)
    // Payload (5 bytes) - 2 bytes actual data, 3 bytes padding (last byte indicates 3)
    0xAA, 0xBB, 0xCC, 0xDD,
    0x03 // Actual payload: 0xAA, 0xBB. Padding: 0xCC, 0xDD, 0x03
  ]);

  try {
    final Packet packetWithPadding = Packet.unmarshal(rtpPacketWithPadding);
    print('Successfully unmarshalled RTP Packet with Padding:');
    print(packetWithPadding);

    assert(packetWithPadding.header.padding == true);
    assert(packetWithPadding.payload.length ==
        2); // Expected actual payload length
    assert(packetWithPadding.payload[0] == 0xAA);
    assert(packetWithPadding.payload[1] == 0xBB);

    print('\nAssertions passed for Packet unmarshal (with padding flag)!');
  } on RtpError catch (e) {
    print('RTP Unmarshal Error: ${e.message}');
  } catch (e) {
    print('An unexpected error occurred: $e');
  }

  print('\n--- Test Unmarshal Packet with Short Padding ---');
  // Padding length (5) > payload length (4)
  final Uint8List rtpPacketShortPadding = Uint8List.fromList([
    0xA0, 0x61, 0x00, 0x02, // Header
    0x00, 0x00, 0x07, 0xD0,
    0x00, 0x00, 0xD4, 0x31,
    0xAA, 0xBB, 0xCC,
    0x05 // Payload: 0xAA, 0xBB, 0xCC. Padding length indicates 5, but only 4 bytes total
  ]);

  try {
    Packet.unmarshal(rtpPacketShortPadding);
    print('Error: Expected ShortPacket error, but unmarshal succeeded.');
  } on RtpError catch (e) {
    if (e == RtpError.shortPacket) {
      print('Caught expected error: ${e.message}');
    } else {
      print('Caught unexpected RTP error: ${e.message}');
    }
  } catch (e) {
    print('Caught unexpected general error: $e');
  }

  print(
      '\n--- Test Unmarshal Packet with 0-length Payload and Padding Flag ---');
  final Uint8List rtpPacketZeroLenPayloadPadding = Uint8List.fromList([
    0xA0, 0x61, 0x00, 0x02, // Header
    0x00, 0x00, 0x07, 0xD0,
    0x00, 0x00, 0xD4, 0x31,
    // No payload bytes follow, but padding flag is set. This is an error.
  ]);

  try {
    Packet.unmarshal(rtpPacketZeroLenPayloadPadding);
    print('Error: Expected ShortPacket error, but unmarshal succeeded.');
  } on RtpError catch (e) {
    if (e == RtpError.shortPacket) {
      print('Caught expected error: ${e.message}');
    } else {
      print('Caught unexpected RTP error: ${e.message}');
    }
  } catch (e) {
    print('Caught unexpected general error: $e');
  }
}
