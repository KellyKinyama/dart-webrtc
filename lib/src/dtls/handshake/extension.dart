// import 'dart:typed_data';
// import 'dart:convert';

// import 'package:dart_tls/ch09/tls.dart';

// import '../crypto.dart';

// // Placeholder classes and enums for the extension types (for example purposes)

// enum ExtensionType {
//   ExtensionTypeServerName(0),
//   ExtensionTypeSupportedEllipticCurves(10),
//   ExtensionTypeSupportedPointFormats(11),
//   ExtensionTypeSupportedSignatureAlgorithms(13),
//   ExtensionTypeUseSRTP(14),
//   ExtensionTypeALPN(16),
//   ExtensionTypeUseExtendedMasterSecret(23),
//   ExtensionTypeRenegotiationInfo(65),

//   ExtensionTypeUnknown(65535); //Not a valid value

//   const ExtensionType(this.value);
//   final int value;

//   static ExtensionType fromInt(int value) {
//     switch (value) {
//       case 0:
//         return ExtensionTypeServerName;
//       case 10:
//         return ExtensionTypeSupportedEllipticCurves;
//       case 11:
//         return ExtensionTypeSupportedPointFormats;
//       case 13:
//         return ExtensionTypeSupportedSignatureAlgorithms;
//       case 14:
//         return ExtensionTypeUseSRTP;
//       case 16:
//         return ExtensionTypeALPN;
//       case 23:
//         return ExtensionTypeUseExtendedMasterSecret;
//       case 65:
//         return ExtensionTypeRenegotiationInfo;
//       default:
//         return ExtensionTypeUnknown;
//     }
//   }
// }

// abstract class Extension {
//   late int type;
//   late Uint8List data;
//   static Extension decode(
//       int extensionLength, Uint8List buf, int offset, int arrayLen) {
//     throw UnimplementedError();
//   }

//   Uint8List encode() {
//     throw UnimplementedError();
//   }

//   ExtensionType getExtensionType();
// }

// class ExtSupportedSignatureAlgorithms extends Extension {
//   List<SignatureHashAlgorithm> signature_hash_algorithms;

//   ExtSupportedSignatureAlgorithms(this.signature_hash_algorithms);

//   @override
//   Uint8List encode() {
//     Uint8List result = Uint8List(2 + 2 * signature_hash_algorithms.length);
//     int offset = 0;
//     ByteData writer = ByteData.sublistView(result);
//     writer.setUint16(offset, 2 * signature_hash_algorithms.length);
//     offset = offset + 2;
//     writer.setUint16(offset, 2 * signature_hash_algorithms.length);
//     offset = offset + 2;
//     for (var v in signature_hash_algorithms) {
//       writer.setUint8(offset, v.hash.value);
//       offset++;
//       writer.setUint8(offset, v.signatureAgorithm.value);
//       offset++;
//     }

//     return result;
//   }

//   static ExtSupportedSignatureAlgorithms unmarshal(
//       int extensionLegnth, Uint8List buf, int offset, int arrayLen) {
//     ByteData reader = ByteData.sublistView(buf);
//     // let _ = reader.read_u16::<BigEndian>()?;
//     // offset = offset + 2;

//     final algorithm_count = (reader.getUint16(offset) / 2).toInt();
//     List<SignatureHashAlgorithm> signature_hash_algorithms = [];
//     // let mut signature_hash_algorithms = vec![];
//     for (int i = 0; i < algorithm_count; i++) {
//       final hash = reader.getUint8(offset);
//       final signature = reader.getUint8(offset);
//       signature_hash_algorithms.add(SignatureHashAlgorithm(
//           hash: HashAlgorithm.fromInt(hash),
//           signatureAgorithm: SignatureAlgorithm.fromInt(signature)));
//     }
//     return ExtSupportedSignatureAlgorithms(signature_hash_algorithms);
//   }

//   @override
//   ExtensionType getExtensionType() {
//     // TODO: implement getExtensionType
//     throw UnimplementedError();
//   }
// }

