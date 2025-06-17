import 'dart:io';
import 'dart:convert'; // Import for utf8.decoder
import 'package:intl/intl.dart'; // For date formatting

// You'll need to add the intl package to your pubspec.yaml:
// dependencies:
//   intl: ^0.18.0 # Use the latest version

void main() async {
  // --- Configuration ---
  final String inputVideoFilePath =
      "C:/movies/army_of_thieves.mp4"; // <<<<< YOUR PATH
  final String destinationHost = '127.0.0.1'; // IP address of the recipient
  final int videoRtpPort = 5100; // UDP port for video RTP
  final int audioRtpPort = 5200; // UDP port for audio RTP
  // --- End Configuration ---

  // Check if the input video file exists
  if (!await File(inputVideoFilePath).exists()) {
    print('Error: Input video file not found at: $inputVideoFilePath');
    print(
        'Please update `inputVideoFilePath` in the Dart code with the correct path.');
    return;
  }

  // Convert Windows backslashes to forward slashes for GStreamer compatibility
  final String gstreamerCompatiblePath =
      inputVideoFilePath.replaceAll('\\', '/');

  // Construct the *internal* GStreamer pipeline string (without 'gst-launch-1.0 -em')
  // This string will be passed as a single, quoted argument to gst-launch-1.0 via cmd /c
  final String gstreamerPipelineArgsString =
      'filesrc location="$gstreamerCompatiblePath" ! '
      'uridecodebin name=demux '
      'demux.video_src ! queue ! videoconvert ! vp8enc cpu-used=0 ! rtpvp8pay pt=96 ! udpsink host=$destinationHost port=$videoRtpPort '
      'demux.audio_src ! queue ! audioconvert ! audioresample ! opusenc ! rtpopuspay pt=97 ! udpsink host=$destinationHost port=$audioRtpPort';

  // Construct the *full* command that will be executed by cmd /c.
  // The crucial change is enclosing the entire GStreamer pipeline string in double quotes.
  final String fullCmdCommand =
      'gst-launch-1.0 -em "$gstreamerPipelineArgsString"';

  print('Starting GStreamer streaming pipeline:');
  print(fullCmdCommand); // Print the actual command being sent to cmd /c

  try {
    final Process process;
    if (Platform.isWindows) {
      // On Windows, pass the fullCmdCommand as a single argument to cmd /c
      process = await Process.start('cmd', ['/c', fullCmdCommand]);
    } else {
      // On Linux/macOS, 'bash -c' is robust for complex commands
      // For Linux/macOS, the extra quotes in fullCmdCommand are still fine,
      // but you could also go back to the List<String> argument method if preferred.
      process = await Process.start('bash', ['-c', fullCmdCommand]);
    }

    process.stdout.transform(utf8.decoder).listen((data) {
      stdout.write('[GStreamer STDOUT]: $data');
    });

    process.stderr.transform(utf8.decoder).listen((data) {
      stderr.write('[GStreamer STDERR]: $data');
    });

    final exitCode = await process.exitCode;
    print('GStreamer streaming pipeline exited with code: $exitCode');

    if (exitCode != 0) {
      print('GStreamer pipeline failed. Check the error logs above.');
    } else {
      print(
          'GStreamer pipeline finished successfully (file probably reached end).');
    }
  } catch (e) {
    print('Error starting GStreamer pipeline: $e');
    print(
        'Ensure GStreamer is installed and its executable is in your system\'s PATH.');
    print(
        'Also, make sure all necessary plugins (uridecodebin, vp8enc, rtpvp8pay, opusenc, rtpopuspay, etc.) are installed and your input file is valid.');
  }

  print('\nStreaming finished or encountered an error.');
}
