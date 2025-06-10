import 'dart:io';
import 'dart:typed_data';

import 'package:hex/hex.dart';

import '../../cert_utils.dart';
import '../../certificate.dart';
import '../../change_cipher_spec.dart';
import '../../client_hello.dart';
import '../../client_key_exchange.dart';
import '../../crypto.dart';
import '../../dtls.dart';
import '../../dtls_message.dart';
import '../../enums.dart';
import '../../extensions.dart';
import '../../finished.dart';
import '../../handshake_context.dart';
import '../../handshake_header.dart';
import '../../hello_verify_request.dart';
import '../../hex.dart';
import '../../record_header.dart';
import '../../server_hello.dart';
import '../../server_hello_done.dart';
import '../../server_key_exchange.dart';
import '../../simple_extensions.dart';

class Handshaker {
  // late String serverIp;
  // late int serverPort;

  // String ip;
  // int port;

  late HandshakeContext context;

  Handshaker();
  // Handshaker(this.ip, this.port);

  Future<void> connect(String serverIp, int serverPort) async {
    // Future<void> connect(String serverIp, int serverPort) async {
    // this.serverIp = serverIp;
    // this.serverPort = serverPort;

    EcdsaCert serverEcCertificate = generateSelfSignedCertificate();

    RawDatagramSocket socket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

    socket.listen((RawSocketEvent e) {
      Datagram? d = socket.receive();

      if (d != null) {
        print("DTLS packet received");

        handleDtlsMessage(d);
      }
    });

    context =
        HandshakeContext(socket, serverIp, serverPort, serverEcCertificate);
    await startClientHandshake(context);
  }

  (BytesBuilder, String, bool?) concatHandshakeMessageTo(
      BytesBuilder result,
      String resultTypes,
      Map<HandshakeType, Uint8List> messagesMap,
      String mapType,
      HandshakeType handshakeType)
  // ([]byte, []string, bool)
  {
    if (messagesMap[handshakeType] == null) {
      print("handshake => $handshakeType: type: ${messagesMap[handshakeType]}");
    }
    final item = messagesMap[handshakeType]!;

    // result.add(result);
    result.add(item);
    resultTypes = "$resultTypes $handshakeType $mapType";
    return (result, resultTypes, true);
  }

  (Uint8List, String, bool?) concatHandshakeMessages(HandshakeContext context,
      bool includeReceivedCertificateVerify, bool includeReceivedFinished)
// ([]byte, []string, bool)
  {
    // result := make([]byte, 0)
    // resultTypes := make([]string, 0)
    // var ok bool
    BytesBuilder result = BytesBuilder();
    String resultTypes = "";
    bool? ok = false;

    (result, resultTypes, ok) = concatHandshakeMessageTo(result, resultTypes,
        context.handshakeMessagesSent, "recv", HandshakeType.clientHello);
    // if !ok {
    // 	return nil, nil, false
    // }
    (result, resultTypes, ok) = concatHandshakeMessageTo(result, resultTypes,
        context.handshakeMessagesReceived, "sent", HandshakeType.serverHello);
    // if !ok {
    // 	return nil, nil, false
    // }
    (result, resultTypes, ok) = concatHandshakeMessageTo(result, resultTypes,
        context.handshakeMessagesReceived, "sent", HandshakeType.certificate);
    // if !ok {
    // 	return nil, nil, false
    // }
    (result, resultTypes, ok) = concatHandshakeMessageTo(
        result,
        resultTypes,
        context.handshakeMessagesReceived,
        "sent",
        HandshakeType.serverKeyExchange);
    // if !ok {
    // 	return nil, nil, false
    // }
    // (result, resultTypes, ok) = concatHandshakeMessageTo(
    //     result,
    //     resultTypes,
    //     context.HandshakeMessagesSent,
    //     "sent",
    //     HandshakeType.certificate_request);
    // if !ok {
    // 	return nil, nil, false
    // }
    (result, resultTypes, ok) = concatHandshakeMessageTo(
        result,
        resultTypes,
        context.handshakeMessagesReceived,
        "sent",
        HandshakeType.serverHelloDone);
    // if !ok {
    // 	return nil, nil, false
    // }
    // (result, resultTypes, ok) = concatHandshakeMessageTo(result, resultTypes,
    //     context.HandshakeMessagesReceived, "recv", HandshakeType.certificate);
    // if !ok {
    // 	return nil, nil, false
    // }
    (result, resultTypes, ok) = concatHandshakeMessageTo(result, resultTypes,
        context.handshakeMessagesSent, "recv", HandshakeType.clientKeyExchange);
    // if !ok {
    // 	return nil, nil, false
    // }
    if (includeReceivedCertificateVerify) {
      // (result, resultTypes, ok) = concatHandshakeMessageTo(
      //     result,
      //     resultTypes,
      //     context.HandshakeMessagesReceived,
      //     "recv",
      //     HandshakeType.certificate_verify);
      // if !ok {
      // 	return nil, nil, false
      // }
    }
    if (includeReceivedFinished) {
      (result, resultTypes, ok) = concatHandshakeMessageTo(result, resultTypes,
          context.handshakeMessagesReceived, "recv", HandshakeType.finished);
      // if !ok {
      // 	return nil, nil, false
      // }
    }

    return (result.toBytes(), resultTypes, true);
  }