// class ExtUseExtendedMasterSecret extends Extension {
//   ExtUseExtendedMasterSecret();
//   @override
//   String toString() {
//     return "[UseExtendedMasterSecret]";
//   }

//   @override
//   ExtensionType getExtensionType() {
//     return ExtensionType.ExtensionTypeUseExtendedMasterSecret;
//   }

//   int size() {
//     return 2;
//   }

//   @override
//   Uint8List encode() {
//     return Uint8List(0);
//   }

//   static ExtUseExtendedMasterSecret decode(
//       int extensionLength, Uint8List buf, int offset, int arrayLen) {
//     // No implementation needed for this example
//     return ExtUseExtendedMasterSecret();
//   }
// }

// class ExtRenegotiationInfo extends Extension {
//   @override
//   String toString() {
//     return "[RenegotiationInfo]";
//   }

//   ExtensionType getExtensionType() {
//     return ExtensionType.ExtensionTypeRenegotiationInfo;
//   }

//   Uint8List encode() {
//     return Uint8List(0);
//   }

//   static ExtRenegotiationInfo decode(
//       int extensionLength, Uint8List buf, int offset, int arrayLen) {
//     // No implementation needed for this example
//     return ExtRenegotiationInfo();
//   }
// }

// class ExtUseSRTP extends Extension {
//   List<int> protectionProfiles;
//   Uint8List mki;

//   ExtUseSRTP(this.protectionProfiles, this.mki);

//   @override
//   String toString() {
//     return "[UseSRTP] Protection Profiles: $protectionProfiles\nMKI: $mki";
//   }

//   ExtensionType getExtensionType() {
//     return ExtensionType.ExtensionTypeUseSRTP;
//   }

//   // List<int> encode() {
//   //   List<int> result = [];
//   //   result.add((protectionProfiles.length * 2) >> 8); // Length in MSB
//   //   result.add((protectionProfiles.length * 2) & 0xFF); // Length in LSB
//   //   protectionProfiles.forEach((profile) {
//   //     result.add((profile >> 8) & 0xFF); // Profile MSB
//   //     result.add(profile & 0xFF); // Profile LSB
//   //   });
//   //   result.add(mki.length);
//   //   result.addAll(mki);
//   //   return result;
//   // }

//   Uint8List encode() {
//     Uint8List result =
//         Uint8List(2 + (protectionProfiles.length * 2) + 1 + mki.length);
//     // result := make([]byte, 2+(len(e.ProtectionProfiles)*2)+1+len(e.Mki))
//     int offset = 0;

//     ByteData writer = ByteData.sublistView(result);
//     writer.setUint16(offset, protectionProfiles.length * 2);
//     offset += 2;
//     for (int i = 0; i < protectionProfiles.length; i++) {
//       writer.setUint16(offset, protectionProfiles[i]);
//       offset += 2;
//     }
//     result[offset] = mki.length;
//     offset++;
//     result.setRange(offset, offset + mki.length, mki);
//     return result;
//   }

//   // @override
//   // void decode(int extensionLength, Uint8List buf, int offset, int arrayLen) {
//   //   int protectionProfilesLength = (buf[offset] << 8) | buf[offset + 1];
//   //   int protectionProfilesCount = protectionProfilesLength ~/ 2;
//   //   offset += 2;
//   //   protectionProfiles = List.generate(protectionProfilesCount, (i) {
//   //     int profile = (buf[offset] << 8) | buf[offset + 1];
//   //     offset += 2;
//   //     return profile;
//   //   });

//   //   int mkiLength = buf[offset];
//   //   offset++;
//   //   mki = buf.sublist(offset, offset + mkiLength);
//   //   offset += mkiLength;
//   // }

