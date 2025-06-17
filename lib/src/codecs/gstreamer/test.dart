// # IP to listen to
// ip: 127.0.0.1
// # RTP port used for video to listen to
// video_port: 5100
// # RTP port used for audio to listen to
// audio_port: 5200
// # Path where the saved files will be stored
// save_path: ./
// # GStreamer pipeline
// pipeline: gst-launch-1.0 -em udpsrc port={port1} caps=application/x-rtp,media=video,encoding-name=H264,payload=96 timeout=2000000000 ! queue ! rtph264depay ! queue ! h264parse ! queue ! mp4mux name=mux ! queue ! filesink location={path}/{date}.mp4 udpsrc port={port2} caps=application/x-rtp,media=audio,encoding-name=OPUS,payload=96 timeout=2000000000 ! queue ! rtpopusdepay ! queue ! opusparse ! queue ! mux.

gst-launch-1.0 -em udpsrc port=5100 caps="application/x-rtp,media=video,encoding-name=H264,payload=96" timeout=2000000000 ! queue ! rtph264depay ! queue ! h264parse ! queue ! mp4mux name=mux ! queue ! filesink location="./output_recording.mp4" udpsrc port=5200 caps="application/x-rtp,media=audio,encoding-name=OPUS,payload=96" timeout=2000000000 ! queue ! rtpopusdepay ! queue ! opusparse ! queue ! mux.

gst-launch-1.0 -v videotestsrc ! vp8enc ! rtpvp8pay ! udpsink host=127.0.0.1 port=5000