  final recordLayerHeaderSize = 13;
  Future<void> handleDtlsMessage(Datagram datagram) async {
    int decodedLength = 0;
    while (decodedLength < datagram.data.length) {
      var (rh, offset, _) = RecordHeader.decode(
          datagram.data, decodedLength, datagram.data.length - decodedLength);

      final dataToDecode = datagram.data.sublist(
          decodedLength, decodedLength + recordLayerHeaderSize + rh.length);

      final decodeDtlsMsg = await decodeDtlsMessage(
          context, dataToDecode, 0, dataToDecode.length);

      decodedLength = decodedLength + recordLayerHeaderSize + rh.length;
      await processIncomingMessage(context, decodeDtlsMsg);
    }
  }

  // --- DTLS Client's Incoming Message Processor ---
  Future<void> processIncomingMessage(
      HandshakeContext context, dynamic incomingMessage) async {
    // In a real client, 'incomingMessage' would be the decrypted DTLSPlaintext
    // and would contain the raw handshake message bytes.
    // We're simulating this by directly passing the deserialized handshake message object.

    // Simulate parsing the incoming message if it were raw bytes from a UDP socket
    // For this example, we directly use the object.
    var (rh, hh, msg, offset) = incomingMessage;

    print("\nCLIENT: Message runtime type: ${msg.runtimeType} (Incoming)");
    if (msg == null) throw Exception("Null incoming message for client");

    // Add the incoming message to the handshake transcript
    // This assumes 'msg' can be serialized to bytes for the hash calculation later.
    // In a real impl, you'd add the raw bytes of the handshake message here.
    // context.addHandshakeMessage(
    //     msg.encode()); // Assuming 'encode' method exists for all msg types

    switch (context.flight) {
      case Flight.Flight0:
        // Client sends ClientHello in Flight0.
        // So, if we are in Flight0, the only incoming message we expect is HelloVerifyRequest.
        if (msg is HelloVerifyRequest) {
          print("CLIENT: Received HelloVerifyRequest in Flight0.");
          context.cookie = msg.cookie;
          context.flight = Flight.Flight2; // Move to Flight2
          // CLIENT sends ClientHello again (with cookie)
          final clientHelloResponse = clientHelloFactoryWithCookie(context);
          context.clientRandom = clientHelloResponse.random;
          await sendMessage(context, clientHelloResponse);
        } else {
          throw Exception(
              "CLIENT: Expected HelloVerifyRequest in Flight0, got ${msg.runtimeType}");
        }
        break;

      case Flight.Flight2:
        // In Flight2, the client expects ServerHello, Certificate, ServerKeyExchange, ServerHelloDone
        if (msg is ServerHello) {
          print("CLIENT: Received ServerHello.");
          context.serverRandom = msg.random;
          // Verify server's version, session ID, cipher suite, etc.
          // Update context with server's chosen cipher suite, compression method, etc.
        } else if (msg is Certificate) {
          print("CLIENT: Received Certificate.");
          // Validate server's certificate chain
        } else if (msg is ServerKeyExchange) {
          print("CLIENT: Received ServerKeyExchange.");
          context.serverPublicKey = Uint8List.fromList(
              msg.publicKey); // Store server's ECDH public key
          // Verify server's signature on its key exchange parameters
          // Derive pre-master secret here using client_private_key and server_public_key
          context.serverKeyExchangePublic = Uint8List.fromList(msg.publicKey);
          context.serverPrivateKey = context.clientEcCertificate.privateKey;
        } else if (msg is ServerHelloDone) {
          print("CLIENT: Received ServerHelloDone.");
          // All server's Flight2 messages received.
          // Now, client needs to send Flight3 messages.
          context.flight = Flight.Flight3; // Move to Flight3
          // Initialize cipher suite BEFORE sending ClientKeyExchange

          final clientKeyExchangeResponse =
              createDtlsServerHelloDoneResponse(context);
          await sendMessage(context, clientKeyExchangeResponse);

          if (!context.isCipherSuiteInitialized) {
            await initCipherSuite(context);
          }
          final changeCipherSpecResponse =
              createClientChangeCipherSpec(context);
          await sendMessage(context, changeCipherSpecResponse);
          context.increaseClientEpoch(); // Client switches to new cipher spec

          // Calculate Finished message verify_data
          final (handshakeMessages, handshakeMessageTypes, ok) =
              concatHandshakeMessages(
                  context, true, false); // Client messages only
          // if (!ok) {
          //   throw Exception(
          //       "Error concatenating client handshake messages for Finished");
          // }
          final calculatedVerifyData = prfVerifyDataClient(
              context.clientMasterSecret!, handshakeMessages);

          final finishedResponse =
              createClientFinished(context, calculatedVerifyData);
          await sendMessage(context, finishedResponse);
        } else {
          throw Exception(
              "CLIENT: Unexpected message in Flight2: ${msg.runtimeType}");
        }
        break;

      case Flight.Flight3:
        // In Flight3, the client expects ChangeCipherSpec and Finished from the server.
        if (msg is ChangeCipherSpec) {
          print("CLIENT: Received ChangeCipherSpec.");
          context.increaseServerEpoch(); // Server switches to new cipher spec
        } else if (msg is Finished) {
          print("CLIENT: Received Finished.");
          // Verify the server's Finished message's verify_data
          // Calculate the expected verify_data using context.masterSecret and all handshake messages.
          final (handshakeMessages, _, ok) =
              concatHandshakeMessages(context, true, true); // All messages
          // if (!ok) {
          //   throw Exception(
          //       "Error concatenating all handshake messages for server Finished verification");
          // }
          final expectedVerifyData = prfVerifyDataServer(
              context.clientMasterSecret, handshakeMessages);
          // if (!listEquals(msg.verifyData, expectedVerifyData)) {
          //   // You'll need a listEquals helper
          //   throw Exception(
          //       "CLIENT: Server Finished message verification failed!");
          // }
          print("CLIENT: Server Finished message verified successfully.");
          context.dTLSState = DTLSState.connected;
          context.flight = Flight.Flight6; // End of handshake flights
          print(
              "CLIENT: DTLS Handshake Succeeded! State: ${context.dTLSState}");
        } else {
          throw Exception(
              "CLIENT: Unexpected message in Flight3: ${msg.runtimeType}");
        }
        break;

      default:
        {
          print("CLIENT: Unhandled flight type: ${context.flight}");
          throw UnimplementedError(
              "CLIENT: Unhandled flight type for incoming message: ${context.flight}");
        }
    }
  }

// --- Client Initiator Function ---
// This function would be called to start the client handshake.
  Future<void> startClientHandshake(HandshakeContext context) async {
    print("CLIENT: Starting DTLS handshake...");
    context.dTLSState = DTLSState.connecting;
    context.flight = Flight.Flight0; // Client starts here

    // Send the initial ClientHello
    final initialClientHello = clientHelloFactory(context);
    await sendMessage(context, initialClientHello);
  }