//   static ExtUseSRTP decode(
//       int extensionLength, Uint8List buf, int offset, int arrayLen)
//   //  error
//   {
//     ByteData reader = ByteData.sublistView(buf);
//     final protectionProfilesLength = reader.getUint16(offset);
//     offset += 2;
//     final protectionProfilesCount = protectionProfilesLength / 2;
//     List<int> protectionProfiles =
//         List.filled(protectionProfilesCount.toInt(), 0);
//     // e.ProtectionProfiles = make([]SRTPProtectionProfile, protectionProfilesCount)
//     for (int i = 0; i < protectionProfilesCount; i++) {
//       protectionProfiles[i] = reader.getUint16(offset);
//       offset += 2;
//     }
//     final mkiLength = buf[offset];
//     offset++;

//     final mki = buf.sublist(offset, offset + mkiLength);
//     offset += mkiLength;

//     return ExtUseSRTP(protectionProfiles, mki);
//   }
// }

// class ExtSupportedPointFormats extends Extension {
//   List<int> pointFormats = [];

//   ExtSupportedPointFormats(this.pointFormats);

//   int size() {
//     return 2 + 1 + pointFormats.length;
//   }

//   @override
//   String toString() {
//     return "[SupportedPointFormats] Point Formats: $pointFormats";
//   }

//   @override
//   ExtensionType getExtensionType() {
//     return ExtensionType.ExtensionTypeSupportedPointFormats;
//   }

//   Uint8List encode() {
//     List<int> result = [];
//     result.add(pointFormats.length);
//     result.addAll(pointFormats);
//     return Uint8List.fromList(result);
//   }

//   static ExtSupportedPointFormats decode(
//       int extensionLength, Uint8List buf, int offset, int arrayLen) {
//     final pointFormatsCount = buf[offset];
//     offset++;
//     final pointFormats = List.filled(pointFormatsCount, 0);
//     for (int i = 0; i < pointFormatsCount; i++) {
//       pointFormats[i] = buf[offset];
//       offset++;
//     }

//     return ExtSupportedPointFormats(pointFormats);
//   }

//   // @override
//   // void decode(int extensionLength, Uint8List buf, int offset, int arrayLen) {
//   //   int pointFormatsCount = buf[offset];
//   //   offset++;
//   //   pointFormats = List.generate(pointFormatsCount, (i) {
//   //     int format = buf[offset];
//   //     offset++;
//   //     return format;
//   //   });
//   // }
// }

// class ExtSupportedEllipticCurves extends Extension {
//   List<int> curves = [];
//   ExtSupportedEllipticCurves(this.curves);

//   @override
//   String toString() {
//     return "[SupportedEllipticCurves] Curves: $curves";
//   }

//   @override
//   ExtensionType getExtensionType() {
//     return ExtensionType.ExtensionTypeSupportedEllipticCurves;
//   }

//   int size() {
//     return 2 + 2 + curves.length * 2;
//   }

//   // List<int> encode() {
//   //   List<int> result = [];
//   //   result.add((curves.length * 2) >> 8); // Length in MSB
//   //   result.add((curves.length * 2) & 0xFF); // Length in LSB
//   //   curves.forEach((curve) {
//   //     result.add((curve >> 8) & 0xFF); // Curve MSB
//   //     result.add(curve & 0xFF); // Curve LSB
//   //   });
//   //   return result;
//   // }

//   // @override
//   // void decode(int extensionLength, Uint8List buf, int offset, int arrayLen) {
//   //   int curvesLength = (buf[offset] << 8) | buf[offset + 1];
//   //   int curvesCount = curvesLength ~/ 2;
//   //   offset += 2;
//   //   curves = List.generate(curvesCount, (i) {
//   //     int curve = (buf[offset] << 8) | buf[offset + 1];
//   //     offset += 2;
//   //     return curve;
//   //   });

//   //   // print("Curves: $curves");
//   // }

//   Uint8List encode() {
//     Uint8List result = Uint8List((1 + curves.length) * 2);
//     int offset = 0;

//     ByteData writer = ByteData.sublistView(result);
//     writer.setUint16(offset, curves.length);
//     offset += 2;
//     for (int i = 0; i < curves.length; i++) {
//       print("result lenght: ${result.length}, attempted length: ${offset + 2}");
//       writer.setUint16(offset, curves[i]);
//       offset += 2;
//     }
//     return result;
//   }

