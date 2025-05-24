import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../handshake/application.dart';
import '../handshake/change_cipher_spec.dart';
import '../handshake/handshake.dart';
import '../handshake/server_key_exchange.dart';
import 'package:hex/hex.dart';

import '../cert_utils.dart';
import '../crypto.dart';
import '../dtls_message.dart';
import '../dtls_state.dart';
import '../enums.dart';
import '../handshake/certificate.dart';
import '../handshake/certificate_verify.dart';
import '../handshake/client_hello.dart';
import '../handshake/client_key_exchange.dart';
// import '../handshake/extension.dart';
import '../handshake/finished.dart';
import '../handshake/handshake_context.dart';
import '../handshake/handshake_header.dart';
import '../handshake/hello_verify_request.dart';
import '../handshake/server_hello.dart';
import '../handshake/server_hello_done.dart';
import '../handshake/tls_random.dart';
import '../key_exchange_algorithm.dart';
import '../record_layer_header.dart';

HandshakeContext context = HandshakeContext();

class HandshakeManager {
  Uint8List serverCertificate = Uint8List(0);

  RawDatagramSocket socket;
  late int port;

  HandshakeManager(this.socket);

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
        context.HandshakeMessagesReceived, "recv", HandshakeType.client_hello);
    // if !ok {
    // 	return nil, nil, false
    // }
    (result, resultTypes, ok) = concatHandshakeMessageTo(result, resultTypes,
        context.HandshakeMessagesSent, "sent", HandshakeType.server_hello);
    // if !ok {
    // 	return nil, nil, false
    // }
    // (result, resultTypes, ok) = concatHandshakeMessageTo(result, resultTypes,
    //     context.HandshakeMessagesSent, "sent", HandshakeType.certificate);
    // if !ok {
    // 	return nil, nil, false
    // }
    (result, resultTypes, ok) = concatHandshakeMessageTo(
        result,
        resultTypes,
        context.HandshakeMessagesSent,
        "sent",
        HandshakeType.server_key_exchange);
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
        context.HandshakeMessagesSent, "sent", HandshakeType.server_hello_done);
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
        context.HandshakeMessagesReceived,
        "recv",
        HandshakeType.client_key_exchange);
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
          context.HandshakeMessagesReceived, "recv", HandshakeType.finished);
      // if !ok {
      // 	return nil, nil, false
      // }
    }

    return (result.toBytes(), resultTypes, true);
  }

  final recordLayerHeaderSize = 13;
  Future<void> processDtlsMessage(Uint8List data) async {
    int decodedLength = 0;

    while (decodedLength < data.length) {
      print("Decoding Dtls message start lenth: $decodedLength");

      var (rh, offset, _) = RecordLayerHeader.unmarshal(data,
          offset: decodedLength, arrayLen: data.length - decodedLength);
      // print("Record header: $rh");
      final dataToDecode = data.sublist(
          decodedLength, decodedLength + recordLayerHeaderSize + rh.contentLen);

      final dtlsMsg = await DecodeDtlsMessageResult.decode(
          context,
          dataToDecode,
          0,
          dataToDecode.length,
          CipherSuiteId.Tls_Psk_With_Aes_128_Gcm_Sha256);

      print(
          "Dtls message lenth: ${data.length}, decoded length: ${dtlsMsg.finalOffset}");
      decodedLength = decodedLength + recordLayerHeaderSize + rh.contentLen;

      // print("dtls message: $dtlsMsg");
      processIncomingMessage(context, dtlsMsg);
    }
  }

  Future<bool?> processIncomingMessage(
      HandshakeContext context, DecodeDtlsMessageResult incomingMessage) async {
    var message = incomingMessage.message;
    // try {
    //   (message, _, _) = incomingMessage.message;
    // } catch (e, st) {
    //   print("incomingMessage: $message");
    //   print("Error: $e, Stack trace: $st");
    //   message = incomingMessage.message;
    //   if (message.runtimeType != ChangeCipherSpec) {
    //     rethrow;
    //   }
    // }

    print("Message runtime type: ${message.runtimeType}");
    switch (message.runtimeType) {
      case ClientHello:
        message as ClientHello;

        context.session_id = Uint8List.fromList(message.session_id);
        context.compression_methods = message.compression_methods;
        context.extensions = message.extensions;
        context.extensionsData = message.extensionsData!;

        switch (context.flight) {
          case Flight.Flight0:
            context.dTLSState = DTLSState.DTLSStateConnecting;
            context.protocolVersion = message.client_version;
            context.cookie = generateDtlsCookie();
            // logging.Descf(logging.ProtoDTLS, "DTLS Cookie was generated and set to <u>0x%x</u> in handshake context (<u>%d bytes</u>).", context.Cookie, len(context.Cookie))
            context.clientRandom = message.random;
            context.flight = Flight.Flight2;
            // logging.Descf(logging.ProtoDTLS, "Running into <u>Flight %d</u>.", context.Flight)
            // logging.LineSpacer(2)
            final helloVerifyRequestResponse =
                createDtlsHelloVerifyRequest(context);
            await sendMessage(context, helloVerifyRequestResponse);
            return null;
          case Flight.Flight2:
            if (message.cookie.length == 0) {
              context.flight = Flight.Flight0;
              // logging.Errorf(logging.ProtoDTLS, "Expected not empty Client Hello Cookie but <nil> found!")
              // logging.Descf(logging.ProtoDTLS, "Running into <u>Flight %d</u>.", context.Flight)
              // logging.LineSpacer(2)
              return null;
            }
            // if (!bytes.Equal(context.cookie, message.cookie)) {
            // 	throw ("client hello cookie is invalid");
            // }
            final negotiatedCipherSuite =
                negotiateOnCipherSuiteIDs(message.cipher_suites);
            // if (err != nil {
            // 	return m.setStateFailed(context, err)
            // }
            context.cipherSuite = negotiatedCipherSuite.value;
            // //logging.Descf(//logging.ProtoDTLS, "Negotiation on cipher suites: Client sent a list of cipher suites, server selected one of them (mutually supported), and assigned in handshake context: %s", negotiatedCipherSuite)
            // Convert map entries to a list
            final extensionList = message.extensions;

            for (var extensionItem in extensionList) {
              // print("Extension runtime type: ${extensionItem.runtimeType}");
              // switch (extensionItem) {
              //   case ExtensionType.ExtensionTypeSupportedEllipticCurves:
              //     final negotiatedCurve = negotiateOnCurves(extensionItem);
              //     // if err != nil {
              //     // 	return m.setStateFailed(context, err)
              //     // }
              //     context.curve = negotiatedCurve;
              //   //logging.Descf(//logging.ProtoDTLS, "Negotiation on curves: Client sent a list of curves, server selected one of them (mutually supported), and assigned in handshake context: <u>%s</u>", negotiatedCurve)
              //   case ExtensionType.ExtensionTypeUseSRTP:
              //     final negotiatedProtectionProfile =
              //         negotiateOnSRTPProtectionProfiles(
              //             extensionItem.ProtectionProfiles);
              //     // if err != nil {
              //     // 	return m.setStateFailed(context, err)
              //     // }
              //     context.srtpProtectionProfile = negotiatedProtectionProfile;
              //   //logging.Descf(//logging.ProtoDTLS, "Negotiation on SRTP protection profiles: Client sent a list of SRTP protection profiles, server selected one of them (mutually supported), and assigned in handshake context: <u>%s</u>", negotiatedProtectionProfile)
              //   case ExtensionType.ExtensionTypeUseExtendedMasterSecret:
              //     context.UseExtendedMasterSecret = true;
              //   //logging.Descf(//logging.ProtoDTLS, "Client sent UseExtendedMasterSecret extension, client wants to use ExtendedMasterSecret. We will generate the master secret via extended way further.")
              // }
            }
// print("Client random: ${}")
            // context.clientRandom = message.random;
            //logging.Descf(//logging.ProtoDTLS, "Client sent Client Random, it set to <u>0x%x</u> in handshake context.", message.Random.Encode())
            context.serverRandom = TlsRandom.defaultInstance();
            context.serverRandom.populate();
            // context.serverRandom.generate();
            //logging.Descf(//logging.ProtoDTLS, "We generated Server Random, set to <u>0x%x</u> in handshake context.", context.ServerRandom.Encode())

            final clientRandomBytes = context.clientRandom.raw();
            final serverRandomBytes = context.serverRandom.marshal();
            print("Server random length: ${serverRandomBytes.length}");

            // var keys2 = generateKeys();
            var keys = generateP256Keys();
            // if err != nil {
            // 	return m.setStateFailed(context, err)
            // }

            context.serverPublicKey = keys.publicKey;
            context.serverPrivateKey = keys.privateKey;
            //logging.Descf(//logging.ProtoDTLS, "We generated Server Public and Private Key pair via <u>%s</u>, set in handshake context. Public Key: <u>0x%x</u>", context.Curve, context.ServerPublicKey)

            //logging.Descf(//logging.ProtoDTLS, "Generating ServerKeySignature. It will be sent to client via ServerKeyExchange DTLS message further.")
            context.serverKeySignature = generateKeySignature(
                clientRandomBytes,
                serverRandomBytes,
                context.serverPublicKey,
                // context.curve, //x25519
                context.serverPrivateKey);
            // if err != nil {
            // 	return m.setStateFailed(context, err)
            // }
            //logging.Descf(//logging.ProtoDTLS, "ServerKeySignature was generated and set in handshake context (<u>%d bytes</u>).", len(context.ServerKeySignature))

            context.flight = Flight.Flight4;
            //logging.Descf(//logging.ProtoDTLS, "Running into <u>Flight %d</u>.", context.Flight)
            //logging.LineSpacer(2)
            final serverHelloResponse = createServerHello(context);
            await sendMessage(context, serverHelloResponse);
            // final certificateResponse = createDtlsCertificate();
            // await sendMessage(context, certificateResponse);
            final serverKeyExchangeResponse =
                createDtlsServerKeyExchange(context);
            print(
                "marshal server key exchange: ${serverKeyExchangeResponse.marshal()}");
            await sendMessage(context, serverKeyExchangeResponse);
            // final certificateRequestResponse =
            //     createDtlsCertificateRequest(context);
            // sendMessage(context, certificateRequestResponse);
            final serverHelloDoneResponse = createDtlsServerHelloDone(context);
            await sendMessage(context, serverHelloDoneResponse);

          // final finishedResponse = createDtlsFinished(context);
          // sendMessage(context, finishedResponse);

          default:
            {
              print("Unhandle flight: ${context.flight}");
            }
        }
      case Certificate:
        context.clientCertificates = message.certificates;
        //logging.Descf(//logging.ProtoDTLS, "Generating certificate fingerprint hash from incoming Client Certificate...")
        final certificateFingerprintHash =
            getCertificateFingerprintFromBytes(context.clientCertificates[0]);
        //logging.Descf(//logging.ProtoDTLS, "Checking fingerprint hash of client certificate incoming by this packet <u>%s</u> equals to expected fingerprint hash <u>%s</u> came from Signaling SDP", certificateFingerprintHash, context.ExpectedFingerprintHash)
        if (context.expectedFingerprintHash != certificateFingerprintHash) {
          throw ("incompatible fingerprint hashes from SDP and DTLS data");
        }
      case CertificateVerify:
      //logging.Descf(//logging.ProtoDTLS, "Checking incoming HashAlgorithm <u>%s</u> equals to negotiated before via hello messages <u>%s</u>", message.AlgoPair.HashAlgorithm, context.CipherSuite.HashAlgorithm)
      //logging.Descf(//logging.ProtoDTLS, "Checking incoming SignatureAlgorithm <u>%s</u> equals to negotiated before via hello messages <u>%s</u>", message.AlgoPair.SignatureAlgorithm, context.CipherSuite.SignatureAlgorithm)
      //logging.LineSpacer(2)
      // if (!(context.cipherSuite.HashAlgorithm == message.algoPair.hashAlgorithm &&
      // 	HashAlgorithm(context.cipherSuite.signatureAlgorithm) == HashAlgorithm(message.algoPair.signatureAlgorithm)) {
      // 	throw("incompatible signature scheme");
      // }
      // final (handshakeMessages, handshakeMessageTypes, ok) =
      //     concatHandshakeMessages(context, false, false);
      // if (!ok) {
      //   throw ("error while concatenating handshake messages");
      // }
      //logging.Descf(//logging.ProtoDTLS,
      // common.JoinSlice("\n", false,
      // 	common.ProcessIndent("Verifying client certificate...", "+", []string{
      // 		fmt.Sprintf("Concatenating messages in single byte array: \n<u>%s</u>", common.JoinSlice("\n", true, handshakeMessageTypes...)),
      // 		fmt.Sprintf("Generating hash from the byte array (<u>%d bytes</u>) via <u>%s</u>.", len(handshakeMessages), context.CipherSuite.HashAlgorithm),
      // 		"Verifying the calculated hash, the incoming signature by CertificateVerify message and client certificate public key.",
      // 	})))
      // final err = verifyCertificate(
      //     handshakeMessages,
      //     context.cipherSuite.hashAlgorithm,
      //     message.signature,
      //     context.clientCertificates);
      // if err != nil {
      // 	return m.setStateFailed(context, err)
      // }
      case ClientKeyExchange:
        context.clientKeyExchangePublic = message.publicKey;

        if (!context.isCipherSuiteInitialized) {
          final err = await initCipherSuite(context);
          // if err != nil {
          // 	return m.setStateFailed(context, err)
          // }
        }
      // print("client key exchange: $message");
      // final changeCipherSpecResponse = createDtlsChangeCipherSpec(context);
      // sendMessage(context, changeCipherSpecResponse);

      // final finishedResponse = createDtlsFinished(context);
      // sendMessage(context, finishedResponse);
      // final changeCipherSpecResponse = createDtlsChangeCipherSpec(context);
      // await sendMessage(context, changeCipherSpecResponse);
      // context.increaseServerEpoch();

      case Finished:
        print("client finished: $message");
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
      // context.dTLSState = DTLSState.DTLSStateConnected;

      case ApplicationData:
        sendMessage(context, message);

      default:
        {
          print("Un handled message: $message");
        }
    }
  }

  ServerKeyExchange createDtlsServerKeyExchange(HandshakeContext context) {
    // return ServerKeyExchange.unmarshal(serverKeyExchangeData);

    // return ServerKeyExchange(
    //     identityHint: [],
    //     ellipticCurveType: EllipticCurveType.NamedCurve,
    //     namedCurve: NamedCurve.prime256v1,
    //     publicKey: context.serverPublicKey,
    //     signatureHashAlgorithm: SignatureHashAlgorithm(
    //         hash: HashAlgorithm.Sha256,
    //         signatureAgorithm: SignatureAlgorithm.Ecdsa),
    //     signature: []);
    const _identity = "Client_identity";

    return ServerKeyExchange(
      identityHint: utf8.encode(_identity),
      ellipticCurveType: EllipticCurveType.unsupported,
      namedCurve: NamedCurve.Unsupported,
      publicKey: [],
      signatureHashAlgorithm: SignatureHashAlgorithm(
        hash: HashAlgorithm.unsupported,
        signatureAgorithm: SignatureAlgorithm.unsupported,
      ),
      signature: [],
    );
  }

  Certificate createDtlsCertificate() {
    // return Certificate.unmarshal(raw_certificate);
    // raw_c
    return Certificate(
        certificate: [Uint8List.fromList(generateKeysAndCertificate())]);
  }

  ServerHello createServerHello(HandshakeContext context) {
    // final ch = context.HandshakeMessagesReceived[HandshakeType.client_hello]
    //     as ClientHello;

    // Add only necessary extensions (filter out unwanted ones)
    // final filteredExtensions = context.extensions.entries.where((ext) {
    //   // Keep only extensions that are needed (example: KeyShareExtension)
    //   if (ext is ExtSupportedEllipticCurves) {
    //     final ext2 = ext as ExtSupportedEllipticCurves;
    //     for (final curve in ext2.curves) {
    //       if (curve == 29) {
    //         return true;
    //       } else {
    //         return false;
    //       }
    //     }
    //   } else {
    //     return true;
    //   }
    //   return false;
    // });

    // final ec = ExtSupportedEllipticCurves([23]);

    // context.extensions[ExtensionType.ExtensionTypeSupportedEllipticCurves] = ec;

    // context.extensions.remove(ExtensionType.ExtensionTypeUnknown);

    // context.extensions
    //     .remove(ExtensionType.ExtensionTypeUseExtendedMasterSecret);

    // if (context
    //         .extensions[ExtensionType.ExtensionTypeUseExtendedMasterSecret] !=
    //     null) {
    context.UseExtendedMasterSecret = true;
    // } else {
    //   throw "Use extended master secret";
    // }

    // print("EXtensions: ${context.extensions}");

    return ServerHello(
        ProtocolVersion(254, 253),
        context.serverRandom,
        context.session_id.length,
        context.session_id,
        CipherSuiteId.Tls_Psk_With_Aes_128_Gcm_Sha256.value,
        context.compression_methods[0],
        context.extensions,
        extensionsData: Uint8List.fromList([
          0x00,
          0x09,
          0xff,
          0x01,
          0x00,
          0x01,
          0x00,
          0x00,
          0x17,
          0x00,
          0x00
        ]));
  }

  CipherSuiteId negotiateOnCipherSuiteIDs(List<CipherSuiteId> cipherSuiteIDs) {
    return CipherSuiteId.Tls_Ecdhe_Ecdsa_With_Aes_128_Gcm_Sha256;
  }

  createDtlsCertificateRequest(HandshakeContext context) {}

  ServerHelloDone createDtlsServerHelloDone(HandshakeContext context) {
    return ServerHelloDone();
  }

  verifyCertificate(Object? handshakeMessages, hashAlgorithm, signature,
      clientCertificates) {}

  getCertificateFingerprintFromBytes(clientCertificat) {}

  // initCipherSuite(HandshakeContext context) {}

  verifyFinishedData(
      Object? handshakeMessages, serverMasterSecret, hashAlgorithm) {}

  ChangeCipherSpec createDtlsChangeCipherSpec(HandshakeContext context) {
    return ChangeCipherSpec();
  }

  // extension on HandshakeContext {
  //  void increaseServerEpoch() {}
  // }

  Future<void> sendMessage(HandshakeContext context, dynamic message) async {
    // print("object type: ${message.runtimeType}");
    final Uint8List encodedMessageBody = message.marshal();
    BytesBuilder encodedMessage = BytesBuilder();
    HandshakeHeader handshakeHeader;
    switch (message.getContentType()) {
      case ContentType.content_handshake:
        // print("message type: ${message.getContentType()}");
        handshakeHeader = HandshakeHeader(
            handshakeType: message.getHandshakeType(),
            length: Uint24.fromUInt32(encodedMessageBody.length),
            messageSequence: context.serverHandshakeSequenceNumber,
            fragmentOffset: Uint24.fromUInt32(0),
            fragmentLength: Uint24.fromUInt32(encodedMessageBody.length));
        context.increaseServerHandshakeSequence();
        final encodedHandshakeHeader = handshakeHeader.marshal();
        encodedMessage.add(encodedHandshakeHeader);
        encodedMessage.add(encodedMessageBody);
        context.HandshakeMessagesSent[message.getHandshakeType()] =
            encodedMessage.toBytes();

      case ContentType.content_change_cipher_spec:
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

    final header = RecordLayerHeader(
        contentType: message.getContentType(),
        protocolVersion: ProtocolVersion(0xfe, 0xfd),
        epoch: context.serverEpoch,
        sequenceNumber: context.serverSequenceNumber,
        contentLen: encodedMessage.toBytes().length);

    final encodedHeader = header.marshal();
    List<int> messageToSend = encodedHeader + encodedMessage.toBytes();

    if (context.serverEpoch > 0) {
      // Epoch is greater than zero, we should encrypt it.
      if (context.isCipherSuiteInitialized) {
        print("Message to encrypt: ${messageToSend.sublist(13)}");
        final encryptedMessage = await context.gcm
            .encrypt(header, Uint8List.fromList(messageToSend));
        // if err != nil {
        // 	panic(err)
        // }
        messageToSend = encryptedMessage;
      }
    }

    socket.send(messageToSend, socket.address, port);
    context.increaseServerSequence();
  }

  Future<void> sendMessageDummy(
      HandshakeContext context, dynamic message) async {
    // print("object type: ${message.runtimeType}");
    final Uint8List encodedMessageBody = message.marshal();
    BytesBuilder encodedMessage = BytesBuilder();
    HandshakeHeader handshakeHeader;
    switch (message.getContentType()) {
      case ContentType.content_handshake:
        // print("message type: ${message.getContentType()}");
        handshakeHeader = HandshakeHeader(
            handshakeType: message.getHandshakeType(),
            length: Uint24.fromUInt32(encodedMessageBody.length),
            messageSequence: context.serverHandshakeSequenceNumber,
            fragmentOffset: Uint24.fromUInt32(0),
            fragmentLength: Uint24.fromUInt32(encodedMessageBody.length));
        context.increaseServerHandshakeSequence();
        final encodedHandshakeHeader = handshakeHeader.marshal();
        encodedMessage.add(encodedHandshakeHeader);
        encodedMessage.add(encodedMessageBody);
        context.HandshakeMessagesSent[message.getHandshakeType()] =
            encodedMessage.toBytes();

      case ContentType.content_change_cipher_spec:
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

    final header = RecordLayerHeader(
        contentType: message.getContentType(),
        protocolVersion: ProtocolVersion(254, 253),
        epoch: context.serverEpoch,
        sequenceNumber: context.serverSequenceNumber,
        contentLen: encodedMessage.toBytes().length);

    final encodedHeader = header.marshal();
    List<int> messageToSend = encodedHeader + encodedMessage.toBytes();

    if (context.serverEpoch > 0) {
      // Epoch is greater than zero, we should encrypt it.
      if (context.isCipherSuiteInitialized) {
        print("Message to encrypt: ${messageToSend.sublist(13)}");
        final encryptedMessage = await context.gcm
            .encrypt(header, Uint8List.fromList(messageToSend));
        // if err != nil {
        // 	panic(err)
        // }
        messageToSend = encryptedMessage;
      }
    }

    socket.send(messageToSend, socket.address, port);
  }

  Finished createDtlsFinished(
      HandshakeContext context, Uint8List verifiedData) {
    return Finished(verifiedData);
  }

  generateCurveKeypair(Uint8List curve) {}

  HelloVerifyRequest createDtlsHelloVerifyRequest(HandshakeContext context) {
    HelloVerifyRequest hvr = HelloVerifyRequest(
        version: context.protocolVersion, cookie: generateDtlsCookie());
    return hvr;
  }

  Uint8List generateDtlsCookie() {
    final cookie = Uint8List(20);
    final random = Random.secure();
    for (int i = 0; i < cookie.length; i++) {
      cookie[i] = random.nextInt(256);
    }
    return cookie;
  }

  negotiateOnCurves(curves) {}
  negotiateOnSRTPProtectionProfiles(protectionProfiles) {}

  Future<void> initCipherSuite(HandshakeContext context) async {
    // final preMasterSecret = generatePreMasterSecret(
    //     context.clientKeyExchangePublic, context.serverPrivateKey);

    final preMasterSecret =
        prfPskPreMasterSecret(Uint8List.fromList([0xAB, 0xC1, 0x23]));
    // if err != nil {
    // 	return err
    // }
    print("pre Master secret: ${HEX.encode(preMasterSecret)}");
    // fb34ef080bf9f808b94665cd41ad16761b98653d1b7208ec44fc88b997819f48

    // pre Master secret: fb34ef080bf9f808b94665cd41ad16761b98653d1b7208ec44fc88b997819f48

    final clientRandomBytes = context.clientRandom.raw();
    final serverRandomBytes = context.serverRandom.marshal();

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
      context.serverMasterSecret = generateMasterSecret(
          preMasterSecret, clientRandomBytes, serverRandomBytes);
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

final raw_certificate = Uint8List.fromList([
  0x00,
  0x01,
  0x8c,
  0x00,
  0x01,
  0x89,
  0x30,
  0x82,
  0x01,
  0x85,
  0x30,
  0x82,
  0x01,
  0x2b,
  0x02,
  0x14,
  0x7d,
  0x00,
  0xcf,
  0x07,
  0xfc,
  0xe2,
  0xb6,
  0xb8,
  0x3f,
  0x72,
  0xeb,
  0x11,
  0x36,
  0x1b,
  0xf6,
  0x39,
  0xf1,
  0x3c,
  0x33,
  0x41,
  0x30,
  0x0a,
  0x06,
  0x08,
  0x2a,
  0x86,
  0x48,
  0xce,
  0x3d,
  0x04,
  0x03,
  0x02,
  0x30,
  0x45,
  0x31,
  0x0b,
  0x30,
  0x09,
  0x06,
  0x03,
  0x55,
  0x04,
  0x06,
  0x13,
  0x02,
  0x41,
  0x55,
  0x31,
  0x13,
  0x30,
  0x11,
  0x06,
  0x03,
  0x55,
  0x04,
  0x08,
  0x0c,
  0x0a,
  0x53,
  0x6f,
  0x6d,
  0x65,
  0x2d,
  0x53,
  0x74,
  0x61,
  0x74,
  0x65,
  0x31,
  0x21,
  0x30,
  0x1f,
  0x06,
  0x03,
  0x55,
  0x04,
  0x0a,
  0x0c,
  0x18,
  0x49,
  0x6e,
  0x74,
  0x65,
  0x72,
  0x6e,
  0x65,
  0x74,
  0x20,
  0x57,
  0x69,
  0x64,
  0x67,
  0x69,
  0x74,
  0x73,
  0x20,
  0x50,
  0x74,
  0x79,
  0x20,
  0x4c,
  0x74,
  0x64,
  0x30,
  0x1e,
  0x17,
  0x0d,
  0x31,
  0x38,
  0x31,
  0x30,
  0x32,
  0x35,
  0x30,
  0x38,
  0x35,
  0x31,
  0x31,
  0x32,
  0x5a,
  0x17,
  0x0d,
  0x31,
  0x39,
  0x31,
  0x30,
  0x32,
  0x35,
  0x30,
  0x38,
  0x35,
  0x31,
  0x31,
  0x32,
  0x5a,
  0x30,
  0x45,
  0x31,
  0x0b,
  0x30,
  0x09,
  0x06,
  0x03,
  0x55,
  0x04,
  0x06,
  0x13,
  0x02,
  0x41,
  0x55,
  0x31,
  0x13,
  0x30,
  0x11,
  0x06,
  0x03,
  0x55,
  0x04,
  0x08,
  0x0c,
  0x0a,
  0x53,
  0x6f,
  0x6d,
  0x65,
  0x2d,
  0x53,
  0x74,
  0x61,
  0x74,
  0x65,
  0x31,
  0x21,
  0x30,
  0x1f,
  0x06,
  0x03,
  0x55,
  0x04,
  0x0a,
  0x0c,
  0x18,
  0x49,
  0x6e,
  0x74,
  0x65,
  0x72,
  0x6e,
  0x65,
  0x74,
  0x20,
  0x57,
  0x69,
  0x64,
  0x67,
  0x69,
  0x74,
  0x73,
  0x20,
  0x50,
  0x74,
  0x79,
  0x20,
  0x4c,
  0x74,
  0x64,
  0x30,
  0x59,
  0x30,
  0x13,
  0x06,
  0x07,
  0x2a,
  0x86,
  0x48,
  0xce,
  0x3d,
  0x02,
  0x01,
  0x06,
  0x08,
  0x2a,
  0x86,
  0x48,
  0xce,
  0x3d,
  0x03,
  0x01,
  0x07,
  0x03,
  0x42,
  0x00,
  0x04,
  0xf9,
  0xb1,
  0x62,
  0xd6,
  0x07,
  0xae,
  0xc3,
  0x36,
  0x34,
  0xf5,
  0xa3,
  0x09,
  0x39,
  0x86,
  0xe7,
  0x3b,
  0x59,
  0xf7,
  0x4a,
  0x1d,
  0xf4,
  0x97,
  0x4f,
  0x91,
  0x40,
  0x56,
  0x1b,
  0x3d,
  0x6c,
  0x5a,
  0x38,
  0x10,
  0x15,
  0x58,
  0xf5,
  0xa4,
  0xcc,
  0xdf,
  0xd5,
  0xf5,
  0x4a,
  0x35,
  0x40,
  0x0f,
  0x9f,
  0x54,
  0xb7,
  0xe9,
  0xe2,
  0xae,
  0x63,
  0x83,
  0x6a,
  0x4c,
  0xfc,
  0xc2,
  0x5f,
  0x78,
  0xa0,
  0xbb,
  0x46,
  0x54,
  0xa4,
  0xda,
  0x30,
  0x0a,
  0x06,
  0x08,
  0x2a,
  0x86,
  0x48,
  0xce,
  0x3d,
  0x04,
  0x03,
  0x02,
  0x03,
  0x48,
  0x00,
  0x30,
  0x45,
  0x02,
  0x20,
  0x47,
  0x1a,
  0x5f,
  0x58,
  0x2a,
  0x74,
  0x33,
  0x6d,
  0xed,
  0xac,
  0x37,
  0x21,
  0xfa,
  0x76,
  0x5a,
  0x4d,
  0x78,
  0x68,
  0x1a,
  0xdd,
  0x80,
  0xa4,
  0xd4,
  0xb7,
  0x7f,
  0x7d,
  0x78,
  0xb3,
  0xfb,
  0xf3,
  0x95,
  0xfb,
  0x02,
  0x21,
  0x00,
  0xc0,
  0x73,
  0x30,
  0xda,
  0x2b,
  0xc0,
  0x0c,
  0x9e,
  0xb2,
  0x25,
  0x0d,
  0x46,
  0xb0,
  0xbc,
  0x66,
  0x7f,
  0x71,
  0x66,
  0xbf,
  0x16,
  0xb3,
  0x80,
  0x78,
  0xd0,
  0x0c,
  0xef,
  0xcc,
  0xf5,
  0xc1,
  0x15,
  0x0f,
  0x58,
]);

final serverKeyExchangeData = Uint8List.fromList([
  0x03,
  0x00,
  0x1d,
  0x41,
  0x04,
  0x0c,
  0xb9,
  0xa3,
  0xb9,
  0x90,
  0x71,
  0x35,
  0x4a,
  0x08,
  0x66,
  0xaf,
  0xd6,
  0x88,
  0x58,
  0x29,
  0x69,
  0x98,
  0xf1,
  0x87,
  0x0f,
  0xb5,
  0xa8,
  0xcd,
  0x92,
  0xf6,
  0x2b,
  0x08,
  0x0c,
  0xd4,
  0x16,
  0x5b,
  0xcc,
  0x81,
  0xf2,
  0x58,
  0x91,
  0x8e,
  0x62,
  0xdf,
  0xc1,
  0xec,
  0x72,
  0xe8,
  0x47,
  0x24,
  0x42,
  0x96,
  0xb8,
  0x7b,
  0xee,
  0xe7,
  0x0d,
  0xdc,
  0x44,
  0xec,
  0xf3,
  0x97,
  0x6b,
  0x1b,
  0x45,
  0x28,
  0xac,
  0x3f,
  0x35,
  0x02,
  0x03,
  0x00,
  0x47,
  0x30,
  0x45,
  0x02,
  0x21,
  0x00,
  0xb2,
  0x0b,
  0x22,
  0x95,
  0x3d,
  0x56,
  0x57,
  0x6a,
  0x3f,
  0x85,
  0x30,
  0x6f,
  0x55,
  0xc3,
  0xf4,
  0x24,
  0x1b,
  0x21,
  0x07,
  0xe5,
  0xdf,
  0xba,
  0x24,
  0x02,
  0x68,
  0x95,
  0x1f,
  0x6e,
  0x13,
  0xbd,
  0x9f,
  0xaa,
  0x02,
  0x20,
  0x49,
  0x9c,
  0x9d,
  0xdf,
  0x84,
  0x60,
  0x33,
  0x27,
  0x96,
  0x9e,
  0x58,
  0x6d,
  0x72,
  0x13,
  0xe7,
  0x3a,
  0xe8,
  0xdf,
  0x43,
  0x75,
  0xc7,
  0xb9,
  0x37,
  0x6e,
  0x90,
  0xe5,
  0x3b,
  0x81,
  0xd4,
  0xda,
  0x68,
  0xcd,
]);
