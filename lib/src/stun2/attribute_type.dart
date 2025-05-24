enum AttributeType {
  Reserved(0x0000),
  MappedAddress(0x0001),
  ResponseAddress(0x0002),
  ChangeRequest(0x0003),
  SourceAddress(0x0004),
  ChangedAddress(0x0005),
  UserName(0x0006),
  Password(0x0007),
  MessageIntegrity(0x0008),
  ErrorCode(0x0009),
  UnknownAttributes(0x000a),
  ReflectedFrom(0x000b),
  Realm(0x0014),
  Nonce(0x0015),
  XorMappedAddress(0x0020),
  Software(0x8022),
  AlternameServer(0x8023),
  Priority(0x0024),
  UseCandidate(0x0025),
  Fingerprint(0x8028),
  PRIORITY(0x8029),
// TURN attributes:
  ChannelNumber(0x000C),
  Lifetime(0x000D),
  XorPeerAdddress(0x0012),
  Data(0x0013),
  XorRelayedAddress(0x0016),
  EvenPort(0x0018),
  RequestedPort(0x0019),
  DontFragment(0x001A),
  ReservationRequest(0x0022),
  ICE_CONTROLLED(0xc057),

// ICE attributes:

  IceControlled(0x8029),
  IceControlling(0x802A);

  const AttributeType(this.value);

  final int value;

  factory AttributeType.fromInt(int key) {
    return values.firstWhere((element) => element.value == key,
        orElse: () => throw Exception(
            "Unknown attribute type: 0x${key.toRadixString(16).padLeft(4, '0')}"));
  }
}

class attributeTypeDef {
  String name;
  attributeTypeDef(this.name);

  @override
  String toString() {
    return "attributeTypeDef{attributeType: $name}";
  }
}

// func (at AttributeType) String() string {
// 	attributeTypeDef, ok := attributeTypeMap[at]
// 	if !ok {
// 		// Just return hex representation of unknown attribute type.
// 		return fmt.Sprintf("0x%x", uint16(at))
// 	}
// 	return attributeTypeDef.Name
// }