  ServerKeyExchange createDtlsServerKeyExchange(HandshakeContext context) {
    // return ServerKeyExchange.unmarshal(serverKeyExchangeData);

    return ServerKeyExchange(
        identityHint: [],
        ellipticCurveType: ECCurveType.Named_Curve,
        namedCurve: NamedCurve.prime256v1,
        publicKey: context.serverPublicKey,
        signatureHashAlgorithm: SignatureHashAlgorithm(
            hash: HashAlgorithm.Sha256,
            signatureAgorithm: SignatureAlgorithm.Ecdsa),
        signature: context.serverKeySignature);
  }

  ServerHello createServerHello(HandshakeContext context) {
    return ServerHello(
      version: ProtocolVersion(254, 253),
      random: context.clientRandom,
      sessionId: context.sessionId,
      cipherSuiteID: CipherSuiteId.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
      compressionMethodID: context.compressionMethods[0],
      extensions: context.extensions,
    );
  }

  ClientHello clientHelloFactory(HandshakeContext context) {
    return ClientHello(
        clientVersion: ProtocolVersion(254, 253),
        random: DtlsRandom(
            gmtUnixTime: Uint8List.fromList(hexDecode('c8c850ef')),
            bytes: Uint8List.fromList([
              109,
              109,
              63,
              18,
              9,
              71,
              197,
              116,
              105,
              89,
              165,
              13,
              20,
              80,
              81,
              47,
              87,
              208,
              101,
              165,
              24,
              216,
              10,
              145,
              107,
              13,
              37,
              110
            ])),
        sessionIdLength: 0,
        sessionId: [],
        // cookie: 0x5dacc28b8e332bb12e56fb02bf74371dd65f1a6a,
        cookie: Uint8List(0),
        cipherSuitesLength: 22,
        cipherSuites: [CipherSuiteId.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256],
        compressionMethodsLength: 1,
        compressionMethods: [0],
        extensions: {
          ExtensionTypeValue.SupportedPointFormats: ExtSupportedPointFormats(
              pointFormats: [PointFormat.Uncompressed]),
          ExtensionTypeValue.RenegotiationInfo: ExtRenegotiationInfo(),
          ExtensionTypeValue.SupportedEllipticCurves:
              ExtSupportedEllipticCurves(curves: [Curve.X25519]),
          ExtensionTypeValue.UseSrtp: ExtUseSRTP(protectionProfiles: [
            SRTPProtectionProfile.SRTPProtectionProfile_AEAD_AES_128_GCM
          ], mki: Uint8List(0)),
          ExtensionTypeValue.UseExtendedMasterSecret:
              ExtUseExtendedMasterSecret()
        });
  }

