import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'attribute.dart';
import 'attribute_type.dart';

const magicCookie = 0x2112A442;

enum IPFamily {
  IPv4(0x01),
  IPV6(0x02);

  const IPFamily(this.value);
  final int value;

  factory IPFamily.fromInt(int key) {
    return values.firstWhere((element) => element.value == key);
  }
}

class MappedAddress {
  IPFamily ipFamily;
  InternetAddress ip;
  int port;

  MappedAddress({required this.ipFamily, required this.ip, required this.port});
}

Attribute createAttrXorMappedAddress(
    Uint8List transactionID, RawDatagramSocket addr) {
  // https://github.com/jitsi/ice4j/blob/311a495b21f38cc2dfcc4f7118dab96b8134aed6/src/main/java/org/ice4j/attribute/XorMappedAddressAttribute.java#L131
  final xorMask = Uint8List(16);
  ByteData bd = ByteData.sublistView(xorMask);
  // binary.BigEndian.PutUint32(xorMask[0:4], magicCookie)
  bd.setUint32(0, magicCookie);
  // copy(xorMask[4:], transactionID)

  xorMask.setRange(4, transactionID.length + 4, transactionID);
  //addressBytes := ms.Addr.IP
  final portModifier =
      ((xorMask[0] << 8) & 0x0000FF00) | (xorMask[1] & 0x000000FF);
  final addressBytes = addr.address.rawAddress;
  // copy(addressBytes, addr.IP.To4())
  final port = addr.port ^ portModifier;
  // print("address bytes length: ${addressBytes.length}");
  // print("xor mask length: ${xorMask.length}");
  // for (int i in addressBytes) {
  for (int i = 0; i < addressBytes.length; i++) {
    // print("index: $i");
    addressBytes[i] ^= xorMask[i];
  }

  final value = Uint8List(8);

  value[1] = IPFamily.IPv4.value;
  bd = ByteData.sublistView(value);
  // binary.BigEndian.PutUint16(value[2:4], port)
  bd.setUint16(2, port);
  // copy(value[4:8], addressBytes)
  value.setRange(4, 8, addressBytes);
  return Attribute(attributeType: AttributeType.XorMappedAddress, value: value
      // offsetInMessage: value.length,
      );
}

MappedAddress decodeAttrXorMappedAddress(
    Attribute attr, Uint8List transactionID, RawDatagramSocket addr) {
  final xorMask = Uint8List(16);
  ByteData bd = ByteData.sublistView(xorMask);
  // binary.BigEndian.PutUint32(xorMask[0:4], magicCookie)
  bd.setUint32(0, magicCookie);

  // xorIP := make([]byte, 16)
  Uint8List xorIP = Uint8List(16);
  for (int i = 0; i < attr.value.length - 4; i++) {
    xorIP[i] = attr.value[i + 4] ^ xorMask[i];
  }
  final family = IPFamily.fromInt(attr.value[1]);
  bd = ByteData.sublistView(attr.value);
  final port = bd.getUint16(0);
  // Truncate if IPv4, otherwise net.IP sometimes renders it as an IPv6 address.
  if (family == IPFamily.IPv4) {
    xorIP = xorIP.sublist(0, 4);
  }

  bd = ByteData.sublistView(xorMask);
  final x = bd.getUint16(0);
  return MappedAddress(
    ipFamily: family,
    ip: InternetAddress.fromRawAddress(xorIP),
    port: port ^ x,
  );
}

Attribute createAttrUserName(String userName) {
  final value = utf8.encode(userName);
  return Attribute(attributeType: AttributeType.UserName, value: value
      // offsetInMessage: value.length
      );
}
