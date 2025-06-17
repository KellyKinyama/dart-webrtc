import 'dart:io';
import 'dart:convert'; // For utf8.decoder

void main() async {
  // --- Configuration for Receiving ---
  final String listenHost = '127.0.0.1'; // IP address to listen on
  final int videoRtpPort = 5100; // UDP port for video RTP (from sender)
  final int audioRtpPort = 5200; // UDP port for audio RTP (from sender)
  // --- End Configuration ---

  // GStreamer pipeline for receiving VP8 Video
  final String videoReceivePipeline =
      'udpsrc port=$videoRtpPort caps="application/x-rtp,media=video,encoding-name=VP8,payload=96" ! '
      'rtpvp8depay ! vp8dec ! videoconvert ! autovideosink sync=false';

  // GStreamer pipeline for receiving Opus Audio
  final String audioReceivePipeline =
      'udpsrc port=$audioRtpPort caps="application/x-rtp,media=audio,encoding-name=OPUS,payload=97" ! '
      'rtpopusdepay ! opusparse ! opusdec ! audioconvert ! audioresample ! autoaudiosink sync=false';

  Process? videoProcess;
  Process? audioProcess;

  print('--- Starting GStreamer Receiving Pipelines ---');

  try {
    // Start Video Receiver Process
    print('\n[Video]: Starting pipeline: gst-launch-1.0 -v $videoReceivePipeline');
    if (Platform.isWindows) {
      videoProcess = await Process.start('cmd', ['/c', 'gst-launch-1.0 -v "$videoReceivePipeline"']);
    } else {
      videoProcess = await Process.start('bash', ['-c', 'gst-launch-1.0 -v "$videoReceivePipeline"']);
    }
    _listenToProcessOutput(videoProcess!, 'Video');

    // Start Audio Receiver Process
    print('\n[Audio]: Starting pipeline: gst-launch-1.0 -v $audioReceivePipeline');
    if (Platform.isWindows) {
      audioProcess = await Process.start('cmd', ['/c', 'gst-launch-1.0 -v "$audioReceivePipeline"']);
    } else {
      audioProcess = await Process.start('bash', ['-c', 'gst-launch-1.0 -v "$audioReceivePipeline"']);
    }
    _listenToProcessOutput(audioProcess!, 'Audio');

    print('\n--- GStreamer receivers started. Press Enter to stop them ---');
    await stdin.first; // Wait for user to press Enter

  } catch (e) {
    print('Error starting GStreamer pipeline: $e');
    print('Ensure GStreamer is installed and its executable is in your system\'s PATH.');
    print('Also, make sure all necessary plugins (rtpvp8depay, vp8dec, rtpopusdepay, opusparse, opusdec, etc.) are installed.');
  } finally {
    // Ensure processes are killed even if an error occurs or user stops
    print('\n--- Stopping GStreamer Pipelines ---');
    videoProcess?.kill();
    audioProcess?.kill();
    print('Pipelines terminated.');
  }
}

/// Helper function to listen to stdout and stderr of a process
void _listenToProcessOutput(Process process, String prefix) {
  process.stdout.transform(utf8.decoder).listen((data) {
    stdout.write('[$prefix STDOUT]: $data');
  });
  process.stderr.transform(utf8.decoder).listen((data) {
    stderr.write('[$prefix STDERR]: $data');
  });

  // Also listen for the process exit code
  process.exitCode.then((code) {
    print('[$prefix]: Pipeline exited with code $code');
  });
}