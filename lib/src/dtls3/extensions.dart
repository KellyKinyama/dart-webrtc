// Minimal restoration of the legacy `lib/src/dtls3/extensions.dart` API.
//
// The real implementation lived in a now-deleted `dtls3/` directory. Only
// the types referenced by `lib/src/dtls/handshake/...` are recreated here:
// the [Extension] base class and the [ExtensionTypeValue] enum.
//
// Concrete extensions (UseSRTP, etc.) live in `simple_extensions.dart`.

import 'dart:typed_data';

/// IANA TLS extension types we recognize. `Unsupported` is the catch-all
/// for everything else; `decodeExtensionMap` maps it to [ExtUnknown].
enum ExtensionTypeValue {
  ServerName(0),
  SupportedEllipticCurves(10),
  SupportedPointFormats(11),
  SupportedSignatureAlgorithms(13),
  UseSrtp(14),
  UseExtendedMasterSecret(23),
  RenegotiationInfo(65281),
  Unsupported(0xFFFF);

  const ExtensionTypeValue(this.value);
  final int value;

  static ExtensionTypeValue fromInt(int key) => values.firstWhere(
        (e) => e.value == key,
        orElse: () => ExtensionTypeValue.Unsupported,
      );
}

/// Base class for a parsed TLS extension. Concrete subclasses live in
/// `simple_extensions.dart`. Every subclass must round-trip through
/// [encode] so `ServerHello.marshal` can re-emit the same bytes.
abstract class Extension {
  /// IANA-typed kind of this extension.
  ExtensionTypeValue extensionType();

  /// Body bytes (the value field of the TLS extension TLV).
  Uint8List encode();
}
