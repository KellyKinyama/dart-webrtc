import 'dart:io';
import 'dart:convert'; // Import for utf8.decoder
import 'package:intl/intl.dart'; // For date formatting

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

// gst-launch-1.0 -v videotestsrc ! vp8enc ! rtpvp8pay ! udpsink host=127.0.0.1 port=5000
  // Construct the GStreamer pipeline command
  // Using vp8enc with cpu-used=0 for fastest encoding.
  final String pipelineCommand = 'gst-launch-1.0 -em '
      'filesrc location="$inputVideoFilePath" ! '
      'uridecodebin name=demux '
      'demux.video_src ! queue ! videoconvert ! vp8enc cpu-used=0 ! rtpvp8pay pt=96 ! udpsink host=$destinationHost port=$videoRtpPort '
      'demux.audio_src ! queue ! audioconvert ! audioresample ! opusenc ! rtpopuspay pt=97 ! udpsink host=$destinationHost port=$audioRtpPort';

  print('Starting GStreamer streaming pipeline:');
  print(pipelineCommand);

  try {
    final Process process;
    if (Platform.isWindows) {
      process = await Process.start('cmd', ['/c', pipelineCommand]);
    } else {
      process = await Process.start('bash', ['-c', pipelineCommand]);
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
  }

  print('\nStreaming finished or encountered an error.');
}
