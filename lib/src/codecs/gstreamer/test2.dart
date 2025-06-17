import 'dart:io';
import 'dart:convert'; // Import for utf8.decoder
import 'package:intl/intl.dart'; // For date formatting

// You'll need to add the intl package to your pubspec.yaml:
// dependencies:
//   intl: ^0.18.0 # Use the latest version

void main() async {
  final String ip = '127.0.0.1';
  final int videoPort = 5100;
  final int audioPort = 5200;
  final String savePath = './'; // Current directory

  // Generate a timestamp for the filename
  final String date = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final String outputFileName = '${savePath}recording_${date}.mp4';

  // Construct the GStreamer pipeline command
  // Ensure the caps string is correctly quoted for the shell
  final String pipelineCommand = 'gst-launch-1.0 -em udpsrc port=$videoPort '
      'caps="application/x-rtp,media=video,encoding-name=H264,payload=96" '
      'timeout=2000000000 ! queue ! rtph264depay ! queue ! h264parse ! queue ! mp4mux name=mux ! queue ! filesink location="$outputFileName" '
      'udpsrc port=$audioPort '
      'caps="application/x-rtp,media=audio,encoding-name=OPUS,payload=96" '
      'timeout=2000000000 ! queue ! rtpopusdepay ! queue ! opusparse ! queue ! mux.';

  print('Starting GStreamer pipeline:');
  print(pipelineCommand);

  try {
    // Start the process
    // On Windows, you might need to explicitly run through 'cmd /c'
    // For cross-platform, it's generally best to try directly first,
    // and if it fails on Windows, prepend 'cmd', '/c', or 'powershell', '-Command'
    final Process process;
    if (Platform.isWindows) {
      process = await Process.start('cmd', ['/c', pipelineCommand]);
    } else {
      // For Linux/macOS, 'bash -c' is robust for complex commands
      process = await Process.start('bash', ['-c', pipelineCommand]);
    }

    // Listen to stdout
    process.stdout.transform(utf8.decoder).listen((data) {
      stdout.write('[GStreamer STDOUT]: $data');
    });

    // Listen to stderr (GStreamer often prints verbose info and errors here)
    process.stderr.transform(utf8.decoder).listen((data) {
      stderr.write('[GStreamer STDERR]: $data');
    });

    // Handle process exit
    final exitCode = await process.exitCode;
    print('GStreamer pipeline exited with code: $exitCode');

    if (exitCode != 0) {
      print('GStreamer pipeline failed. Check the error logs above.');
    } else {
      print('GStreamer pipeline finished successfully.');
    }
  } catch (e) {
    print('Error starting GStreamer pipeline: $e');
  }

  print(
      '\nTo stop the pipeline, you might need to terminate the Dart process or send a signal (e.g., Ctrl+C).');
  print('The recorded file will be: $outputFileName');
}
