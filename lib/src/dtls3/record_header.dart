import 'dart:typed_data';
import 'dtls.dart'; // Assuming common DTLS types are here

// Assuming DtlsVersion and ContentType enums are defined in dtls.dart
// enum ContentType { ... }
// enum DtlsVersion { ... }

const int sequenceNumberSize = 6; // 48 bit

/// Represents the header of a DTLS record.
/// Corresponds to Go's `RecordHeader` struct.
class RecordHeader {
  ContentType contentType;
  DtlsVersion version;
  int epoch;
  Uint8List sequenceNumber; // 48-bit value, represented as 6 bytes
  int length;

  RecordHeader({
    required this.contentType,
    required this.version,
    required this.epoch,
    required this.sequenceNumber,
    required this.length,
  }) : assert(sequenceNumber.length == sequenceNumberSize);

  /// Encodes the RecordHeader into a byte array.
  /// Corresponds to Go's `Encode` method.
  Uint8List encode() {
    final result = Uint8List(7 + sequenceNumberSize);
    final ByteData bd = ByteData.view(result.buffer);

    bd.setUint8(0, contentType.value);
    bd.setUint16(1, version.value, Endian.big);
    bd.setUint16(3, epoch, Endian.big);
    result.setRange(5, 5 + sequenceNumberSize, sequenceNumber);
    bd.setUint16(5 + sequenceNumberSize, length, Endian.big);

    return result;
  }

  /// Decodes a RecordHeader from a byte array.
  /// Corresponds to Go's `DecodeRecordHeader` function.
  static (RecordHeader, int, dynamic) decode(
      Uint8List buf, int offset, int arrayLen) {
    if (offset + 13 > arrayLen) {
      return (
        RecordHeader(
          contentType: ContentType.unsupported,
          version: DtlsVersion.unsupported,
          epoch: 0,
          sequenceNumber: Uint8List(sequenceNumberSize),
          length: 0,
        ),
        offset,
        'Incomplete DTLS record header'
      );
    }
    final reader = ByteData.sublistView(buf, offset);

    final contentType = ContentType.fromInt(reader.getUint8(0));
    final version = DtlsVersion.fromInt(reader.getUint16(1, Endian.big));
    final epoch = reader.getUint16(3, Endian.big);
    final sequenceNumber = Uint8List.fromList(
        buf.sublist(offset + 5, offset + 5 + sequenceNumberSize));
    final length = reader.getUint16(5 + sequenceNumberSize, Endian.big);

    return (
      RecordHeader(
        contentType: contentType,
        version: version,
        epoch: epoch,
        sequenceNumber: sequenceNumber,
        length: length,
      ),
      offset +
          13, // 1 (contentType) + 2 (version) + 2 (epoch) + 6 (sequenceNumber) + 2 (length) = 13
      null
    );
  }

  @override
  String toString() {
    final seqNum = ByteData.view(Uint8List(8).buffer)
      ..setUint8(2, sequenceNumber[0])
      ..setUint8(3, sequenceNumber[1])
      ..setUint8(4, sequenceNumber[2])
      ..setUint8(5, sequenceNumber[3])
      ..setUint8(6, sequenceNumber[4])
      ..setUint8(7, sequenceNumber[5]);
    final sequenceNumberValue = seqNum.getUint64(0, Endian.big);

    return 'RecordHeader(contentType: ${contentType.toString().split('.').last}, version: ${version.toString().split('.').last}, epoch: $epoch, sequenceNumber: $sequenceNumberValue, length: $length)';
  }
}
