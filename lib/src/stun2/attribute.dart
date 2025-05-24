import 'dart:convert';
import 'dart:typed_data';

import 'attribute_type.dart';
import 'message_manual.dart';

const attributeHeaderSize = 4;

class Attribute {
  dynamic attributeType;
  Uint8List value;
  // int offsetInMessage;

  Attribute({required this.attributeType, required this.value});

  int getRawDataLength() {
    return value.length;
  }

  @override
  String toString() {
    // TODO: implement toString
    if (attributeType is AttributeType &&
        attributeType == AttributeType.UserName) {
      return "Attribute{ attributeType: $attributeType, value: ${utf8.decode(value)}";
    }
    return "Attribute{ attributeType: $attributeType, value: $value}";
    // return "Attribute{ attributeType: $attributeType, value: $value}";
  }

  Uint8List encode() {
    int attrLen = 4 + value.length;
    attrLen += (4 - (attrLen % 4)) % 4;
    final attrData = Uint8List(attrLen);
    final bd = ByteData.sublistView(attrData);
    // result := make([]byte, attrLen)
    bd.setUint16(0, attributeType.value);
    bd.setUint16(2, value.length);
    attrData.setRange(4, 4 + value.length, value);
    return attrData;
  }
}

// func (a Attribute) String() string {
// 	return fmt.Sprintf("%s: [%s]", a.AttributeType, a.Value)
// }

Attribute decodeAttribute(Uint8List buf, int offset, int arrayLen)
// (*Attribute, error)
{
  if (arrayLen < attributeHeaderSize) {
    throw errIncompleteTURNFrame;
  }

  final bd = ByteData.sublistView(buf);

  final attrType = bd.getUint16(offset);

  offset += 2;

  final attrLength = bd.getUint16(offset);

  print("Attribute length: $attrLength");

  offset += 2;

  final value = buf.sublist(offset, offset + attrLength);
  dynamic attributeType;
  try {
    attributeType = AttributeType.fromInt(attrType);
  } catch (e) {
    attributeType = attrType;
  }

  return Attribute(
    attributeType: attributeType,
    value: value,
    // offsetInMessage: offsetBackup
  );
}
