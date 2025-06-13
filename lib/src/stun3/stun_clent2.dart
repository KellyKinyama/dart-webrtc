// --- Main Function to Run the Client ---
import 'dart:io';

import 'stun_client.dart';

Future<void> main(List<String> arguments) async {
  // Google's public STUN server address and port
  // Note: Public STUN servers usually don't require authentication (username/password/ufrag)
  // for basic binding requests.
  final serverHost =
      InternetAddress.lookup('stun.l.google.com').then((list) => list.first);
  final serverPort = 19302; // Standard STUN port

  // These credentials are often not needed for public STUN servers.
  // Set them to empty strings to indicate they are not used.
  String clientUfrag = ""; // Not typically sent to public STUN servers
  String serverUfrag = ""; // Not typically sent to public STUN servers
  String serverPassword = ""; // Not typically used with public STUN servers

  // You can still override these with command-line arguments if needed for a specific server
  // if (arguments.length > 0) {
  //   // Note: If you provide an argument, it will override the google.com lookup.
  //   // For this example, if you provide an argument, it's assumed to be an IP or hostname.
  //   // For simplicity, we'll just parse the first argument as a hostname if provided.
  //   // For a robust solution, you'd handle `InternetAddress.lookup` with arguments better.
  //   serverHost = InternetAddress.lookup(arguments[0]).then((list) => list.first);
  // }
  // if (arguments.length > 1) serverPort = int.tryParse(arguments[1]) ?? 19302;
  // if (arguments.length > 2) clientUfrag = arguments[2];
  // if (arguments.length > 3) serverUfrag = arguments[3];
  // if (arguments.length > 4) serverPassword = arguments[4];

  print('STUN Client configuration:');
  print('  Server: ${(await serverHost).host}:${serverPort}');
  print('  Client Ufrag: ${clientUfrag.isEmpty ? "N/A" : clientUfrag}');
  print('  Server Ufrag: ${serverUfrag.isEmpty ? "N/A" : serverUfrag}');
  print(
      '  Server Password: ${serverPassword.isEmpty ? "N/A" : "Provided (for integrity check)"}');

  final client = StunClient(
    await serverHost, // Await the Future<InternetAddress>
    serverPort,
    clientUfrag: clientUfrag,
    serverUfrag: serverUfrag,
    serverPassword: serverPassword,
  );

  await client.sendBindingRequest();

  // The client will automatically close the socket after receiving a response or timing out.
  // No need for explicit stop() call here for this simple use case.
}
