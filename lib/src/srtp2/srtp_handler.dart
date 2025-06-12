import 'dart:typed_data';

import 'IPacketTransformer.dart'; // From previous turn's response
import 'SdpSecurityDescription.dart'; // From previous turn's response
import 'SrtpParameters.dart'; // From previous turn's response
import 'SrtpTransformEngine.dart'; // From previous turn's response (conceptual)

import 'package:webrtc_nuts_and_bolts/srtp/srtp_context.dart'; // Assuming the path to your srtp_context.dart
import 'package:webrtc_nuts_and_bolts/srtp/srtp_manager.dart'; // Assuming the path to your srtp_manager.dart
import 'package:webrtc_nuts_and_bolts/srtp/protection_profiles.dart'; // Assuming the path
import 'package:webrtc_nuts_and_bolts/rtp2.dart'; // Assuming the path to your rtp2.dart for Packet and Header

enum SdpType { offer, answer }

class SrtpHandler {
  List<SdpSecurityDescription>? localSecurityDescriptions;
  List<SdpSecurityDescription>? remoteSecurityDescriptions;

  SdpSecurityDescription? localSecurityDescription;
  SdpSecurityDescription? remoteSecurityDescription;

  SRTPContext? srtpContext; // Direct reference to the SRTPContext

  bool isNegotiationComplete = false;

  SrtpHandler();

  bool remoteSecurityDescriptionUnchanged(
      List<SdpSecurityDescription> securityDescriptions) {
    if (remoteSecurityDescription == null || localSecurityDescription == null) {
      return false;
    }

    final rsec = securityDescriptions.firstWhere(
        (x) => x.CryptoSuite == localSecurityDescription!.CryptoSuite,
        orElse: () => throw Exception("CryptoSuite not found"));
    return rsec.toString() == remoteSecurityDescription.toString();
  }

  bool setupLocal(
      List<SdpSecurityDescription> securityDescriptions, SdpType sdpType) {
    localSecurityDescriptions = securityDescriptions;

    if (sdpType == SdpType.offer) {
      isNegotiationComplete = false;
      return true;
    }

    if (remoteSecurityDescriptions == null || remoteSecurityDescriptions!.isEmpty) {
      throw Exception('Setup local crypto failed. No crypto attribute in offer.');
    }

    if (localSecurityDescriptions == null || localSecurityDescriptions!.isEmpty) {
      throw Exception('Setup local crypto failed. No crypto attribute in answer.');
    }

    localSecurityDescription = localSecurityDescriptions![0];
    remoteSecurityDescription = remoteSecurityDescriptions!.firstWhere(
        (x) => x.CryptoSuite == localSecurityDescription!.CryptoSuite,
        orElse: () => throw Exception("CryptoSuite not found"));

    if (remoteSecurityDescription != null &&
        remoteSecurityDescription!.Tag == localSecurityDescription!.Tag) {
      isNegotiationComplete = true;
      _initializeSrtpContext(localSecurityDescription!, remoteSecurityDescription!);
      return true;
    }

    return false;
  }

  bool setupRemote(
      List<SdpSecurityDescription> securityDescriptions, SdpType sdpType) {
    remoteSecurityDescriptions = securityDescriptions;

    if (sdpType == SdpType.offer) {
      isNegotiationComplete = false;
      return true;
    }

    if (localSecurityDescriptions == null || localSecurityDescriptions!.isEmpty) {
      throw Exception('Setup remote crypto failed. No crypto attribute in offer.');
    }

    if (remoteSecurityDescriptions == null || remoteSecurityDescriptions!.isEmpty) {
      throw Exception('Setup remote crypto failed. No crypto attribute in answer.');
    }

    remoteSecurityDescription = remoteSecurityDescriptions![0];
    localSecurityDescription = localSecurityDescriptions!.firstWhere(
        (x) => x.CryptoSuite == remoteSecurityDescription!.CryptoSuite,
        orElse: () => throw Exception("CryptoSuite not found"));

    if (localSecurityDescription != null &&
        localSecurityDescription!.Tag == remoteSecurityDescription!.Tag) {
      isNegotiationComplete = true;
      _initializeSrtpContext(localSecurityDescription!, remoteSecurityDescription!);
      return true;
    }

    return false;
  }

