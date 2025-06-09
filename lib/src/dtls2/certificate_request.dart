// certificate_request.dart (Converted from certificaterequest.go)

import 'dart:typed_data';
import 'dtls.dart'; // For common DTLS types like AlgoPair, CertificateType

class CertificateRequest {
  List<CertificateType> certificateTypes;
  List<AlgoPair> algoPairs;

  CertificateRequest({
    required this.certificateTypes,
    required this.algoPairs,
  });

  static (CertificateRequest, int, dynamic) unmarshal(
      Uint8List data, int offset, int arrayLen) {
    var reader = ByteData.sublistView(data);

    final certificateTypeCount = reader.getUint8(offset);
    offset++;
    List<CertificateType> certificateTypes = [];
    for (int i = 0; i < certificateTypeCount; i++) {
      certificateTypes.add(CertificateType.fromInt(reader.getUint8(offset + i)));
    }
    offset += certificateTypeCount;

    final algoPairLength = reader.getUint16(offset);
    offset += 2;
    final algoPairCount = algoPairLength ~/ 2;
    List<AlgoPair> algoPairs = [];
    for (int i = 0; i < algoPairCount; i++) {
      final decodedAlgoPair = AlgoPair.decode(data, offset);
      algoPairs.add(decodedAlgoPair.$1);
      offset = decodedAlgoPair.$2;
    }

    offset += 2; // Distinguished Names Length (skipped for now as per Go code)

    return (
      CertificateRequest(
        certificateTypes: certificateTypes,
        algoPairs: algoPairs,
      ),
      offset,
      null
    );
  }

  Uint8List marshal() {
    BytesBuilder result = BytesBuilder();
    result.addByte(certificateTypes.length);
    for (var type in certificateTypes) {
      result.addByte(type.value);
    }

    BytesBuilder encodedAlgoPairs = BytesBuilder();
    for (var algoPair in algoPairs) {
      encodedAlgoPairs.add(algoPair.encode());
    }
    final algoPairsBytes = encodedAlgoPairs.toBytes();
    result.add((ByteData(2)..setUint16(0, algoPairsBytes.length)).buffer.asUint8List());
    result.add(algoPairsBytes);

    result.add((ByteData(2)..setUint16(0, 0)).buffer.asUint8List()); // Distinguished Names Length (empty)

    return result.toBytes();
  }

  @override
  String toString() {
    final certTypesStr = certificateTypes.map((e) => e.toString()).join(', ');
    final algoPairsStr = algoPairs.map((e) => e.toString()).join(', ');
    return 'CertificateRequest(CertificateTypes: $certTypesStr, AlgoPairs: $algoPairsStr)';
  }
}