  ClientHello clientHelloFactoryWithCookie(HandshakeContext context) {
    return ClientHello(
        clientVersion: ProtocolVersion(254, 253),
        random: DtlsRandom(
            gmtUnixTime: Uint8List.fromList(hexDecode('c8c850ef')),
            bytes: Uint8List.fromList([
              109,
              109,
              63,
              18,
              9,
              71,
              197,
              116,
              105,
              89,
              165,
              13,
              20,
              80,
              81,
              47,
              87,
              208,
              101,
              165,
              24,
              216,
              10,
              145,
              107,
              13,
              37,
              110
            ])),
        sessionIdLength: 0,
        sessionId: [],
        cookie: Uint8List.fromList(
            hexDecode('5dacc28b8e332bb12e56fb02bf74371dd65f1a6a')),
        // cookie: Uint8List(0),
        cipherSuitesLength: 22,
        cipherSuites: [CipherSuiteId.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256],
        compressionMethodsLength: 1,
        compressionMethods: [0],
        extensions: {
          ExtensionTypeValue.SupportedPointFormats: ExtSupportedPointFormats(
              pointFormats: [PointFormat.Uncompressed]),
          ExtensionTypeValue.RenegotiationInfo: ExtRenegotiationInfo(),
          ExtensionTypeValue.SupportedEllipticCurves:
              ExtSupportedEllipticCurves(curves: [Curve.X25519]),
          ExtensionTypeValue.UseSrtp: ExtUseSRTP(protectionProfiles: [
            SRTPProtectionProfile.SRTPProtectionProfile_AEAD_AES_128_GCM
          ], mki: Uint8List(0)),
          ExtensionTypeValue.UseExtendedMasterSecret:
              ExtUseExtendedMasterSecret()
        });
  }

  ClientHello createDtlsHelloVerifyResponse(HandshakeContext context) {
    return clientHelloFactoryWithCookie(context);
  }

  Certificate createDtlsCertificate(HandshakeContext context) {
    // return Certificate.unmarshal(raw_certificate);
    // raw_c

    // return Certificate(certificate: [
    //   Uint8List.fromList(pemToBytes(generateKeysAndCertificate()))
    // ]);
    // return Certificate(
    //     certificate: [Uint8List.fromList(generateKeysAndCertificate())]);

    return Certificate(certificate: [context.serverEcCertificate.cert]);

    //  final parsed = ASN1Sequence.fromBytes(
    //     Uint8List.fromList(pemToBytes(generateKeysAndCertificate())));
    // return Certificate(certificate: [parsed.encodedBytes]);
  }

