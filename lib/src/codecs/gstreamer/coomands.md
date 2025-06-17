1. Microphone to Local Speaker (Loopback/Monitor your mic)
This pipeline captures audio from your microphone and plays it directly out of your speakers.

GStreamer Pipeline (Example for Windows with wasapisrc):

Bash

gst-launch-1.0 -v wasapisrc ! audioconvert ! wasapisink
GStreamer Pipeline (Example for Linux with pulsesrc):

Bash

gst-launch-1.0 -v pulsesrc ! audioconvert ! pulsesink
GStreamer Pipeline (Cross-Platform using autoaudiosrc/autoaudiosink):

Bash

gst-launch-1.0 -v autoaudiosrc ! audioconvert ! autoaudiosink

2. Microphone to RTP (Streaming your mic audio)
This pipeline captures audio from your microphone, encodes it with Opus, packetizes it into RTP, and sends it to a UDP port.

GStreamer Pipeline (Example for Windows with wasapisrc):

Bash

gst-launch-1.0 -v wasapisrc ! audioconvert ! audioresample ! opusenc ! rtpopuspay pt=97 ! udpsink host=127.0.0.1 port=5004
GStreamer Pipeline (Cross-Platform with autoaudiosrc):

Bash

gst-launch-1.0 -v autoaudiosrc ! audioconvert ! audioresample ! opusenc ! rtpopuspay pt=97 ! udpsink host=127.0.0.1 port=5004
Dart Sender Code (Microphone to RTP):