//   static ExtSupportedEllipticCurves decode(
//       int extensionLength, Uint8List buf, int offset, int arrayLen) {
//     ByteData reader = ByteData.sublistView(buf);
//     final curvesLength = reader.getUint16(offset);
//     offset += 2;
//     final curvesCount = (curvesLength / 2).toInt();
//     final curves = List.filled(curvesCount, 0);
//     for (int i = 0; i < curvesCount; i++) {
//       curves[i] = reader.getUint16(offset);
//       offset += 2;
//     }

//     return ExtSupportedEllipticCurves(curves);
//   }
// }

// class ExtUnknown extends Extension {
//   final int type;
//   final int dataLength;
//   Uint8List data;

//   ExtUnknown(
//       {required this.type, required this.dataLength, required this.data});

//   int size() {
//     return 2 + 1 + dataLength;
//   }

//   @override
//   String toString() {
//     return "[Unknown Extension Type] Ext Type: <u>$type</u>, Data: <u>$dataLength bytes</u>";
//   }

//   ExtensionType getExtensionType() {
//     return ExtensionType.ExtensionTypeUnknown;
//   }

//   Uint8List encode() {
//     // throw UnsupportedError("ExtUnknown cannot be encoded, it's readonly");
//     return data;
//   }

//   static ExtUnknown decode(
//       int extensionLength, Uint8List buf, int offset, int arrayLen) {
//     throw UnsupportedError("ExtUnknown cannot be encoded, it's readonly");

//     // return ExtUnknown(type: type, dataLength: extensionLength, data: data);
//   }
// }

// // Decoding method
// // Map<ExtensionType, Extension> decodeExtensionMap(
// //     Uint8List buf, int offset, int arrayLen) {
// //   Map<ExtensionType, Extension> result = {};
// //   int length =
// //       ByteData.sublistView(buf, offset, offset + 2).getUint16(0, Endian.big);
// //   offset += 2;

// //   int offsetBackup = offset;
// //   while (offset < offsetBackup + length) {
// //     ExtensionType extensionType = ExtensionType.fromInt(
// //         ByteData.sublistView(buf, offset, offset + 2).getUint16(0, Endian.big));
// //     offset += 2;

// //     int extensionLength =
// //         ByteData.sublistView(buf, offset, offset + 2).getUint16(0, Endian.big);
// //     offset += 2;

// //     Extension? extension;
// //     switch (extensionType) {
// //       case ExtensionType.ExtensionTypeUseExtendedMasterSecret:
// //         extension = ExtUseExtendedMasterSecret();
// //         break;
// //       case ExtensionType.ExtensionTypeRenegotiationInfo:
// //         extension = ExtRenegotiationInfo();
// //         break;
// //       case ExtensionType.ExtensionTypeUseSRTP:
// //         extension = ExtUseSRTP();
// //         break;
// //       case ExtensionType.ExtensionTypeSupportedPointFormats:
// //         extension = ExtSupportedPointFormats();
// //         break;
// //       case ExtensionType.ExtensionTypeSupportedEllipticCurves:
// //         extension = ExtSupportedEllipticCurves();
// //         break;
// //       default:
// //         extension =
// //             ExtUnknown(type: extensionType, dataLength: extensionLength);
// //     }

// //     extension.decode(extensionLength, buf, offset, arrayLen);
// //     result[extension.getExtensionType()] = extension;

// //     offset += extensionLength;
// //   }
// //   return result;
// // }

// List<Extension> decodeExtensionMap(Uint8List buf, int offset, int arrayLen) {
  
