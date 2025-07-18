// lib/src/vpx_exception.dart
import 'package:ffi/ffi.dart';

/// Custom exception for VPX FFI operations.
class VpxException implements Exception {
  final String message;
  final int? errorCode;
  final String? errorDetail;

  VpxException(this.message, {this.errorCode, this.errorDetail});

  @override
  String toString() {
    String result = 'VpxException: $message';
    if (errorCode != null) {
      result += ' (Error Code: $errorCode)';
    }
    if (errorDetail != null && errorDetail!.isNotEmpty) {
      result += ' (Detail: $errorDetail)';
    }
    return result;
  }
}