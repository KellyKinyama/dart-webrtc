import 'dart:io';
import 'dart:typed_data';

import 'package:dartls/src/tls/handshake/client_hello.dart';
import 'package:dartls/src/tls/handshake/handshake_header.dart';
import 'package:dartls/src/tls/handshake/server_hello.dart';
import 'package:dartls/src/tls/protocol_version.dart';
import 'package:dartls/src/tls/tls_message.dart';

import '../../../types/types.dart';
import '../enums.dart';
import '../handshake/application_data.dart';
import '../handshake/certificate.dart';
import '../handshake/certificate_verify.dart';
import '../handshake/change_cipher_spec.dart';
import '../handshake/client_key_exchange.dart';
import '../handshake/finished.dart';
import '../handshake/hello_verify_request.dart';
import '../handshake/server_hello_done.dart';
import '../handshake/server_key_exchange.dart';
import '../handshake_context.dart';
import '../record_layer.dart';
import '../tls_random.dart';

class HandshakeManager {
  Socket socket;
  HandshakeContext context;

  HandshakeManager(this.context, this.socket);

  processTlsMessage(Uint8List data) async {
    final tlsMessage = TlsMessage.unmarshal(data, 0, data.length);
    await processIncomingMessage(context, tlsMessage.message);
  }

  Future<bool?> processIncomingMessage(
      HandshakeContext context, TlsMessage incomingMessage) async {
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

        context.session_id = Uint8List.fromList(message.sessionId);
        context.compression_methods = message.compressionMethods;
        context.extensions = message.extensions;
        // context.extensionsData = message.extensionsData!;

        switch (context.flight) {
          case Flight.Flight0:
            context.tlsState = TLSState.TLSStateConnecting;
            context.protocolVersion = message.protocolVersion;
            context.cookie = generateDtlsCookie();
            // logging.Descf(logging.ProtoDTLS, "DTLS Cookie was generated and set to <u>0x%x</u> in handshake context (<u>%d bytes</u>).", context.Cookie, len(context.Cookie))
            context.clientRandom = message.tlsRandom;
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
            final certificateResponse = createDtlsCertificate();
            await sendMessage(context, certificateResponse);
            final serverKeyExchangeResponse =
                createDtlsServerKeyExchange(context);
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


  Future<void> sendMessage(HandshakeContext context, dynamic message) async {
    // print("object type: ${message.runtimeType}");
    final Uint8List encodedMessageBody = message.marshal();
    BytesBuilder encodedMessage = BytesBuilder();
    HandshakeHeader handshakeHeader;
    switch (message.getContentType()) {
      case TlsContentType.content_handshake:
        // print("message type: ${message.getContentType()}");
        handshakeHeader = HandshakeHeader(
            message.getHandshakeType(), Uint24(encodedMessageBody.length));
        context.increaseServerHandshakeSequence();
        final encodedHandshakeHeader = handshakeHeader.marshal();
        encodedMessage.add(encodedHandshakeHeader);
        encodedMessage.add(encodedMessageBody);
        context.handshakeMessagesSent[message.getHandshakeType()] =
            encodedMessage.toBytes();

      case TlsContentType.content_change_cipher_spec:
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

    final header = RecordLayer(
        message.getContentType(),
        ProtocolVersion(Uint8(3), Uint8(1)),
        Uint16(encodedMessage.toBytes().length));

    final encodedHeader = header.marshal();
    List<int> messageToSend = encodedHeader + encodedMessage.toBytes();

    // if (context.serverEpoch > 0) {
    //   // Epoch is greater than zero, we should encrypt it.
    //   if (context.isCipherSuiteInitialized) {
    //     print("Message to encrypt: ${messageToSend.sublist(13)}");
    //     final encryptedMessage = await context.gcm
    //         .encrypt(header, Uint8List.fromList(messageToSend));
    //     // if err != nil {
    //     // 	panic(err)
    //     // }
    //     messageToSend = encryptedMessage;
    //   }
    // }

    socket.add(messageToSend);
    context.increaseServerSequence();
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
        context.protocolVersion,
        context.serverRandom,
        context.session_id.length,
        context.session_id,
        CipherSuiteId.Tls_Ecdhe_Ecdsa_With_Aes_128_Gcm_Sha256.value,
        context.compression_methods[0],
        context.extensions,
        extensionsData: context.extensionsData);
  }

  Certificate createDtlsCertificate() {
    // return Certificate.unmarshal(raw_certificate);
    // raw_c
    return Certificate(certificate: [
      Uint8List.fromList(pemToBytes(generateKeysAndCertificate()))
    ]);
  }
ServerHelloDone createDtlsServerHelloDone(HandshakeContext context) {
    return ServerHelloDone();
  }
ChangeCipherSpec createDtlsChangeCipherSpec(HandshakeContext context) {
    return ChangeCipherSpec();
  }
  Finished createDtlsFinished(
      HandshakeContext context, Uint8List verifiedData) {
    return Finished(verifiedData);
  }

   ServerKeyExchange createDtlsServerKeyExchange(HandshakeContext context) {
    // return ServerKeyExchange.unmarshal(serverKeyExchangeData);

    return ServerKeyExchange(
        identityHint: [],
        ellipticCurveType: EllipticCurveType.NamedCurve,
        namedCurve: NamedCurve.prime256v1,
        publicKey: context.serverPublicKey,
        signatureHashAlgorithm: SignatureHashAlgorithm(
            hash: HashAlgorithm.Sha256,
            signatureAgorithm: SignatureAlgorithm.Ecdsa),
        signature: context.serverKeySignature);
  }
  HelloVerifyRequest createDtlsHelloVerifyRequest(HandshakeContext context) {
    HelloVerifyRequest hvr = HelloVerifyRequest(
        version: context.protocolVersion, cookie: generateDtlsCookie());
    return hvr;
  }
}