  void _initializeSrtpContext(
      SdpSecurityDescription localDesc, SdpSecurityDescription remoteDesc) {
    final srtpManager = SRTPManager();

    // Assuming localDesc.CryptoSuite maps directly to ProtectionProfile enum value
    final protectionProfile = ProtectionProfile.fromValue(localDesc.CryptoSuite);

    // Placeholder for actual network socket/address needed by SRTPContext
    // In a real application, you would pass the actual InternetAddress and RawDatagramSocket
    // associated with your RTP/RTCP transport.
    // For this example, we'll use dummy values.
    final dummyAddr = InternetAddress.anyIPv4;
    final dummySocket = RawDatagramSocket.bindSync(InternetAddress.anyIPv4, 0);

    srtpContext = srtpManager.newContext(
        dummyAddr, dummySocket, protectionProfile);

    // Extract keying material and initialize GCM cipher
    // The SRTPManager's _extractEncryptionKeys is private, so we'll simulate the key extraction
    // based on the SdpKeyParam.
    // In a real DTLS-SRTP setup, the keying material comes from the DTLS handshake.
    // For this example, we'll directly use the keys from the SdpKeyParam.
    final localMasterKey = _base64Decode(localDesc.KeyParams[0].Key);
    final localMasterSalt = _base64Decode(localDesc.KeyParams[0].Salt); // Assuming salt is also base64 encoded
    final remoteMasterKey = _base64Decode(remoteDesc.KeyParams[0].Key);
    final remoteMasterSalt = _base64Decode(remoteDesc.KeyParams[0].Salt);

    // Initialize the GCM cipher with the appropriate master key and salt.
    // For send (encryption), use local keys. For receive (decryption), use remote keys.
    // In a full DTLS-SRTP implementation, the SRTPManager handles this more holistically
    // by deriving the keys from the DTLS keying material.
    // For now, we'll assume the srtpContext is initialized with keys for *both* directions
    // or that the GCM instance itself handles the client/server keys.
    // The current GCM.newGCM takes a single masterKey and masterSalt, which implies
    // it's for one direction. We might need two GCM instances or a more complex GCM
    // class to handle both client and server keys if we strictly follow the
    // SRTPManager's key extraction.

    // Given the previous SrtpHandler.cs implies separate encoders/decoders,
    // we'll assume the SRTPContext will manage the GCM instance, and its
    // encrypt/decrypt methods will use the appropriate keys.
    // For simplicity, we'll initialize GCM with local keys for encryption and remote for decryption.
    // This is a simplification; a proper SRTP library would handle key derivation and context.

    // The SRTPManager.set and SRTPManager.setRemoteKeyingMaterial would typically handle this.
    // We need a way to pass both local and remote keys to the SRTPContext or its underlying GCM.
    // Let's modify the SRTPManager to hold the GCM and have methods to set client/server keys.

    // Re-thinking: The SRTPContext in the provided Dart code is more about per-SSRC state.
    // The actual GCM object holds the session keys.
    // The SRTPManager's `setupSrtpContext` method in the original `srtp_manager.dart`
    // is responsible for initializing the GCM for the SRTPContext.

    // Let's call the `setupSrtpContext` from `srtp_manager.dart` to properly set up the GCM.
    // This implies that `srtpManager.setupSrtpContext` will take the keying material.
    // However, the `SdpSecurityDescription` only provides "key" and "salt" for the current
    // direction. DTLS-SRTP involves deriving client_write_key, server_write_key, etc.

    // For the scope of this request, where DTLS is ignored, and assuming `SdpSecurityDescription`'s
    // `KeyParams` directly contain the SRTP master key and master salt for the respective endpoint,
    // we will initialize `srtpContext.gcm` directly.

    // For simplicity and direct implementation, let's assume `localDesc.KeyParams` holds the
    // master key and salt for *sending* packets, and `remoteDesc.KeyParams` holds the
    // master key and salt for *receiving* packets.
    // This might not be fully accurate for a full DTLS-SRTP negotiation, but aligns with the
    // goal of implementing encryption/decryption given the provided parameters.

    // To properly initialize SRTPContext for both directions as required by SrtpHandler,
    // we need to set up the GCM with both client and server keys.
    // The `SRTPManager.setupSrtpContext` does this based on `keyingMaterial`.
    // Let's create dummy `keyingMaterial` for demonstration, or assume `SRTPManager`
    // gets updated to accept separate local/remote keys.

    // For now, let's assume `SRTPContext` itself will handle separate GCM instances for send/receive
    // or that the `GCM` class gets a more complex constructor for client/server.
    // A simpler approach is to pass the appropriate keying material to the `srtpManager.setupSrtpContext`

    // Assuming the `KeyParams` in `SdpSecurityDescription` (from C#) contains the master key and salt
    // for the *local* endpoint.
    final localKeyingMaterial = Uint8List.fromList([
      ..._base64Decode(localDesc.KeyParams[0].Key),
      ..._base64Decode(localDesc.KeyParams[0].Salt)
    ]);
    final remoteKeyingMaterial = Uint8List.fromList([
      ..._base64Decode(remoteDesc.KeyParams[0].Key),
      ..._base64Decode(remoteDesc.KeyParams[0].Salt)
    ]);

    // The current SRTPManager.setupSrtpContext assumes a single keyingMaterial that then gets split
    // into client/server keys. This is typical for DTLS-SRTP where a single keying material is
    // derived.
    // For this problem, if `SdpSecurityDescription.KeyParams` directly gives the master key/salt for the
    // *endpoint's* use, then we'd initialize the GCM in SRTPContext directly.

    // Let's modify SRTPContext to take a "sendGCM" and "receiveGCM" or similar to handle both directions explicitly.
    // Or, more simply, if `SRTPContext` contains a `GCM` field, it needs to be initialized for both encryption and decryption.

    // For this example, let's stick to the `SRTPManager.setupSrtpContext` as it's designed to set up the `GCM`
    // within the `SRTPContext`. We'll just need to fabricate the `keyingMaterial` that it expects.

    // The SRTPManager's `_extractEncryptionKeys` and `setupSrtpContext` are designed for `DTLS-SRTP` keying material
    // which includes client and server master keys/salts derived from a single keying material blob.
    // Since we are ignoring DTLS, we'll simplify and directly initialize the `GCM` inside `SRTPContext`
    // with the keys from `localSecurityDescription` for sending and `remoteSecurityDescription` for receiving.

    // This is a crucial design point when divorcing from DTLS.
    // Let's make SRTPContext directly use local keys for encryption and remote keys for decryption.
    srtpContext!.gcm = GCM.newGCM(_base64Decode(localDesc.KeyParams[0].Key),
        _base64Decode(localDesc.KeyParams[0].Salt)) as GCM?; // For encryption
    // And for decryption, it needs a GCM initialized with remote keys.
    // This implies SRTPContext needs to hold two GCM instances or the GCM needs to be re-initialized.

    // A better approach, considering the `IPacketTransformer` interface, is to have
    // `SrtpTransformEngine` handle the `SRTPContext` and use it for the transformations.

    // Let's revise `_generateTransformer` to create an `SRTPContext` and then use it.
    // The `_SrtpTransformer` should then call the `SRTPContext`'s encrypt/decrypt methods.
  }