//   ByteData reader = ByteData.sublistView(buf);
//   List<Extension> result = [];
//   final length = reader.getUint16(offset);
//   offset += 2;
//   final offsetBackup = offset;
//   while (offset < offsetBackup + length) {
//     final intExtensionType = reader.getUint16(offset);
//     final extensionType = ExtensionType.fromInt(intExtensionType);
//     offset += 2;
//     final extensionLength = reader.getUint16(offset);
//     offset += 2;
//     // var extension Extension = nil
//     switch (extensionType) {
//       // case ExtensionType.ExtensionTypeUseExtendedMasterSecret:
//       //   result[extensionType] = ExtUseExtendedMasterSecret.decode(
//       //       extensionLength, buf, offset, buf.length);
//       // case ExtensionType.ExtensionTypeUseSRTP:
//       //   result[extensionType] =
//       //       ExtUseSRTP.decode(extensionLength, buf, offset, buf.length);
//       // case ExtensionType.ExtensionTypeSupportedPointFormats:
//       //   result[extensionType] = ExtSupportedPointFormats.decode(
//       //       extensionLength, buf, offset, buf.length);
//       // case ExtensionType.ExtensionTypeSupportedEllipticCurves:
//       //   result[extensionType] = ExtSupportedEllipticCurves.decode(
//       //       extensionLength, buf, offset, buf.length);

//       // case ExtensionType.ExtensionTypeSupportedSignatureAlgorithms:
//       //   result[extensionType] = ExtSupportedSignatureAlgorithms.unmarshal(
//       //       extensionLength, buf, offset, arrayLen);

//       default:
//         result.add(ExtUnknown(
//             type: intExtensionType,
//             dataLength: extensionLength,
//             data: buf.sublist(offset, offset + extensionLength)));
//     }
//     // if extension != nil {
//     // 	err := extension.Decode(int(extensionLength), buf, offset, arrayLen)

//     // 	if err != nil {
//     // 		return nil, offset, err
//     // 	}
//     // 	AddExtension(result, extension)
//     // }
//     offset += extensionLength;
//   }
//   return result;
// }

// Uint8List encodeExtensionMap(List<Extension> extensionMap) {
//   Uint8List result = Uint8List(2);
//   Uint8List encodedBody = Uint8List(0);
//   // print("Extensions: ${extensionMap}");
//   extensionMap.where((extension) {
//     Uint8List encodedExtension;

//     final encodedExtType = Uint8List(2);
//     // if (extension is ExtUnknown) return false;
//     print("Extension: ${extension}");

//     // if (extension is ExtUnknown) {
//     encodedExtension = extension.data;
//     ByteData writer = ByteData.sublistView(encodedExtType);
//     writer.setUint16(0, extension.type);
//     // }
//     // else {
//     //   encodedExtension = extension.encode();
//     //   ByteData writer = ByteData.sublistView(encodedExtType);
//     //   writer.setUint16(0, extension);
//     // }
//     encodedBody = Uint8List.fromList([...encodedBody, ...encodedExtType]);

//     final encodedExtLen = Uint8List(2);
//     ByteData.sublistView(encodedExtLen).setUint16(0, encodedExtension.length);

//     encodedBody = Uint8List.fromList(
//         [...encodedBody, ...encodedExtLen, ...encodedExtension]);

//     return true;
//   }).toList();
//   print("encoded body length: ${encodedBody.length}");
//   ByteData.sublistView(encodedBody).setUint16(0, encodedBody.length);

//   result = Uint8List.fromList([...encodedBody, ...encodedBody]);

//   // for (var ext in extensions) {
//   // 	final encodedExtension = ext.encode();
//   // 	final encodedExtType = Uint8List(2);
//   //    ByteData writer = ByteData.sublistView(encodedExtType);
//   // 	binary.BigEndian.PutUint16(encodedExtType, uint16(extension.ExtensionType()))
//   // 	encodedBody = append(encodedBody, encodedExtType...)

//   // 	encodedExtLen := make([]byte, 2)
//   // 	binary.BigEndian.PutUint16(encodedExtLen, uint16(len(encodedExtension)))
//   // 	encodedBody = append(encodedBody, encodedExtLen...)
//   // 	encodedBody = append(encodedBody, encodedExtension...)
//   // }
//   // binary.BigEndian.PutUint16(result[0:], uint16(len(encodedBody)))
//   // result = append(result, encodedBody...)
//   return result;
// }
