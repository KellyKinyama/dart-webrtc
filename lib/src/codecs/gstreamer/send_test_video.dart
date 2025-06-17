import 'dart:io';
import 'dart:convert'; // Import for utf8.decoder

void main() async {
  // --- Configuration for Sending Test Video ---
  final String destinationHost = '127.0.0.1'; // IP address of the recipient
  final int videoRtpPort =
      5000; // UDP port for video RTP (from the test pipeline)
  // --- End Configuration ---

  // GStreamer pipeline components as a list of strings.
  // Each element, property, or '!' is a separate string in the list.
  final List<String> gstreamerArgs = [
    '-v', // Verbose output
    'videotestsrc', '\!',
    'videoconvert', '\!',
    'vp8enc', 'cpu-used=0', '\!', // VP8 encoder, fastest setting
    'rtpvp8pay', 'pt=96', '\!',
    'udpsink', 'host=$destinationHost', 'port=$videoRtpPort'
  ];

  // For printing the full command (for debugging/info)
  final String pipelineCommandForPrint =
      'gst-launch-1.0 ${gstreamerArgs.join(' ')}';
  print('--- Starting GStreamer Test Video Sender Pipeline ---');
  print('Command: $pipelineCommandForPrint');
  print('Sending test video to $destinationHost:$videoRtpPort');

  Process? senderProcess;

  try {
    // Start the process directly with 'gst-launch-1.0' and the list of arguments.
    // This is the most robust way to avoid shell parsing issues.
    senderProcess = await Process.start('gst-launch-1.0', gstreamerArgs);

    // Listen to stdout
    senderProcess!.stdout.transform(utf8.decoder).listen((data) {
      stdout.write('[GStreamer STDOUT]: $data');
    });

    // Listen to stderr
    senderProcess!.stderr.transform(utf8.decoder).listen((data) {
      stderr.write('[GStreamer STDERR]: $data');
    });

    // Handle process exit (non-blocking)
    senderProcess!.exitCode.then((code) {
      print('[GStreamer Sender]: Pipeline exited with code $code');
      if (code != 0) {
        print('GStreamer sender pipeline failed. Check the error logs above.');
      } else {
        print('GStreamer sender pipeline finished successfully.');
      }
    });

    print('\n--- GStreamer sender started. Press Enter to stop it ---');
    await stdin.first; // Wait for user to press Enter
  } catch (e) {
    print('Error starting GStreamer pipeline: $e');
    print(
        'Ensure GStreamer is installed and its executable is in your system\'s PATH.');
    print(
        'Also, make sure all necessary plugins (videotestsrc, videoconvert, vp8enc, rtpvp8pay, udpsink) are installed.');
  } finally {
    print('\n--- Stopping GStreamer Sender Pipeline ---');
    senderProcess?.kill();
    print('Sender pipeline terminated.');
  }
}
