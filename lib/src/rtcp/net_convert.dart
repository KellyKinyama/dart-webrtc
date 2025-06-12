import 'package:fixnum/fixnum.dart';

/// Utility class for network byte order conversions.
// class NetConvert {
//   /// Reverses the byte order of a 32-bit unsigned integer.
//   static int doReverseEndian(int value) {
//     return ((value & 0x000000FF) << 24) |
//         ((value & 0x0000FF00) << 8) |
//         ((value & 0x00FF0000) >> 8) |
//         ((value & 0xFF000000) >> 24);
//   }

//   /// Reverses the byte order of a 16-bit unsigned integer.
//   static int doReverseEndian16(int value) {
//     return ((value & 0x00FF) << 8) | ((value & 0xFF00) >> 8);
//   }
// }
/// Utility class for network byte order conversions.
class NetConvert {
  /// Reverses the byte order of a 32-bit unsigned integer.
  static int doReverseEndian(int value) {
    return ((value & 0x000000FF) << 24) |
        ((value & 0x0000FF00) << 8) |
        ((value & 0x00FF0000) >> 8) |
        ((value & 0xFF000000) >> 24);
  }

  /// Reverses the byte order of a 16-bit unsigned integer.
  static int doReverseEndian16(int value) {
    return ((value & 0x00FF) << 8) | ((value & 0xFF00) >> 8);
  }

  /// Converts a DateTime to an NTP timestamp (64-bit unsigned fixed-point number).
  // static Int64 dateTimeToNtpTimestamp(DateTime value) {
  //   final DateTime utcEpoch1900 = DateTime.utc(1900, 1, 1);
  //   final DateTime utcEpoch2036 = DateTime.utc(2036, 2, 7, 6, 28, 16);

  //   DateTime baseDate = value.isUtc
  //       ? (value.isAfter(utcEpoch2036) ? utcEpoch2036 : utcEpoch1900)
  //       : (value.toUtc().isAfter(utcEpoch2036) ? utcEpoch2036 : utcEpoch1900);

  //   final Duration elapsedTime = value.toUtc().difference(baseDate.toUtc());
  //   final double seconds = elapsedTime.inMicroseconds / 1000000.0;

  //   final Int64 ntpTimestamp =
  //       Int64.fromInts((seconds.toInt()), (seconds - seconds).toInt());

  //   return ntpTimestamp;
  // }

  /// Converts a DateTime to an NTP timestamp (64-bit unsigned fixed-point number).
  static Int64 dateTimeToNtpTimestamp(DateTime value) {
    final DateTime utcEpoch1900 = DateTime.utc(1900, 1, 1);
    final DateTime utcEpoch2036 = DateTime.utc(2036, 2, 7, 6, 28, 16);

    // Ensure the DateTime is UTC for accurate calculation against UTC epochs
    DateTime utcValue = value.toUtc();

    DateTime baseDate =
        utcValue.isAfter(utcEpoch2036) ? utcEpoch2036 : utcEpoch1900;

    final Duration elapsedTime = utcValue.difference(baseDate);
    final double seconds = elapsedTime.inMicroseconds / 1000000.0;

    final Int64 ntpTimestampSeconds = Int64(seconds.toInt());
    final Int64 ntpTimestampFraction =
        Int64(((seconds - seconds.toInt()) * 0xFFFFFFFF).toInt());

    // Combine seconds and fractional parts into a 64-bit Int64
    return (ntpTimestampSeconds << 32) | ntpTimestampFraction;
  }
}
