// SPDX-FileCopyrightText: 2023 The Pion community <https://pion.ly>
// SPDX-License-Identifier: MIT

// Package opus provides an Opus Audio Codec RFC 6716 implementation.

import 'silk_common.dart';
import 'silk_decoder.dart';

// Custom exceptions for Opus decoder errors.
class OpusError implements Exception {
  final String message;
  const OpusError(this.message);

  @override
  String toString() => 'OpusError: $message';
}

const OpusError errTooShortForTableOfContentsHeader =
    OpusError('input too short for Table of Contents header');
const OpusError errUnsupportedFrameCode = OpusError('unsupported frame code');
const OpusError errUnsupportedConfigurationMode =
    OpusError('unsupported configuration mode');

/// Configuration struct based on Opus header.
/// Note: This is a simplified representation based on usage in `decoder_opus.go`
/// and does not fully implement all aspects of RFC 6716 Table 1.
class Configuration {
  final int _configByte;

  Configuration(this._configByte);

  /// Returns the mode (bits 3-4 of config byte).
  /// 0: CELT-only
  /// 1: Hybrid
  /// 2: Silk-only
  /// 3: Hybrid
  int mode() {
    // Mode is bits 3 and 4 (0-indexed)
    return (_configByte >> 3) & 0x03;
  }

  /// Returns the bandwidth (bits 0-2 of config byte).
  /// 0: Unused
  /// 1: Narrowband
  /// 2: Mediumband
  /// 3: Wideband
  /// 4: Superwideband
  /// 5: Fullband
  int bandwidth() {
    // Bandwidth is bits 0, 1, 2 (0-indexed)
    return _configByte & 0x07;
  }

  /// Returns the frame duration.
  /// 0: 2.5 ms
  /// 1: 5 ms
  /// 2: 10 ms
  /// 3: 20 ms
  /// 4: 40 ms
  /// 5: 60 ms
  /// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-3.1
  FrameDuration frameDuration() {
    // frame_duration_code from bits 5 and 6
    final frameDurationCode = (_configByte >> 5) & 0x03;
    switch (frameDurationCode) {
      case 0:
        return FrameDuration.ms2_5;
      case 1:
        return FrameDuration.ms5;
      case 2:
        return FrameDuration.ms10;
      case 3:
        return FrameDuration
            .ms20; // This is the only one used by Silk for 20ms frames
      default:
        return FrameDuration
            .ms20; // Fallback, though ideally this would be an error
    }
  }
}

/// Represents frame duration.
enum FrameDuration {
  ms2_5(2500000),
  ms5(5000000),
  ms10(10000000),
  ms20(20000000);

  final int nanoseconds;
  const FrameDuration(this.nanoseconds);
}

/// Table of Contents Header for Opus frames.
/// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-3.1
class TableOfContentsHeader {
  final int _headerByte;

  TableOfContentsHeader(this._headerByte);

  /// Returns the configuration (bits 3-7).
  Configuration configuration() {
    return Configuration(_headerByte >> 3);
  }

  /// Returns the frame code (bits 0-2).
  /// 0: 1 frame in packet
  /// 1: 2 frames in packet, equal size
  /// 2: 3 frames in packet, equal size
  /// 3: 4 frames in packet, equal size
  /// 4: 2 frames in packet, 1st small
  /// 5: 2 frames in packet, 2nd small
  int frameCode() {
    return _headerByte & 0x07;
  }

  /// Returns true if the stream is stereo.
  /// Not directly from the header byte in RFC 6716 for Opus,
  /// but often implied by channel count from Opus header.
  /// For this specific Go code, `tocHeader.isStereo()` was passed directly.
  bool isStereo() {
    // Placeholder: In a real Opus implementation, stereo information
    // would come from the Opus header's channel count, not the ToC header byte.
    // For now, mirroring the Go function's presence.
    return false; // Assuming mono for SILK-only as per go code limitations
  }
}

/// Mode constants from RFC 6716.
class ConfigurationMode {
  static const int celtOnly = 0;
  static const int hybrid = 1; // Also 3
  static const int silkOnly = 2;
}

/// Frame Code constants from RFC 6716.
class FrameCode {
  static const int oneFrame = 0;
  // Other frame codes omitted for simplicity as only oneFrame is handled by Go code.
}