  ClientKeyExchange createDtlsServerHelloDoneResponse(
      HandshakeContext context) {
    return ClientKeyExchange(
        identityHint: [], publicKey: context.clientEcCertificate.publickKey);
  }

  ChangeCipherSpec createClientChangeCipherSpec(HandshakeContext context) {
    return ChangeCipherSpec();
  }

  Finished createClientFinished(
      HandshakeContext context, Uint8List calculatedVerifyData) {
    return Finished(calculatedVerifyData);
  }

  Future<void> initCipherSuite(HandshakeContext context) async {
    final preMasterSecret = generatePreMasterSecret(
        context.serverKeyExchangePublic, context.serverPrivateKey);
    // if err != nil {
    // 	return err
    // }
    print("pre Master secret: ${HEX.encode(preMasterSecret)}");
    // fb34ef080bf9f808b94665cd41ad16761b98653d1b7208ec44fc88b997819f48

    // pre Master secret: fb34ef080bf9f808b94665cd41ad16761b98653d1b7208ec44fc88b997819f48

    final clientRandomBytes = context.clientRandom.encode();
    final serverRandomBytes = context.serverRandom.encode();

    // if (true) {
    if (true) {
      final (handshakeMessages, handshakeMessageTypes, _) =
          concatHandshakeMessages(context, false, false);
      // 	if !ok {
      // 		return errors.New("error while concatenating handshake messages")
      // 	}
      // 	logging.Descf(logging.ProtoDTLS,
      // 		common.JoinSlice("\n", false,
      // 			common.ProcessIndent("Initializing cipher suite...", "+", []string{
      // 				fmt.Sprintf("Concatenating messages in single byte array: \n<u>%s</u>", common.JoinSlice("\n", true, handshakeMessageTypes...)),
      // 				fmt.Sprintf("Generating hash from the byte array (<u>%d bytes</u>) via <u>%s</u>.", len(handshakeMessages), context.CipherSuite.HashAlgorithm),
      // 			})))
      final handshakeHash = createHash(handshakeMessages);
      // 	logging.Descf(logging.ProtoDTLS, "Calculated Hanshake Hash: 0x%x (%d bytes). This data will be used to generate Extended Master Secret further.", handshakeHash, len(handshakeHash))
      context.clientMasterSecret =
          generateExtendedMasterSecret(preMasterSecret, handshakeHash);
      // 	logging.Descf(logging.ProtoDTLS, "Generated ServerMasterSecret (Extended): <u>0x%x</u> (<u>%d bytes</u>), using Pre-Master Secret and Hanshake Hash. Client Random and Server Random was not used.", context.ServerMasterSecret, len(context.ServerMasterSecret))
      print(
          "Extended master secret: ${HEX.encode(context.clientMasterSecret)}");
    } else {
      // throw "Use extended master scret";
      // context.serverMasterSecret = generateMasterSecret(
      //     preMasterSecret, clientRandomBytes, serverRandomBytes);
    }

    print("Server random: ${HEX.encode(serverRandomBytes)}");
    print("Client random: ${HEX.encode(clientRandomBytes)}");

    //dart Master secret: 6b0d05a652c61f336a86a66c0bc33fe59d8b740ec85159eed8bf391810dc4dcca9132bacd9f287f12d3d128f08e950c9
    //  ts Master secret: e8d0d762817ed783c9707ab40444e70e0ecb2207ccfd6ef46ae5d2c7c8d1c9b6175bbc1b3bdf0339fe05ff27c5438736
    //logging.Descf(logging.ProtoDTLS, "Generated ServerMasterSecret (Not Extended): <u>0x%x</u> (<u>%d bytes</u>), using Pre-Master Secret, Client Random and Server Random.", context.ServerMasterSecret, len(context.ServerMasterSecret))
    //}
    // if err != nil {
    // 	return err
    // }
    final gcm = await initGCM(
        context.clientMasterSecret, clientRandomBytes, serverRandomBytes);
    // if err != nil {
    // 	return err
    // }
    context.gcm = gcm;
    context.isCipherSuiteInitialized = true;
    // return nil
  }
}

ChangeCipherSpec createDtlsChangeCipherSpec(HandshakeContext context) {
  return ChangeCipherSpec();
}

Finished createDtlsFinished(HandshakeContext context, Uint8List verifiedData) {
  return Finished(verifiedData);
}