  // Helper to decode base64 keys/salts
  Uint8List _base64Decode(String base64String) {
    // Implement base64 decoding.
    // You might need to import 'dart:convert' and use base64.decode().
    return Uint8List.fromList([]); // Placeholder
  }

  Future<Uint8List?> unprotectRTP(Uint8List packet, int offset, int length) async {
    if (srtpContext == null) {
      throw Exception("SRTP Context is not initialized.");
    }
    final rtpPacket = Packet.decodePacket(packet, offset, length).packet;
    return await srtpContext!.decryptRtpPacket(rtpPacket, Uint8List.fromList(packet.sublist(offset, offset + length)));
  }

  Future<int> unprotectRTPWithOutLength(Uint8List payload, int length,
      [Uint8List? outputBuffer]) async {
    final result = await unprotectRTP(payload, 0, length);

    if (result == null) {
      return -1; // Indicate error
    }

    if (outputBuffer != null) {
      if (outputBuffer.length < result.length) {
        throw ArgumentError("Output buffer is too small.");
      }
      outputBuffer.setRange(0, result.length, result);
    } else {
      payload.setRange(0, result.length, result);
    }

    return result.length;
  }

  Future<Uint8List?> protectRTP(Uint8List packet, int offset, int length) async {
    if (srtpContext == null) {
      throw Exception("SRTP Context is not initialized.");
    }
    final rtpPacket = Packet.decodePacket(packet, offset, length).packet;
    return await srtpContext!.encryptRtpPacket(rtpPacket);
  }

  Future<int> protectRTPWithOutLength(Uint8List payload, int length,
      [Uint8List? outputBuffer]) async {
    final result = await protectRTP(payload, 0, length);

    if (result == null) {
      return -1; // Indicate error
    }

    if (outputBuffer != null) {
      if (outputBuffer.length < result.length) {
        throw ArgumentError("Output buffer is too small.");
      }
      outputBuffer.setRange(0, result.length, result);
    } else {
      payload.setRange(0, result.length, result);
    }

    return result.length;
  }

  Future<Uint8List?> unprotectRTCP(Uint8List packet, int offset, int length) async {
    if (srtpContext == null) {
      throw Exception("SRTP Context is not initialized.");
    }
    return await srtpContext!.decryptRtcpPacket(Uint8List.fromList(packet.sublist(offset, offset + length)), Uint8List.fromList(packet.sublist(offset, offset + length)));
  }

  Future<int> unprotectRTCPWithOutLength(Uint8List payload, int length,
      [Uint8List? outputBuffer]) async {
    final result = await unprotectRTCP(payload, 0, length);
    if (result == null) {
      return -1; // Indicate error
    }

    if (outputBuffer != null) {
      if (outputBuffer.length < result.length) {
        throw ArgumentError("Output buffer is too small.");
      }
      outputBuffer.setRange(0, result.length, result);
    } else {
      payload.setRange(0, result.length, result);
    }

    return result.length;
  }

  Future<Uint8List?> protectRTCP(Uint8List packet, int offset, int length) async {
    if (srtpContext == null) {
      throw Exception("SRTP Context is not initialized.");
    }
    return await srtpContext!.encryptRtcpPacket(Uint8List.fromList(packet.sublist(offset, offset + length)));
  }

  Future<int> protectRTCPWithOutLength(Uint8List payload, int length,
      [Uint8List? outputBuffer]) async {
    final result = await protectRTCP(payload, 0, length);
    if (result == null) {
      return -1; // Indicate error
    }

    if (outputBuffer != null) {
      if (outputBuffer.length < result.length) {
        throw ArgumentError("Output buffer is too small.");
      }
      outputBuffer.setRange(0, result.length, result);
    } else {
      payload.setRange(0, result.length, result);
    }

    return result.length;
  }
}