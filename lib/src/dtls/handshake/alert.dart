import 'dart:typed_data';

import 'handshake.dart';

enum AlertLevel {
  warning(1),
  fatal(2),
  invalid(0);

  final int value;
  const AlertLevel(this.value);

  @override
  String toString() {
    switch (this) {
      case AlertLevel.warning:
        return 'LevelWarning';
      case AlertLevel.fatal:
        return 'LevelFatal';
      default:
        return 'Invalid alert level';
    }
  }

  static AlertLevel from(int val) {
    switch (val) {
      case 1:
        return AlertLevel.warning;
      case 2:
        return AlertLevel.fatal;
      default:
        return AlertLevel.invalid;
    }
  }
}

enum AlertDescription {
  closeNotify(0),
  unexpectedMessage(10),
  badRecordMac(20),
  decryptionFailed(21),
  recordOverflow(22),
  decompressionFailure(30),
  handshakeFailure(40),
  noCertificate(41),
  badCertificate(42),
  unsupportedCertificate(43),
  certificateRevoked(44),
  certificateExpired(45),
  certificateUnknown(46),
  illegalParameter(47),
  unknownCa(48),
  accessDenied(49),
  decodeError(50),
  decryptError(51),
  exportRestriction(60),
  protocolVersion(70),
  insufficientSecurity(71),
  internalError(80),
  userCanceled(90),
  noRenegotiation(100),
  unsupportedExtension(110),
  unknownPskIdentity(115),
  invalid(0);

  final int value;
  const AlertDescription(this.value);

  @override
  String toString() {
    switch (this) {
      case AlertDescription.closeNotify:
        return 'CloseNotify';
      case AlertDescription.unexpectedMessage:
        return 'UnexpectedMessage';
      case AlertDescription.badRecordMac:
        return 'BadRecordMac';
      case AlertDescription.decryptionFailed:
        return 'DecryptionFailed';
      case AlertDescription.recordOverflow:
        return 'RecordOverflow';
      case AlertDescription.decompressionFailure:
        return 'DecompressionFailure';
      case AlertDescription.handshakeFailure:
        return 'HandshakeFailure';
      case AlertDescription.noCertificate:
        return 'NoCertificate';
      case AlertDescription.badCertificate:
        return 'BadCertificate';
      case AlertDescription.unsupportedCertificate:
        return 'UnsupportedCertificate';
      case AlertDescription.certificateRevoked:
        return 'CertificateRevoked';
      case AlertDescription.certificateExpired:
        return 'CertificateExpired';
      case AlertDescription.certificateUnknown:
        return 'CertificateUnknown';
      case AlertDescription.illegalParameter:
        return 'IllegalParameter';
      case AlertDescription.unknownCa:
        return 'UnknownCA';
      case AlertDescription.accessDenied:
        return 'AccessDenied';
      case AlertDescription.decodeError:
        return 'DecodeError';
      case AlertDescription.decryptError:
        return 'DecryptError';
      case AlertDescription.exportRestriction:
        return 'ExportRestriction';
      case AlertDescription.protocolVersion:
        return 'ProtocolVersion';
      case AlertDescription.insufficientSecurity:
        return 'InsufficientSecurity';
      case AlertDescription.internalError:
        return 'InternalError';
      case AlertDescription.userCanceled:
        return 'UserCanceled';
      case AlertDescription.noRenegotiation:
        return 'NoRenegotiation';
      case AlertDescription.unsupportedExtension:
        return 'UnsupportedExtension';
      case AlertDescription.unknownPskIdentity:
        return 'UnknownPskIdentity';
      default:
        return 'Invalid alert description';
    }
  }

  static AlertDescription from(int val) {
    switch (val) {
      case 0:
        return AlertDescription.closeNotify;
      case 10:
        return AlertDescription.unexpectedMessage;
      case 20:
        return AlertDescription.badRecordMac;
      case 21:
        return AlertDescription.decryptionFailed;
      case 22:
        return AlertDescription.recordOverflow;
      case 30:
        return AlertDescription.decompressionFailure;
      case 40:
        return AlertDescription.handshakeFailure;
      case 41:
        return AlertDescription.noCertificate;
      case 42:
        return AlertDescription.badCertificate;
      case 43:
        return AlertDescription.unsupportedCertificate;
      case 44:
        return AlertDescription.certificateRevoked;
      case 45:
        return AlertDescription.certificateExpired;
      case 46:
        return AlertDescription.certificateUnknown;
      case 47:
        return AlertDescription.illegalParameter;
      case 48:
        return AlertDescription.unknownCa;
      case 49:
        return AlertDescription.accessDenied;
      case 50:
        return AlertDescription.decodeError;
      case 51:
        return AlertDescription.decryptError;
      case 60:
        return AlertDescription.exportRestriction;
      case 70:
        return AlertDescription.protocolVersion;
      case 71:
        return AlertDescription.insufficientSecurity;
      case 80:
        return AlertDescription.internalError;
      case 90:
        return AlertDescription.userCanceled;
      case 100:
        return AlertDescription.noRenegotiation;
      case 110:
        return AlertDescription.unsupportedExtension;
      case 115:
        return AlertDescription.unknownPskIdentity;
      default:
        return AlertDescription.invalid;
    }
  }
}

class Alert {
  final AlertLevel alertLevel;
  final AlertDescription alertDescription;

  Alert(this.alertLevel, this.alertDescription);

  ContentType get contentType => ContentType.content_alert;

  int get size => 2;

  Uint8List marshal() {
    final bb = BytesBuilder();
    bb.add(Uint8List.fromList([alertLevel.value, alertDescription.value]));

    return bb.toBytes();
  }

  static (Alert, int, bool?) unmarshal(
      Uint8List buf, int offset, int arrayLen) {

        final alertLevel=AlertLevel.from(buf[offset]);
        offset++;
        final alertDescription=AlertDescription.from(buf[offset]);
    return (
      Alert(alertLevel, alertDescription),
      offset,
      null
    );
  }

  @override
  String toString() {
    return 'Alert $alertLevel: $alertDescription';
  }

  static (Alert, int, bool?) decode(Uint8List buf, int offset, int arrayLen) {
    return (
      Alert(AlertLevel.from(buf[offset]), AlertDescription.from(buf[offset++])),
      buf[offset],
      null
    );
  }
}

class ByteReader {
  // Define how you read bytes from the input, e.g., reading from a stream or file
  Future<int> readByte() async {
    // Implement reading logic
    return 0;
  }
}

class ByteSink {
  // Define how you write bytes to the output, e.g., to a file or stream
  Future<void> add(Uint8List data) async {
    // Implement writing logic
  }

  Future<void> flush() async {
    // Implement flush logic
  }
}