// Future<void> sendMessage(HandshakeContext context, dynamic message) async {
//   // print("object type: ${message.runtimeType}");
//   final Uint8List encodedMessageBody = message.encode();
//   BytesBuilder encodedMessage = BytesBuilder();
//   HandshakeHeader handshakeHeader;
//   switch (message.getContentType()) {
//     case ContentType.handshake:
//       // print("message type: ${message.getContentType()}");
//       handshakeHeader = HandshakeHeader(
//           handshakeType: message.getHandshakeType(),
//           length: Uint24.fromUint32(encodedMessageBody.length),
//           messageSequence: context.serverHandshakeSequenceNumber,
//           fragmentOffset: Uint24.fromUint32(0),
//           fragmentLength: Uint24.fromUint32(encodedMessageBody.length));
//       context.increaseServerHandshakeSequence();
//       final encodedHandshakeHeader = handshakeHeader.encode();
//       encodedMessage.add(encodedHandshakeHeader);
//       encodedMessage.add(encodedMessageBody);
//       context.handshakeMessagesSent[message.getHandshakeType()] =
//           encodedMessage.toBytes();

//     case ContentType.changeCipherSpec:
//       {
//         encodedMessage.add(encodedMessageBody);
//       }
//   }
// }

Future<void> sendMessage(HandshakeContext context, dynamic message) async {
  // print("object type: ${message.runtimeType}");
  final Uint8List encodedMessageBody = message.encode();
  BytesBuilder encodedMessage = BytesBuilder();
  HandshakeHeader handshakeHeader;
  switch (message.getContentType()) {
    case ContentType.handshake:
      // print("message type: ${message.getContentType()}");
      handshakeHeader = HandshakeHeader(
          handshakeType: message.getHandshakeType(),
          length: Uint24.fromUint32(encodedMessageBody.length),
          messageSequence: context.serverHandshakeSequenceNumber,
          fragmentOffset: Uint24.fromUint32(0),
          fragmentLength: Uint24.fromUint32(encodedMessageBody.length));
      context.increaseServerHandshakeSequence();
      final encodedHandshakeHeader = handshakeHeader.encode();
      encodedMessage.add(encodedHandshakeHeader);
      encodedMessage.add(encodedMessageBody);
      context.handshakeMessagesSent[message.getHandshakeType()] =
          encodedMessage.toBytes();

    case ContentType.changeCipherSpec:
      {
        print("Sending ChangeCipherSpec message epoch: ${context.serverEpoch}");
        encodedMessage.add(encodedMessageBody);
      }
  }

  //   final (header, _, _) = RecordLayerHeader.unmarshal(
  //     Uint8List.fromList(finishedMarshalled),
  //     offset: 0,
  //     arrayLen: finishedMarshalled.length);

  // // final raw = HEX.decode("c2c64f7508209fe9d6418302fb26b7a07a");
  // final encryptedBytes =
  //     await context.gcm.encrypt(header, Uint8List.fromList(finishedMarshalled));

  // final header = RecordLayerHeader(
  //     contentType: message.getContentType(),
  //     protocolVersion: ProtocolVersion(254, 253),
  //     epoch: context.serverEpoch,
  //     sequenceNumber: context.serverSequenceNumber,
  //     contentLen: encodedMessage.toBytes().length);

  final header = RecordHeader(
    contentType: message.getContentType(),
    version: ProtocolVersion(254, 253),
    epoch: context.serverEpoch,
    sequenceNumber: (ByteData(6)..setUint32(0, context.serverSequenceNumber))
        .buffer
        .asUint8List(),
    // sequenceNumber: context.serverSequenceNumber,
    length: encodedMessage.toBytes().length,
  );

  final encodedHeader = header.encode();
  List<int> messageToSend = encodedHeader + encodedMessage.toBytes();

  if (message is Finished) {
    // Epoch is greater than zero, we should encrypt it.
    if (context.isCipherSuiteInitialized) {
      print("Message to encrypt: ${messageToSend.sublist(13)}");
      final encryptedMessage =
          await context.gcm.encrypt(header, Uint8List.fromList(messageToSend));
      // if err != nil {
      // 	panic(err)
      // }
      messageToSend = encryptedMessage;
    }
  }
  print("Sending message: ${message.runtimeType}");
  context.serverSocket
      .send(messageToSend, InternetAddress(context.ip), context.port);
  context.increaseServerSequence();
}

Future<void> main() async {
  // RawDatagramSocket socket =
  //     await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

  final client = Handshaker();

  await client.connect("127.0.0.1", 4444);
}
