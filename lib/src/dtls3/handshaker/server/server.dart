import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// import 'package:events_emitter/events_emitter.dart';
// import '../../dtls/dtls_message.dart';
import 'package:hex/hex.dart';

import '../../algo_pair.dart';
import '../../cert_utils.dart';
import '../../certificate.dart';
import '../../change_cipher_spec.dart';
import '../../client_hello.dart';
import '../../client_key_exchange.dart';
import '../../crypto.dart';
import '../../dtls.dart';
import '../../dtls_message.dart';
import '../../enums.dart';
import '../../finished.dart';
import '../../handshake_context.dart';
import '../../handshake_header.dart';
import '../../hello_verify_request.dart';
import '../../record_header.dart';
import '../../server_hello.dart';
import '../../server_hello_done.dart';
import '../../server_key_exchange.dart';

Uint8List generateDtlsCookie() {
  final cookie = Uint8List(20);
  final random = Random.secure();
  for (int i = 0; i < cookie.length; i++) {
    cookie[i] = random.nextInt(256);
  }
  return cookie;
}

class HandshakeManager {
  RawDatagramSocket serverSocket;

  late EcdsaCert serverEcCertificate;

  HandshakeManager(this.serverSocket) {
    serverEcCertificate = generateSelfSignedCertificate();
  }
  Map<String, HandshakeContext> clients = {};

  final recordLayerHeaderSize = 13;
  Future<void> handleDtlsMessage(Datagram datagram) async {
    final key = "${datagram.address.address}:${datagram.port}";

    if (clients[key] == null) {
      clients[key] = HandshakeContext(serverSocket, datagram.address.address,
          datagram.port, serverEcCertificate,DTLSRole.server);
    }

    int decodedLength = 0;
    while (decodedLength < datagram.data.length) {
      var (rh, offset, _) = RecordHeader.decode(
          datagram.data, decodedLength, datagram.data.length - decodedLength);

      final dataToDecode = datagram.data.sublist(
          decodedLength, decodedLength + recordLayerHeaderSize + rh.length);

      final decodeDtlsMsg = decodeDtlsMessage(
          clients[key]!, dataToDecode, 0, dataToDecode.length);

      decodedLength = decodedLength + recordLayerHeaderSize + rh.length;
      await processIncomingMessage(clients[key]!, decodeDtlsMsg);
    }
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
        context.handshakeMessagesReceived, "recv", HandshakeType.clientHello);
    // if !ok {
    // 	return nil, nil, false
    // }
    (result, resultTypes, ok) = concatHandshakeMessageTo(result, resultTypes,
        context.handshakeMessagesSent, "sent", HandshakeType.serverHello);
    // if !ok {
    // 	return nil, nil, false
    // }
    (result, resultTypes, ok) = concatHandshakeMessageTo(result, resultTypes,
        context.handshakeMessagesSent, "sent", HandshakeType.certificate);
    // if !ok {
    // 	return nil, nil, false
    // }
    (result, resultTypes, ok) = concatHandshakeMessageTo(result, resultTypes,
        context.handshakeMessagesSent, "sent", HandshakeType.serverKeyExchange);
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
    (result, resultTypes, ok) = concatHandshakeMessageTo(result, resultTypes,
        context.handshakeMessagesSent, "sent", HandshakeType.serverHelloDone);
    // if !ok {
    // 	return nil, nil, false
    // }
    // (result, resultTypes, ok) = concatHandshakeMessageTo(result, resultTypes,
    //     context.HandshakeMessagesReceived, "recv", HandshakeType.certificate);
    // if !ok {
    // 	return nil, nil, false
    // }
    (result, resultTypes, ok) = concatHandshakeMessageTo(
        result,
        resultTypes,
        context.handshakeMessagesReceived,
        "recv",
        HandshakeType.clientKeyExchange);
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

