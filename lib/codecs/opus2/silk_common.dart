// SPDX-FileCopyrightText: 2023 The Pion community <https://pion.ly>
// SPDX-License-Identifier: MIT

// Package silk provides common types, constants, and utility functions for Silk codec.

import 'dart:math' as math;

/// Represents the bandwidth for Silk.
/// NB (narrowband), MB (medium-band), or WB (wideband).
enum Bandwidth {
  narrowband(1),
  mediumband(2),
  wideband(3);

  final int value;
  const Bandwidth(this.value);
}

/// Represents the frame signal type.
enum FrameSignalType {
  inactive(1),
  unvoiced(2),
  voiced(3);

  final int value;
  const FrameSignalType(this.value);
}

/// Represents the frame quantization offset type.
enum FrameQuantizationOffsetType {
  low(1),
  high(2);

  final int value;
  const FrameQuantizationOffsetType(this.value);
}

/// Constants used in the Silk codec.
class SilkConstants {
  static const int subframeCount = 4;
  static const int pulsecountLargestPartitionSize = 16;
  static const int nanoseconds10Ms = 10000000;
  static const int nanoseconds20Ms = 20000000;
}

/// Returns the maximum of two 32-bit integers.
int maxInt32(int a, int b) {
  return a > b ? a : b;
}

/// Returns the maximum of two 16-bit integers.
int maxInt16(int a, int b) {
  return a > b ? a : b;
}

/// Returns the minimum of two unsigned integers.
int minUint(int a, int b) {
  return a > b ? b : a;
}

/// Returns the minimum of two 16-bit integers.
int minInt16(int a, int b) {
  return a > b ? b : a;
}

/// Clamps an integer [input] value between a [low] and [high] bound.
int clamp(int low, int input, int high) {
  if (input > high) {
    return high;
  } else if (input < low) {
    return low;
  }
  return input;
}

/// Clamps a float32 [value] between -1.0 and 1.0.
double clampNegativeOneToOne(double value) {
  if (value <= -1.0) {
    return -1.0;
  } else if (value >= 1.0) {
    return 1.0;
  }
  return value;
}

/// Returns the sign of [x].
/// -1 if x < 0, 0 if x == 0, 1 if x > 0.
int sign(int x) {
  if (x < 0) {
    return -1;
  } else if (x == 0) {
    return 0;
  } else {
    return 1;
  }
}

/// Returns the minimum number of bits required to store a positive integer [n].
/// 0 for a non-positive integer [n].
///
/// Ref: https://datatracker.ietf.org/doc/html/rfc6716#section-1.1.4
int ilog(int n) {
  if (n <= 0) {
    return 0;
  }
  // math.Log2 returns double, floor it and add 1.
  return (math.log(n) / math.ln2).floor() + 1;
}

// Custom exceptions for Silk decoder errors.
class SilkError implements Exception {
  final String message;
  const SilkError(this.message);

  @override
  String toString() => 'SilkError: $message';
}

const SilkError errUnsupportedSilkFrameDuration =
    SilkError('unsupported SILK frame duration');
const SilkError errUnsupportedSilkStereo =
    SilkError('unsupported SILK stereo mode');
const SilkError errOutBufferTooSmall =
    SilkError('output buffer too small for SILK frame');
const SilkError errUnsupportedSilkLowBitrateRedundancy =
    SilkError('unsupported SILK low bitrate redundancy');
const SilkError errNonAbsoluteLagsUnsupported =
    SilkError('non-absolute pitch lags are not supported');