/// Placeholder for bitdepth conversion functions.
/// In a full implementation, these would convert float32 PCM to S16LE.
class Bitdepth {
  /// Converts a List of float32 PCM samples to S16LE byte array.
  /// Factor [factor] determines how many times each sample is "resampled" into the output bytes.
  static void convertFloat32LittleEndianToSigned16LittleEndian(
      List<double> input, List<int> output, int factor) {
    int currIndex = 0;
    for (int i = 0; i < input.length; i++) {
      // Scale to S16 range and floor to effectively truncate, matching Go's int16 conversion behavior.
      // Use clamp to ensure the value stays within the int16 range, though dart ints are larger.
      // The bitwise operations below will handle the int16 two's complement representation.
      int res = (input[i] * 32767).floor();

      // Ensure 'res' is within signed 16-bit range for consistent bitwise behavior
      // -32768 to 32767
      if (res > 32767) {
        res = 32767;
      } else if (res < -32768) {
        res = -32768;
      }

      for (int j = 0; j < factor; j++) {
        // Write LSB (lower 8 bits)
        output[currIndex] = res & 0xFF;
        currIndex++;

        // Write MSB (upper 8 bits)
        // Dart's `>> 8` performs arithmetic right shift, preserving sign.
        output[currIndex] = (res >> 8) & 0xFF;
        currIndex++;
      }
    }
  }
}

/// Placeholder for resample functions.
/// In a full implementation, this would perform resampling.
class Resample {
  /// Upsamples or downsamples input to output.
  /// Factor of 3 is used in Go code.
  static void up(List<double> input, List<double> output, int factor) {
    // This is a simplified placeholder.
    // A real resampler would implement a proper algorithm (e.g., polyphase filter).
    // For now, a simple copy or scaling.
    for (int i = 0; i < input.length; i++) {
      if (i < output.length) {
        output[i] = input[i]; // Simple copy for now
      }
    }
  }

  // Up upsamples the requested amount.
  static void up(List<double> input, List<double> output, int upsampleCount) {
    int currIndex = 0;
    for (int i = 0; i < input.length; i++) {
      for (int j = 0; j < upsampleCount; j++) {
        output[currIndex] = output[i];
        currIndex++;
      }
    }
  }
}

/// [OpusDecoder] decodes the Opus bitstream into PCM.
class OpusDecoder {
  final SilkDecoder _silkDecoder = SilkDecoder();
  final List<double> _silkBuffer =
      List.filled(320, 0.0); // Buffer for SILK output

  /// Creates a new Opus Decoder.
  OpusDecoder();

  /// Internal decode logic used by both [decode] and [decodeFloat32].
  (Bandwidth bandwidth, bool isStereo, OpusError? err) _decodeInternal(
      List<int> input, List<double> output) {
    if (input.isEmpty) {
      return (Bandwidth.narrowband, false, errTooShortForTableOfContentsHeader);
    }

    final tocHeader = TableOfContentsHeader(input[0]);
    final cfg = tocHeader.configuration();

    List<List<int>> encodedFrames = [];
    switch (tocHeader.frameCode()) {
      case FrameCode.oneFrame:
        encodedFrames.add(input.sublist(1));
        break;
      default:
        return (Bandwidth.narrowband, false, errUnsupportedFrameCode);
    }

    if (cfg.mode() != ConfigurationMode.silkOnly) {
      return (Bandwidth.narrowband, false, errUnsupportedConfigurationMode);
    }

    for (final encodedFrame in encodedFrames) {
      final silkErr = _silkDecoder.decode(
        encodedFrame,
        output,
        tocHeader.isStereo(),
        cfg.frameDuration().nanoseconds,
        Bandwidth.values.firstWhere((b) => b.value == cfg.bandwidth()),
      );
      if (silkErr != null) {
        return (Bandwidth.narrowband, false, OpusError(silkErr.message));
      }
    }

    return (
      Bandwidth.values.firstWhere((b) => b.value == cfg.bandwidth()),
      tocHeader.isStereo(),
      null
    );
  }

  /// Decodes the Opus bitstream into S16LE PCM.
  (Bandwidth bandwidth, bool isStereo, OpusError? err) decode(
      List<int> input, List<int> output) {
    final (bandwidth, isStereo, err) = _decodeInternal(input, _silkBuffer);
    if (err != null) {
      return (bandwidth, isStereo, err);
    }

    // Convert float32 SILK output to S16LE PCM
    Bitdepth.convertFloat32LittleEndianToSigned16LittleEndian(
        _silkBuffer, output, 3);

    return (bandwidth, isStereo, null);
  }

  /// Decodes the Opus bitstream into F32LE PCM.
  (Bandwidth bandwidth, bool isStereo, OpusError? err) decodeFloat32(
      List<int> input, List<double> output) {
    final (bandwidth, isStereo, err) = _decodeInternal(input, _silkBuffer);
    if (err != null) {
      return (bandwidth, isStereo, err);
    }

    // Resample the SILK output to F32LE PCM
    Resample.up(_silkBuffer, output, 3);

    return (bandwidth, isStereo, null);
  }
}
