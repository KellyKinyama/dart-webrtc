import 'dart:io';
// import 'dart:typed_data';

// import 'package:dart_tls/ch09/handshake/handshake_context.dart';
// import 'package:dart_tls/ch09/handshaker/psk_aes_128_ccm.dart';
import '../../handshaker/aes_gcm_128_sha_256.dart';
import '../../tests/verify_ecdsa_256_cert1.dart';
// import 'package:dart_tls/dart_tls.dart' as dart_tls;

HandshakeManager? handshakeManager;

void handleDtls(
    Datagram d, RawDatagramSocket socket, EcdsaCert serverEcCertificate) {
  if (handshakeManager == null) {
    handshakeManager = HandshakeManager(socket, serverEcCertificate);

    handshakeManager!.port = d.port;
  }
  print("recieved data: ${d.data}");
  // HandshakeContext context = HandshakeContext();
  // final dtlsMsg =
  //     DecodeDtlsMessageResult.decode(context, d.data, 0, d.data.length);

  handshakeManager!.processDtlsMessage(d.data);
  //print("DTLS msg: $dtlsMsg");
}