  Future<void> processIncomingMessage(
      HandshakeContext context, dynamic incomingMessage) async {
    var (rh, hh, msg, offset) = await incomingMessage;

    print("Message runtime type: ${msg.runtimeType}");
    if (msg == null) throw Exception("Null message");
    switch (msg.runtimeType) {
      case ClientHello:
        {
          msg = msg as ClientHello;
          print("Message case type: ${msg.runtimeType}");
          switch (context.flight) {
            case Flight.Flight0:
              context.dTLSState = DTLSState.connecting;
              context.protocolVersion = msg.clientVersion;
              context.cookie = generateDtlsCookie();
              context.clientRandom = msg.random;
              context.sessionId = msg.sessionId;
              context.extensions = msg.extensions;
              context.compressionMethods = msg.compressionMethods;

              context.flight = Flight.Flight2;

              final helloVerifyRequestResponse =
                  createDtlsHelloVerifyRequest(context);
              await sendMessage(context, helloVerifyRequestResponse);
              break;

            case Flight.Flight2:
              if (msg.cookie.isEmpty) {
                break;
              } else {
                print("Received cookie: ${msg.cookie}");

                context.serverRandom = context.clientRandom;
                final clientRandomBytes = context.clientRandom.encode();
                final serverRandomBytes = context.serverRandom.encode();

                context.serverPublicKey =
                    context.serverEcCertificate.publickKey;
                context.serverPrivateKey =
                    context.serverEcCertificate.privateKey;

                context.serverKeySignature = generateKeySignature(
                    clientRandomBytes,
                    serverRandomBytes,
                    context.serverPublicKey,
                    // context.curve, //x25519
                    context.serverPrivateKey);

                context.flight = Flight.Flight4;

                final serverHelloResponse = createServerHello(context);
                await sendMessage(context, serverHelloResponse);

                final certificateResponse = createDtlsCertificate(context);
                await sendMessage(context, certificateResponse);
                final serverKeyExchangeResponse =
                    createDtlsServerKeyExchange(context);
                await sendMessage(context, serverKeyExchangeResponse);
                // final certificateRequestResponse =
                //     createDtlsCertificateRequest(context);
                // sendMessage(context, certificateRequestResponse);
                final serverHelloDoneResponse =
                    createDtlsServerHelloDone(context);
                await sendMessage(context, serverHelloDoneResponse);
              }
            default:
              {
                print("Unhandled flight typ: ${context.flight}");
              }
          }
        }
      case ClientKeyExchange:
        msg = msg as ClientKeyExchange;
        context.clientKeyExchangePublic = msg.publicKey;

        if (!context.isCipherSuiteInitialized) {
          await initCipherSuite(context);
          // if err != nil {
          // 	return m.setStateFailed(context, err)
          // }
        }

      case ChangeCipherSpec:
        {
          print("Message: $msg");
        }

      case Finished:
        print("client finished: $msg");
        //logging.Descf(//logging.ProtoDTLS, "Received first encrypted message and decrypted successfully: Finished (epoch was increased to <u>%d</u>)", context.ClientEpoch)
        //logging.LineSpacer(2)

        final (handshakeMessages, handshakeMessageTypes, ok) =
            concatHandshakeMessages(context, true, true);
        // if (!ok) {
        // 	return setStateFailed(context, errors.New("error while concatenating handshake messages"))
        // }
        //logging.Descf(//logging.ProtoDTLS,
        // common.JoinSlice("\n", false,
        // 	common.ProcessIndent("Verifying Finished message...", "+", []string{
        // 		fmt.Sprintf("Concatenating messages in single byte array: \n<u>%s</u>", common.JoinSlice("\n", true, handshakeMessageTypes...)),
        // 		fmt.Sprintf("Generating hash from the byte array (<u>%d bytes</u>) via <u>%s</u>, using server master secret.", len(handshakeMessages), context.CipherSuite.HashAlgorithm),
        // 	})))

        // final handshakeHash = createHash(handshakeMessages);
        final calculatedVerifyData =
            // prfVerifyDataClient(handshakeMessages, context.serverMasterSecret);
            prfVerifyDataServer(context.serverMasterSecret, handshakeMessages);
        print("Finished calculated data: $calculatedVerifyData");
        // if err != nil {
        // 	return m.setStateFailed(context, err)
        // }
        //logging.Descf(//logging.ProtoDTLS, "Calculated Finish Verify Data: <u>0x%x</u> (<u>%d bytes</u>). This data will be sent via Finished message further.", calculatedVerifyData, len(calculatedVerifyData))
        // context.flight = Flight.Flight6;
        // //logging.Descf(//logging.ProtoDTLS, "Running into <u>Flight %d</u>.", context.Flight)
        // //logging.LineSpacer(2)
        final changeCipherSpecResponse = createDtlsChangeCipherSpec(context);
        await sendMessage(context, changeCipherSpecResponse);
        context.increaseServerEpoch();

        final finishedResponse =
            createDtlsFinished(context, calculatedVerifyData);
        //  print("Finished");
        await sendMessage(context, finishedResponse);
        // //logging.Descf(//logging.ProtoDTLS, "Sent first encrypted message successfully: Finished (epoch was increased to <u>%d</u>)", context.ServerEpoch)
        // //logging.LineSpacer(2)

        // //logging.Infof(//logging.ProtoDTLS, "Handshake Succeeded with <u>%v:%v</u>.\n", context.Addr.IP, context.Addr.Port)
        context.dTLSState = DTLSState.connected;

      default:
        {
          print(msg);
          throw UnimplementedError("${msg.runtimeType}");
        }
    }
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

  HelloVerifyRequest createDtlsHelloVerifyRequest(HandshakeContext context) {
    HelloVerifyRequest hvr = HelloVerifyRequest(
        version: context.protocolVersion, cookie: generateDtlsCookie());
    return hvr;
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

  ServerHelloDone createDtlsServerHelloDone(HandshakeContext context) {
    return ServerHelloDone();
  }

  Future<void> initCipherSuite(HandshakeContext context) async {
    final preMasterSecret = generatePreMasterSecret(
        context.clientKeyExchangePublic, context.serverPrivateKey);
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
      context.serverMasterSecret =
          generateExtendedMasterSecret(preMasterSecret, handshakeHash);
      // 	logging.Descf(logging.ProtoDTLS, "Generated ServerMasterSecret (Extended): <u>0x%x</u> (<u>%d bytes</u>), using Pre-Master Secret and Hanshake Hash. Client Random and Server Random was not used.", context.ServerMasterSecret, len(context.ServerMasterSecret))
      print(
          "Extended master secret: ${HEX.encode(context.serverMasterSecret)}");
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
        context.serverMasterSecret, clientRandomBytes, serverRandomBytes);
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

  if (context.serverEpoch > 0) {
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
