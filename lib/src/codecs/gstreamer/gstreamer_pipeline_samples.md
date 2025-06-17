# Gstreamer Pipeline Samples

Table of Contents:

- [Gstreamer Pipeline Samples](#gstreamer-pipeline-samples)
  - [Tips for Debug](#tips-for-debug)
  - [Video](#video)
    - [display test video](#display-test-video)
    - [record to file](#record-to-file)
    - [record and display at the same time(queue)](#record-and-display-at-the-same-timequeue)
    - [record webcam to `*.mp4`(jetson nano)](#record-webcam-to-mp4jetson-nano)
    - [fps test](#fps-test)
  - [Audio](#audio)
  - [Mux Video and Audio](#mux-video-and-audio)
  - [Media File](#media-file)
    - [Play Media File](#play-media-file)
    - [Transcode Media File](#transcode-media-file)
  - [Network streaming](#network-streaming)
    - [Video RTP Streaming](#video-rtp-streaming)
      - [send a test video with h264 rtp stream](#send-a-test-video-with-h264-rtp-stream)
      - [send a screen capture with h264 rtp stream(linux)](#send-a-screen-capture-with-h264-rtp-streamlinux)
      - [send a screen capture with h264 rtp stream(osx)](#send-a-screen-capture-with-h264-rtp-streamosx)
      - [send a `*.mp4` file with h264 rtp stream](#send-a-mp4-file-with-h264-rtp-stream)
      - [send a webcam with h264 rtp stream(jetson nano)](#send-a-webcam-with-h264-rtp-streamjetson-nano)
      - [send a webcam with h264 rtp stream while record (jetson nano)](#send-a-webcam-with-h264-rtp-stream-while-record-jetson-nano)
      - [receive h264 rtp stream(desktop host)](#receive-h264-rtp-streamdesktop-host)
    - [Audio RTP Streaming](#audio-rtp-streaming)
      - [raw audio](#raw-audio)
      - [encoded/decoded audio](#encodeddecoded-audio)
    - [Audio + Video RTP Streaming](#audio--video-rtp-streaming)
    - [Media File RTP Streaming](#media-file-rtp-streaming)
      - [demux and split video and audio(not best)](#demux-and-split-video-and-audionot-best)
      - [remux to MPEGST(best)](#remux-to-mpegstbest)
        - [mpegts sender](#mpegts-sender)
        - [mpegts receiver](#mpegts-receiver)
    - [RTSP Server](#rtsp-server)
      - [install server(jetson nano)](#install-serverjetson-nano)
      - [stream web-cam(jetson nano)](#stream-web-camjetson-nano)
      - [stream media file(\*.mp4)](#stream-media-filemp4)
    - [RTSP Server via MediaMTX](#rtsp-server-via-mediamtx)
    - [Serving MPEG-TS `.ts` file by HTTP](#serving-mpeg-ts-ts-file-by-http)
      - [Create a single `ts` streaming file](#create-a-single-ts-streaming-file)
      - [Run a simple web server](#run-a-simple-web-server)
      - [Client to play `.ts` files](#client-to-play-ts-files)
    - [HLS](#hls)
      - [Creating segemented **.ts** files and a **.m3u8** playlist](#creating-segemented-ts-files-and-a-m3u8-playlist)
      - [Runing a web server for serving HLS](#runing-a-web-server-for-serving-hls)
      - [Client to play HLS stream](#client-to-play-hls-stream)
    - [RTMP Server](#rtmp-server)
      - [Set up a RTMP server](#set-up-a-rtmp-server)
      - [Send a live stream to a RTMP server](#send-a-live-stream-to-a-rtmp-server)
      - [Receiver a live stream](#receiver-a-live-stream)
  - [Mixing](#mixing)
    - [Mixing videos](#mixing-videos)
    - [Mixing video+audio](#mixing-videoaudio)
  - [SHM(Shared Memory)](#shmshared-memory)
    - [raw video](#raw-video)
    - [h264 encode/decode](#h264-encodedecode)
  - [Fallbacksrc](#fallbacksrc)
  - [Live Stream, Format, Codec Comparison](#live-stream-format-codec-comparison)
  - [python-opencv](#python-opencv)


Get great help from below references:

- [Stream H.264 video over rtp using gstreamer](https://stackoverflow.com/questions/17313985/stream-h-264-video-over-rtp-using-gstreamer)

- [Implementing GStreamer Webcam(USB & Internal) Streaming[Mac & C++ & CLion]](https://medium.com/lifesjourneythroughalens/implementing-gstreamer-webcam-usb-internal-streaming-mac-c-clion-76de0fdb8b34)

- [GStreamer command-line cheat sheet](https://github.com/matthew1000/gstreamer-cheat-sheet)

- [Example GStreamer Pipelines](http://labs.isee.biz/index.php/Example_GStreamer_Pipelines#Decode_Audio_Files)

- [Gstreamer real life examples](http://4youngpadawans.com/gstreamer-real-life-examples/)

## Tips for Debug

- Set general debug level

  ```sh
  export GST_DEBUG=6 #5
  export GST_DEBUG=GST_REGISTRY:6,GST_PLUGIN:6
  ```

- Discover video file

  ```sh
  gst-discoverer-1.0 -v fat_bunny.ogg 
  ```

- Inspect plugin

  ```sh
  gst-inspect-1.0 avdec_h264
  ```

- Visualize a pipeline graph

**Graphviz** needs to be installed to convert those GStreamer generated `.dot` files into PDF and image file.

`GST_DEBUG_DUMP_DOT_DIR` environment variable must be defined firstly before creating the graph,
```sh
mkdir -p /tmp/pipeline
export GST_DEBUG_DUMP_DOT_DIR=/tmp/pipeline
```

Then run the pipeline,
```sh
gst-launch-1.0 playbin3 uri=http://$HOST:8080/live.m3u8
```

Five state change `.dot` files are created
```sh
❯ ls /tmp/pipeline
0.00.00.016386417-gst-launch.NULL_READY.dot
0.00.00.319950042-gst-launch.READY_PAUSED.dot
0.00.00.322555584-gst-launch.PAUSED_PLAYING.dot
0.00.07.145014292-gst-launch.PLAYING_PAUSED.dot
0.00.07.214058584-gst-launch.PAUSED_READY.dot
```

Finally convert these `.dot` files into PDF or image files,
```sh
# convert to PNG
dot -Tpng /tmp/pipeline/*.READY_PAUSED.dot -o ~/Desktop/pipeline-graph.png
# convert to PDF
dot -Tpdf /tmp/pipeline/*.READY_PAUSED.dot -o ~/Desktop/pipeline-graph.pdf
```

## Video

### display test video

```sh
gst-launch-1.0 -vvv videotestsrc ! autovideosink
gst-launch-1.0 -vvv videotestsrc ! 'video/x-raw,width=1280,height=720,format=RGB,framerate=60/1' ! fpsdisplaysink
gst-launch-1.0 -vvv videotestsrc ! videoconvert ! fpsdisplaysink text-overlay=false
```

### record to file

```sh
gst-launch-1.0 -vv videotestsrc ! x264enc ! flvmux ! filesink location=xyz.flv

gst-launch-1.0 -vv videotestsrc ! x264enc ! qtmux ! filesink location=xyz.mp4 -e
```

### record and display at the same time(queue)

[GStreamer Recording and Viewing Stream Simultaneously](https://stackoverflow.com/questions/37444615/gstreamer-recording-and-viewing-stream-simultaneously)

```sh
gst-launch-1.0 -vvv videotestsrc \
! tee name=t \
t. ! queue ! x264enc ! mp4mux ! filesink location=xyz.mp4 -e \
t. ! queue leaky=1 ! autovideosink sync=false
```

**tips:**

1. `-e (EOS signal)`: Pipelines for file saving require a reliable EOS(End of Stream) signal
2. `queue leaky=1 ! autovideosink sync=false`: prevent blocking
3. `drop=true`: drop frame if cannot read quickly enough

### record webcam to `*.mp4`(jetson nano)

```sh
gst-launch-1.0 nvarguscamerasrc ! fakesink

gst-launch-1.0 nvarguscamerasrc num-buffers=2000 ! 'video/x-raw(memory:NVMM),width=1920, height=1080, framerate=30/1, format=NV12' ! omxh264enc ! qtmux ! filesink location=test.mp4 -e

gst-launch-1.0 nvarguscamerasrc num-buffers=2000 ! 'video/x-raw(memory:NVMM),width=1920, height=1080, framerate=30/1, format=NV12' ! nvvidconv ! x264enc ! qtmux ! filesink location=test.mp4 -e
```

### fps test

```sh
gst-launch-1.0 -v videotestsrc ! videorate ! video/x-raw,framerate=30/1 ! videoconvert ! autovideosink

gst-launch-1.0 -v videotestsrc ! videorate ! video/x-raw,framerate=30/1 ! x264enc tune=zerolatency bitrate=16000000 speed-preset=superfast ! rtph264pay ! udpsink port=5000 host=$HOST

gst-launch-1.0 -v videotestsrc ! videorate ! video/x-raw,framerate=60/1 ! x264enc tune=zerolatency bitrate=16000000 speed-preset=superfast ! h264parse ! rtph264pay ! udpsink port=5000 host=$HOST

gst-launch-1.0 -v videotestsrc ! video/x-raw,framerate=30/1 ! videorate ! video/x-raw,framerate=60/1 ! x264enc tune=zerolatency bitrate=16000000 speed-preset=superfast ! rtph264pay ! udpsink port=5000 host=$HOST
```

## Audio

```sh
gst-launch-1.0 audiotestsrc ! autoaudiosink

# This creates a higher beep:
gst-launch-1.0 audiotestsrc freq=1000 ! autoaudiosink

# volume
gst-launch-1.0 audiotestsrc volume=0.1 ! autoaudiosink

# White noise
gst-launch-1.0 audiotestsrc wave="white-noise" ! autoaudiosink

# Silence
gst-launch-1.0 audiotestsrc wave="silence" ! autoaudiosink
```

## Mux Video and Audio

```sh
gst-launch-1.0 -v audiotestsrc ! autoaudiosink videotestsrc ! autovideosink

# save to `*.mp4` file
gst-launch-1.0 -v -e videotestsrc \
  ! x264enc \
  ! mp4mux name=mux \
  ! filesink location="bla.mp4" \
  audiotestsrc ! lamemp3enc ! mux.

```

videotestsrc --> x264enc -----\
                               >---> mp4mux ---> filesink
audiotestsrc --> lamemp3enc --/

## Media File

```sh
# information of file
gst-discoverer-1.0 -v /home/jetson/Videos/why_I_left_China_for_Good.mp4
```

### Play Media File

```sh
# play `mp4` file with audio
gst-launch-1.0 filesrc location=/Users/siyao/Movies/why_I_left_China_for_Good.mp4 \
  ! qtdemux name=demux  demux.audio_0 \
  ! decodebin ! audioconvert ! audioresample ! autoaudiosink

# play `mp4` file with video
gst-launch-1.0 filesrc location=/Users/siyao/Movies/why_I_left_China_for_Good.mp4 \
  ! qtdemux \
  ! decodebin ! videoconvert ! videoscale ! autovideosink

# play `mkv` file with video
gst-launch-1.0 -v filesrc location=/Users/siyao/Movies/jellyfish-10-mbps-hd-h264.mkv \
  ! matroskademux name=demux  demux.video_0\
  ! decodebin \
  ! videoconvert \
  ! autovideosink

# play `mp4` file with both audio and video
gst-launch-1.0 filesrc location=/Users/siyao/Movies/why_I_left_China_for_Good.mp4 \
  ! qtdemux name=demux  demux.audio_0 \
  ! queue ! decodebin ! audioconvert ! audioresample ! autoaudiosink  demux.video_0 \
  ! queue ! decodebin ! videoconvert ! videoscale ! autovideosink

```

### Transcode Media File

```sh
# `mkv` to `mp4` with video
gst-launch-1.0 -v filesrc location=/home/jetson/Videos/jellyfish-10-mbps-hd-h264.mkv \
  ! matroskademux \
  ! h264parse \
  ! mp4mux \
  ! filesink location=jellyfish.mp4

# `mp4` to `mkv` with video
gst-launch-1.0 -v filesrc location=/Users/siyao/Movies/why_I_left_China_for_Good.mp4 \
  ! qtdemux name=demux matroskamux name=mux \
  ! filesink location=fat_bunny.mkv  demux.video_0 \
  ! queue ! h264parse ! mux.

# `mp4` to `mkv` with audio
gst-launch-1.0 -v filesrc location=/Users/siyao/Movies/why_I_left_China_for_Good.mp4 \
  ! qtdemux name=demux matroskamux name=mux \
  ! filesink location=fat_bunny.mka  demux.audio_0 \
  ! queue ! decodebin ! audioconvert ! vorbisenc ! mux.

# `mp4`to `mkv` with both audio and video
gst-launch-1.0 -v filesrc location=/Users/siyao/Movies/why_I_left_China_for_Good.mp4 \
  ! qtdemux name=demux matroskamux name=mux \
  ! filesink location=fat_bunny.mkv  demux.audio_0 \
  ! queue ! decodebin ! audioconvert ! audioresample ! vorbisenc ! mux.  demux.video_0 \
  ! queue ! h264parse ! mux.

```

## Network streaming

HOST=192.168.31.175 [//]: # (destination receiving the stream)

### Video RTP Streaming

- sender

#### send a test video with h264 rtp stream

```sh
gst-launch-1.0 -v videotestsrc ! x264enc tune=zerolatency bitrate=500 speed-preset=superfast ! rtph264pay ! udpsink port=5000 host=$HOST

gst-launch-1.0 -v videotestsrc pattern=snow ! "video/x-raw,format=I420,width=1920,height=1080,framerate=60/1" ! x264enc tune=zerolatency bitrate=500 speed-preset=superfast ! rtph264pay ! udpsink port=5000 host=$HOST

# grayscale
gst-launch-1.0 -v videotestsrc ! videobalance saturation=0 ! x264enc ! video/x-h264, stream-format=byte-stream ! rtph264pay ! udpsink host=$HOST port=5000

# control fps
gst-launch-1.0 -v videotestsrc ! videorate ! "video/x-raw,framerate=60/1" ! x264enc tune=zerolatency bitrate=16000000 speed-preset=superfast ! h264parse ! rtph264pay pt=96 ! udpsink port=5000 host=$HOST

gst-launch-1.0 -v videotestsrc ! videorate ! "video/x-raw,framerate=60/1" ! omxh264enc insert-sps-pps=true bitrate=16000000 ! h264parse ! rtph264pay pt=96 ! udpsink port=5000 host=$HOST

gst-launch-1.0 -v videotestsrc ! videorate ! "video/x-raw,width=1280,height=720,framerate=60/1" ! omxh264enc insert-sps-pps=true bitrate=16000000 ! h264parse ! rtph264pay pt=96 ! udpsink port=5000 host=$HOST

```

#### send a screen capture with h264 rtp stream(linux)

```sh
gst-launch-1.0 -v ximagesrc ! video/x-raw,framerate=20/1 ! videoscale ! videoconvert ! x264enc tune=zerolatency bitrate=500 speed-preset=superfast ! rtph264pay ! udpsink host=127.0.0.1 port=5000
```

#### send a screen capture with h264 rtp stream(osx)

```sh
gst-launch-1.0 -v avfvideosrc capture-screen=true ! video/x-raw,framerate=20/1 ! videoscale ! videoconvert ! x264enc tune=zerolatency bitrate=500 speed-preset=superfast ! rtph264pay ! udpsink host=127.0.0.1 port=5000
```

#### send a `*.mp4` file with h264 rtp stream

```sh
gst-launch-1.0 -v filesrc location=test.mp4 ! qtdemux ! h264parse ! omxh264dec ! x264enc ! rtph264pay ! udpsink host=$HOST port=5000

gst-launch-1.0 -v filesrc location=test.mp4 ! qtdemux ! h264parse ! omxh264dec ! omxh264enc insert-sps-pps=true ! rtph264pay ! udpsink host=$HOST port=5000

gst-launch-1.0 -v filesrc location=test.mp4 ! qtdemux ! h264parse ! rtph264pay ! udpsink host=$HOST port=5000
```

#### send a webcam with h264 rtp stream(jetson nano)

```sh
!!slow
gst-launch-1.0 nvarguscamerasrc ! 'video/x-raw(memory:NVMM),width=1280, height=720, framerate=60/1, format=NV12' ! nvvidconv ! x264enc bitrate=16000000 speed-preset=superfast ! rtph264pay ! udpsink port=5000 host=$HOST

!!fast
gst-launch-1.0 nvarguscamerasrc ! 'video/x-raw(memory:NVMM),width=1920, height=1080, framerate=30/1, format=NV12' ! nvvidconv flip-method=2 ! nvv4l2h264enc insert-sps-pps=true bitrate=16000000 ! rtph264pay ! udpsink port=5000 host=$HOST

gst-launch-1.0 nvarguscamerasrc ! 'video/x-raw(memory:NVMM),width=1920, height=1080, framerate=30/1, format=NV12' ! omxh264enc insert-sps-pps=true bitrate=16000000 ! rtph264pay ! udpsink port=5000 host=$HOST

# avoid receiver using sync=false

```

#### send a webcam with h264 rtp stream while record (jetson nano)

```sh
gst-launch-1.0 nvarguscamerasrc sensor-id=0 ! 'video/x-raw(memory:NVMM),width=1920, height=1080, framerate=30/1, format=NV12' ! nvvidconv flip-method=2 ! omxh264enc insert-sps-pps=true bitrate=16000000 \
    ! tee name=t \
    t. ! queue ! rtph264pay ! udpsink port=5000 host=$OSX_HOST \
    t. ! queue ! qtmux ! filesink location=test.mp4 -e
```

- receiver

#### receive h264 rtp stream(desktop host)

```sh
# display
gst-launch-1.0 -v udpsrc port=5000 ! "application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)H264, payload=(int)96" ! rtph264depay ! h264parse ! decodebin ! videoconvert ! autovideosink sync=false

gst-launch-1.0 -v udpsrc port=5000 ! "application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)H264, payload=(int)96" ! rtph264depay ! h264parse ! avdec_h264 ! videoconvert ! autovideosink

# fps
gst-launch-1.0 -v udpsrc port=5000 ! "application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)H264, payload=(int)96" ! rtph264depay ! h264parse ! decodebin ! videoconvert ! fpsdisplaysink text-overlay=false sync=false

# record and display
gst-launch-1.0 -v udpsrc port=5000 ! "application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)H264, payload=(int)96" \
! rtph264depay ! h264parse \
! tee name=t \
t. ! queue ! mp4mux ! filesink location=xyz.mp4 -e \
t. ! queue leaky=1 ! decodebin ! videoconvert ! autovideosink sync=false

```

> **tips**:
>
> 1. `sync=false`: remove dropped frame rate, lag and error message(`There may be a timestamping problem, or this computer is too slow`). see the [Streaming RTP/RTSP: sync/timestamp problems](https://stackoverflow.com/questions/11397655/streaming-rtp-rtsp-sync-timestamp-problems) for details.
> 2. `udpsrc port=5000 cap='application/x-rtp'`: will set the remaining properties to default.

### Audio RTP Streaming

#### raw audio

```sh
# sender
gst-launch-1.0 audiotestsrc \
  ! audioconvert \
  ! audioresample \
  ! rtpL24pay \
  ! udpsink host=$HOST port=5001

# receiver
gst-launch-1.0 -v udpsrc port=5001 \
  ! 'application/x-rtp,media=audio,payload=96,clock-rate=44100,encoding-name=L24' \
  ! rtpL24depay \
  ! audioconvert \
  ! autoaudiosink sync=false
```

#### encoded/decoded audio

```sh
# sender
gst-launch-1.0 audiotestsrc \
  ! audioconvert \
  ! audioresample \
  ! alawenc \
  ! rtppcmapay \
  ! udpsink host=$HOST port=5001

# receiver
gst-launch-1.0 -v udpsrc port=5001 \
  ! 'application/x-rtp,media=audio,payload=8,clock-rate=8000,encoding-name=PCMA'  \
  ! rtppcmadepay \
  ! alawdec \
  ! audioconvert \
  ! autoaudiosink sync=false
```

### Audio + Video RTP Streaming

```sh
# sender
gst-launch-1.0 -v videotestsrc \
  ! 'video/x-raw,format=I420,width=1920,height=1080,framerate=60/1' \
  ! omxh264enc insert-sps-pps=true bitrate=16000000 \
  ! h264parse \
  ! rtph264pay pt=96 \
  ! udpsink port=5000 host=$HOST audiotestsrc \
  ! audioconvert \
  ! audioresample \
  ! rtpL24pay \
  ! udpsink host=$HOST port=5001


# receiver
gst-launch-1.0 -v udpsrc port=5000 \
  ! 'application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)H264, payload=(int)96' \
  ! rtph264depay \
  ! h264parse \
  ! decodebin \
  ! videoconvert \
  ! fpsdisplaysink text-overlay=false sync=false \
  udpsrc port=5001 \
  ! "application/x-rtp,channels=1,media=audio,payload=96,clock-rate=44100,encoding-name=L24" \
  ! rtpL24depay \
  ! audioconvert \
  ! autoaudiosink sync=false

#TODO: SDP file
v=0
c=IN IP4 <Receiver IP>
m=video 5000 RTP/AVP 96
a=recvonly
a=rtpmap:96 H264/90000
m=audio 5001 RTP/AVP 8
a=recvonly
a=rtpmap:8 PCMA/8000/1
```

### Media File RTP Streaming

#### demux and split video and audio(not best)

```sh
# sender `mp4` file
gst-launch-1.0 -v filesrc location=/home/jetson/Videos/why_I_left_China_for_Good.mp4 \
  ! qtdemux name=demux  \
  demux.video_0 ! queue ! h264parse ! decodebin ! omxh264enc insert-sps-pps=true bitrate=16000000 ! rtph264pay pt=96 ! udpsink host=$HOST port=5000  \
  demux.audio_0 ! queue ! decodebin ! audioconvert ! audioresample ! avenc_ac3 ! rtpac3pay ! udpsink host=$HOST port=5001

# receiver
gst-launch-1.0 -v \
  udpsrc port=5000 \
  ! 'application/x-rtp,media=(string)video,clock-rate=(int)90000,encoding-name=(string)H264,payload=(int)96' \
  ! rtph264depay ! h264parse ! decodebin ! videoconvert ! fpsdisplaysink text-overlay=false sync=false  \
  udpsrc port=5001 \
  ! 'application/x-rtp,media=(string)audio,clock-rate=(int)44100,encoding-name=(string)AC3,payload=(int)96' \
  ! rtpac3depay ! ac3parse ! decodebin ! audioconvert ! autoaudiosink sync=false

# receiver(short version)
gst-launch-1.0 -v \
  udpsrc port=5000 caps='application/x-rtp' \
  ! rtph264depay ! decodebin ! videoconvert ! fpsdisplaysink text-overlay=false sync=false  \
  udpsrc port=5001 caps='application/x-rtp' \
  ! rtpac3depay ! decodebin ! audioconvert ! autoaudiosink sync=false
```

#### remux to MPEGST(best)

It has several advantages like good re-synchronization after packet loss and that A/V always stays sync

##### mpegts sender

```sh
# sender `mp4` file
gst-launch-1.0 -v filesrc location=/home/jetson/Videos/why_I_left_China_for_Good.mp4 \
  ! qtdemux name=demux mpegtsmux name=mux alignment=7 \
  ! rtpmp2tpay \
  ! udpsink host=$HOST port=5000 demux. \
  ! queue ! h264parse ! decodebin ! omxh264enc insert-sps-pps=true bitrate=16000000 ! mux. demux. \
  ! queue ! aacparse ! mux.
```

##### mpegts receiver

```sh
# receiver
gst-launch-1.0 -v udpsrc port=5000 \
  ! 'application/x-rtp,clock-rate=(int)90000,media=(string)video,payload=(int)96,encoding-name=(string)MP2T' \
  ! rtpmp2tdepay ! tsparse ! tsdemux name=demux \
  demux. ! queue ! decodebin ! videoconvert ! fpsdisplaysink text-overlay=false sync=false \
  demux. ! queue ! decodebin ! audioconvert ! autoaudiosink sync=false

# receiver(short version)
gst-launch-1.0 -v udpsrc port=5000 caps="application/x-rtp" \
  ! rtpmp2tdepay ! tsparse ! tsdemux name=demux \
  demux. ! queue ! decodebin ! videoconvert ! fpsdisplaysink text-overlay=false sync=false \
  demux. ! queue ! decodebin ! audioconvert ! autoaudiosink sync=false

# receiver(`ts` file)
gst-launch-1.0 -v -e udpsrc port=5000 caps="application/x-rtp" \
  ! rtpmp2tdepay ! tsparse ! filesink location=foo.ts
```

> `tsdemux demux.video_0` not work, see the details belowing:
> You're using a name (video_0) that doesn't exist. The pad names of demuxers vary from demuxer to demuxer, and might sometimes also differ from version to version. In this case that first video pad is called video_0031 as you can see at the end. It's generally best not to specify pad names unless you have a good reason to do so.

### RTSP Server

#### install server(jetson nano)

```sh
# install gst-rtsp-server libs
sudo apt-get install libgstrtspserver-1.0 libgstreamer1.0-dev

# install gst-rtsp-server test server(1.14 is your gst version, checked by gst-lanch-1.0 --version)
wget https://raw.githubusercontent.com/GStreamer/gst-rtsp-server/1.14/examples/test-launch.c
gcc test-launch.c -o test-launch $(pkg-config --cflags --libs gstreamer-1.0 gstreamer-rtsp-server-1.0)
```

#### stream web-cam(jetson nano)

```sh
# server
./test-launch "nvarguscamerasrc ! video/x-raw(memory:NVMM), format=NV12, width=1920, height=1080, framerate=30/1 ! nvvidconv ! video/x-raw, width=640, height=480, format=NV12, framerate=30/1 ! omxh265enc ! rtph265pay name=pay0 pt=96 config-interval=1"

# client
gst-launch-1.0 rtspsrc location=rtsp://jetson-desktop.local:8554/test  ! decodebin ! videoconvert ! autovideosink
```

#### stream media file(*.mp4)

1. video

    ```sh
    # server
    ./test-launch "filesrc location=/home/jetson/Videos/why_I_left_China_for_Good.mp4 \
      ! qtdemux \
      ! h264parse \
      ! decodebin \
      ! videoconvert \
      ! omxh264enc insert-sps-pps=true bitrate=16000000 \
      ! rtph264pay name=pay0"

    # client
    gst-launch-1.0 -v rtspsrc location=rtsp://jetson-desktop.local:8554/test \
      ! rtph264depay \
      ! h264parse \
      ! decodebin \
      ! videoconvert \
      ! autovideosink sync=false
    ```
  
2. audio

    ```sh
    # server
    ./test-launch "filesrc location=/home/jetson/Videos/why_I_left_China_for_Good.mp4 \
      ! qtdemux \
      ! aacparse \
      ! decodebin \
      ! audioconvert \
      ! avenc_aac \
      ! rtpmp4apay name=pay0"

    # client
    gst-launch-1.0 -v rtspsrc location=rtsp://jetson-desktop.local:8554/test \
      ! rtpmp4adepay \
      ! aacparse \
      ! decodebin \
      ! audioconvert \
      ! autoaudiosink sync=false
    ```

3. video + audio

    h264 + acc,

    ```sh
    # server
    ./test-launch "filesrc location=/home/jetson/Videos/why_I_left_China_for_Good.mp4 \
      ! qtdemux name=demux \
      demux. ! queue ! h264parse ! decodebin ! omxh264enc insert-sps-pps=true bitrate=16000000 ! rtph264pay name=pay0 \
      demux. ! queue ! aacparse ! decodebin ! audioconvert ! avenc_aac ! rtpmp4apay name=pay1"

    # client
    gst-launch-1.0 -v rtspsrc location=rtsp://jetson-desktop.local:8554/test name=src \
      src. ! rtph264depay ! h264parse ! decodebin ! videoconvert ! autovideosink sync=false \
      src. ! rtpmp4adepay ! aacparse ! decodebin ! audioconvert ! autoaudiosink sync=false

    # client(short)
    gst-launch-1.0 -v rtspsrc location=rtsp://jetson-desktop.local:8554/test name=src \
      src. ! decodebin ! videoconvert ! autovideosink sync=false \
      src. ! decodebin ! audioconvert ! autoaudiosink sync=false
    ```

    mpegts,

    ```sh
    # server
    ./test-launch "filesrc location=/home/jetson/Videos/why_I_left_China_for_Good.mp4 \
      ! qtdemux name=demux mpegtsmux name=mux alignment=7 \
      ! rtpmp2tpay name=pay0 demux. \
      ! queue ! h264parse ! decodebin ! omxh264enc insert-sps-pps=true bitrate=16000000 ! mux. demux. \
      ! queue ! aacparse ! decodebin ! audioconvert ! avenc_aac ! mux."

    # client
    gst-launch-1.0 -v rtspsrc location=rtsp://jetson-desktop.local:8554/test \
      ! rtpmp2tdepay ! tsparse ! tsdemux name=demux \
      demux. ! queue ! decodebin ! videoconvert ! fpsdisplaysink text-overlay=false sync=false \
      demux. ! queue leaky=1 ! decodebin ! audioconvert ! autoaudiosink sync=false

    # client(only video)
    gst-launch-1.0 -v rtspsrc location=rtsp://jetson-desktop.local:8554/test name=src \
      src. ! rtpmp2tdepay ! tsparse ! tsdemux name=demux ! h264parse ! avdec_h264 ! videoconvert ! autovideosink sync=false

    # client(only audio)
    gst-launch-1.0 -v rtspsrc location=rtsp://jetson-desktop.local:8554/test \
      ! rtpmp2tdepay ! tsparse ! tsdemux name=demux ! aacparse ! decodebin ! audioconvert ! autoaudiosink sync=false
    ```

### RTSP Server via MediaMTX

```sh
docker run --rm -it --network=host bluenviron/mediamtx
```

RTSP_SERVER=rtsp://192.168.2.24:8554
RTSP_SRC=$RTSP_SERVER/mystream

```sh
gst-launch-1.0 -v \
    videotestsrc is-live=true ! video/x-raw,framerate=60/1 ! clockoverlay time-format="%H:%M:%S" font-desc="Sans 24" ! \
    x264enc ! \
    queue ! mpegtsmux name=mux ! rtspclientsink location=$RTSP_SRC protocols=tcp \
    audiotestsrc is-live=true ! \
    queue ! faac bitrate=128000 ! mux.
```

```sh
gst-launch-1.0 -v \
    fallbacksrc uri=http://192.168.2.24:8080/live.ts \
    fallback-uri=file:///tmp/black_frame.png restart-on-eos=True name=d \
    d.video ! queue ! videoconvert ! x264enc ! mpegtsmux name=mux ! rtspclientsink location=$RTSP_SRC protocols=tcp \
    d.audio ! queue ! audioconvert ! faac ! mux.
```

```sh
gst-launch-1.0 playbin3 uri=$RTSP_SRC

gst-launch-1.0 -v \
    rtspsrc location=$RTSP_SRC protocols=tcp latency=100 \
    ! rtpmp2tdepay ! tsdemux name=demux \
    demux. ! queue max-size-time=0 max-size-bytes=0 max-size-buffers=0 ! decodebin ! videoconvert ! autovideosink \
    demux. ! queue max-size-time=0 max-size-bytes=0 max-size-buffers=0 ! decodebin ! audioconvert ! audioresample ! autoaudiosink
```

### Serving MPEG-TS `.ts` file by HTTP

**MPEG-TS** (MPEG Transport Stream) is a standard video container format used primarily for broadcasting and streaming applications, including HLS (HTTP Live Streaming). It is designed to be robust and fault-tolerant for delivering video and audio content over unreliable networks, such as satellite, cable, or the internet.

The live/vod video is always segmented to **MPEG-TS** chunks like 2-10s `.ts` files that are used in `HLS`.

Here, we can use a http server to serve a **MPEG-TS** files.

#### Create a single `ts` streaming file

```sh
mkdir -p /tmp/video
```

To to creat mock video:

```sh
gst-launch-1.0 -v \
    videotestsrc is-live=true ! video/x-raw,framerate=60/1 ! clockoverlay time-format="%H:%M:%S" font-desc="Sans 24" ! \
    x264enc ! \
    h264parse ! \
    mpegtsmux ! filesink location=/tmp/video/live.ts
```

To to creat mock video and mock audio:

```sh
gst-launch-1.0 -v \
    videotestsrc is-live=true ! video/x-raw,framerate=60/1 ! clockoverlay time-format="%H:%M:%S" font-desc="Sans 24" ! \
    x264enc ! \
    queue ! \
    tsmux. audiotestsrc is-live=true ! \
    faac ! \
    queue ! \
    mpegtsmux name=tsmux ! filesink location=/tmp/video/live.ts
```

or

```sh
gst-launch-1.0 -v \
    videotestsrc is-live=true ! video/x-raw,framerate=60/1 ! clockoverlay time-format="%H:%M:%S" font-desc="Sans 24" ! \
    x264enc ! \
    queue ! \
    mpegtsmux name=tsmux ! filesink location=/tmp/video/live.ts \
    audiotestsrc is-live=true ! \
    faac ! \
    queue ! \
    tsmux.
```

#### Run a simple web server

Run a simple web server to serve the **MPEG-TS** by using `Python`:

```sh
cd /tmp/video
python3 -m http.server 8080
```

#### Client to play `.ts` files

```sh
HOST=127.0.0.1
```

Media Player like VLC can view **MPEG-TS**, and Browser needs third party libraries:
https://$HOST:8080/live.ts

GStreamer pipeline to fetch the **MPEG-TS** stream.

To use `playbin3`:
```sh
gst-launch-1.0 playbin3 uri=http://$HOST:8080/live.ts
```

To play only video:
```sh
gst-launch-1.0 souphttpsrc location=http://$HOST:8080/live.ts is-live=true ! tsdemux ! decodebin ! autovideosink
```

To play only audio:
```sh
gst-launch-1.0 souphttpsrc location=http://$HOST:8080/live.ts ! tsdemux ! decodebin ! autoaudiosink
```

To play both video and audio:
```sh
gst-launch-1.0 -v \
    souphttpsrc location=http://$HOST:8080/live.ts is-live=true ! \
    tsdemux name=demux \
    demux. ! queue ! decodebin ! videoconvert ! autovideosink \
    demux. ! queue ! decodebin ! audioconvert ! audioresample ! autoaudiosink
```

```sh
gst-launch-1.0 -v \
    souphttpsrc location=http://192.168.2.24:8080/live.ts is-live=true ! \
    tsdemux name=demux \
    demux. ! queue ! h264parse! flvmux name=mux ! rtmpsink location="rtmp://192.168.2.24/live/camera2" \
    demux. ! queue ! aacparse ! mux.
```

### HLS

**HLS** is served over **HTTP** and it support both **live** and **vod** stream, which makes it friendly for mobiles or PC to use modern browsers like Chrome and Safari to play the stream in real time with low latency.

- **Compatibility**: HTTP is widely supported by most network infrastructures, including firewalls, proxies, and content delivery networks (CDNs). This makes HLS a flexible and scalable protocol for streaming across different devices and platforms.
- **Adaptive Streaming**: HLS allows for adaptive bitrate streaming, where the playlist can contain links to different quality levels (e.g., low_quality.m3u8, medium_quality.m3u8, and high_quality.m3u8). The client can request the appropriate .m3u8 file and corresponding segments based on the current network conditions.
- **Standard Web Protocol**: Since HTTP is the standard protocol used for web traffic, it allows for easy integration with web servers, CDNs, and other network components. It’s also easier to set up than some other protocols like RTMP.

#### Creating segemented **.ts** files and a **.m3u8** playlist

```sh
mkdir -p /tmp/video
```

Video for live stream(`.m3u8` playlist will be continuously updated as new segments are created)::

```sh
gst-launch-1.0 -v \
    videotestsrc is-live=true ! video/x-raw,framerate=60/1 ! clockoverlay time-format="%H:%M:%S" font-desc="Sans 24" ! \
    x264enc bitrate=1000 speed-preset=ultrafast tune=zerolatency ! \
    h264parse ! \
    hlssink2 location=/tmp/video/segment%05d.ts playlist-location=/tmp/video/live.m3u8 target-duration=2
```

Video for VOD stream:

```sh
gst-launch-1.0 -v \
    videotestsrc is-live=true ! video/x-raw,framerate=60/1 ! clockoverlay time-format="%H:%M:%S" font-desc="Sans 24" ! \
    x264enc bitrate=1000 speed-preset=ultrafast tune=zerolatency ! \
    h264parse ! \
    hlssink2 location=/tmp/video/segment%05d.ts playlist-location=/tmp/video/live.m3u8 target-duration=2 max-files=0 playlist-length=0
```

Then, MUST `CTRL+C` to exit the pipeline for adding `EXT-X-ENDLIST` into the end of the `.m3u8` file which indicates it is **VOD** stream.

To send both video and audio:

```sh
gst-launch-1.0 -v \
    videotestsrc is-live=true ! video/x-raw,framerate=60/1 ! \
    x264enc bitrate=1000 speed-preset=ultrafast tune=zerolatency ! \
    h264parse ! \
    queue ! \
    hlssink2 name=hls location=/tmp/video/segment%05d.ts playlist-location=/tmp/video/live.m3u8 target-duration=2 \
    audiotestsrc ! audio/x-raw,rate=44100,channels=2 ! \
    faac ! aacparse ! \
    queue \
    ! hls.audio
```

#### Runing a web server for serving HLS

To run a simple web server to serve the MPEG-TS or HLS file by using `Python`,

```sh
cd /tmp/video
python3 -m http.server 8080
```

#### Client to play HLS stream

Safari can play **HLS** with live update directly via `http://127.0.0.1:8080/live.m3u8`, while Chrome needs third-party javascript libraries like **hls.js**:

GStreamer pipeline,

To use `playbin3`:

```sh
gst-launch-1.0 playbin3 uri=http://$HOST:8080/live.m3u8
```

To play only video:
```sh
gst-launch-1.0 -v souphttpsrc location=http://$HOST:8080/live.m3u8 is-live=TRUE ! hlsdemux ! decodebin ! autovideosink
```

To play only audio:
```sh
gst-launch-1.0 souphttpsrc location=http://$HOST:8080/live.m3u8 ! hlsdemux ! decodebin ! audioconvert ! audioresample ! autoaudiosink
```

To play both video and audio:
```sh
gst-launch-1.0 -v \
    souphttpsrc location=http://$HOST:8080/live.m3u8 ! \
    hlsdemux ! tsdemux name=demux \
    demux. ! queue ! decodebin ! videoconvert ! autovideosink \
    demux. ! queue ! decodebin ! audioconvert ! audioresample ! autoaudiosink
```

> Note: `tsdemux` needs to be sitting between `hlsdemux` and `decodebin`!

### RTMP Server

RTMP server supports both live streams and on-demand streams.
RTMP server can only accept `FLV` container format.

#### Set up a RTMP server

Here, if you need your own RTMP server, running the following docker container works quite simply well.

```sh
docker run -d -p 1935:1935 --name nginx-rtmp tiangolo/nginx-rtmp
```

A modified configuration file `nginx.config` can be used to serve either a RTMP stream or a HLS stream,

```conf title=/etc/nginx/nginx.conf
worker_processes auto;
rtmp_auto_push on;
events {}
rtmp {
    server {
        listen 1935;
        listen [::]:1935 ipv6only=on;

        application live {
            live on;
            record off;
	          interleave on; # Ensures audio and video packets are properly synchronized.

            hls on;
            hls_path /tmp/hls;
        }
    }
}

http {
    server {
        listen 8080;  # HTTP port for accessing HLS streams

        # Serve the HLS playlist and segments
        location /hls/ {
            root /tmp;  # Path to HLS files
            add_header Cache-Control no-cache;
            add_header Access-Control-Allow-Origin *;  # Allow cross-origin access
        }
    }
}
```

The RTMP url format is like: `rtmp://<ip_of_host>/live/<key>`, and the HLS can be visited at `http://<ip_of_host>/hls/<key>.m3u8`.

#### Send a live stream to a RTMP server

```sh
HOST=192.168.2.24
RTMP_SRC="rtmp://$HOST/live/camera1"
```

To send a video:
```sh
gst-launch-1.0 -v \
    videotestsrc is-live=true ! video/x-raw,framerate=60/1 ! clockoverlay time-format="%H:%M:%S" font-desc="Sans 24" ! \
    x264enc ! \
    flvmux streamable=true name=mux ! rtmpsink location=$RTMP_SRC
```

To send a video and audio:
```sh
gst-launch-1.0 -v \
    videotestsrc is-live=true ! video/x-raw,framerate=60/1 ! clockoverlay time-format="%H:%M:%S" font-desc="Sans 24" ! \
    x264enc ! \
    queue ! flvmux streamable=true name=mux ! rtmpsink location=$RTMP_SRC \
    audiotestsrc is-live=true ! \
    queue ! faac bitrate=128000 ! mux.
```

```sh
gst-launch-1.0 \
    videotestsrc is-live=1 \
    ! videoconvert \
    ! "video/x-raw, width=1280, height=720, framerate=30/1" \
    ! queue \
    ! x264enc cabac=1 bframes=2 ref=1 \
    ! "video/x-h264,profile=main" \
    ! flvmux streamable=true name=mux \
    ! rtmpsink location="$RTMP_SRC live=1" \
    audiotestsrc is-live=1 wave=ticks \
    ! faac bitrate=128000 \
    ! mux.
```

#### Receiver a live stream

Let's play the above `RTMP_SRC` which is a live stream.

> NOTE: A test RTMP on-demand stream is at: RTMP_SRC="rtmp://matthewc.co.uk/vod/scooter.flv", which can be used to test your pipeline.

To use `playbin3`, it's simple while versatile and magic:
```sh
gst-launch-1.0 playbin3 uri=$RTMP_SRC
```

To play only video:
```sh
gst-launch-1.0 rtmpsrc location=$RTMP_SRC ! decodebin ! videoconvert ! autovideosink
```

To play only audio:
```sh
gst-launch-1.0 rtmpsrc name=rtmpsrc location=$RTMP_SRC ! decodebin ! audioconvert ! autoaudiosink
```

To play video and audio in a fine-grained pipeline:
```sh
gst-launch-1.0 rtmpsrc location="$RTMP_SRC live=1" ! \
    flvdemux name=demux \
    demux.audio ! queue ! decodebin ! audioconvert ! autoaudiosink \
    demux.video ! queue ! decodebin ! videoconvert ! autovideosink 
```

```sh
gst-launch-1.0 rtmpsrc location="$RTMP_SRC live=1" ! \
    flvdemux name=demux \
    demux.audio ! queue max-size-time=0 max-size-bytes=0 max-size-buffers=0 ! decodebin ! audioconvert ! autoaudiosink \
    demux.video ! queue max-size-time=0 max-size-bytes=0 max-size-buffers=0 ! decodebin ! videoconvert ! autovideosink
```

## Mixing

### Mixing videos

```sh
# display
gst-launch-1.0 -e compositor name=comp sink_0::alpha=0.7 sink_1::alpha=0.5 \
    ! autovideosink \
    videotestsrc \
        ! video/x-raw, framerate=10/1, width=640, height=360 \
        ! comp.sink_0 \
    videotestsrc pattern="snow" \
        ! video/x-raw, framerate=10/1, width=200, height=150 \
        ! comp.sink_1
```

video + rtp/udp,

```sh
# sender
gst-launch-1.0 -e compositor name=comp sink_0::alpha=0.7 sink_1::alpha=0.5 \
    ! videoconvert ! omxh264enc insert-sps-pps=true bitrate=16000000 ! h264parse ! rtph264pay ! udpsink port=5000 host=$HOST \
    videotestsrc \
        ! video/x-raw, framerate=10/1, width=640, height=360 \
        ! comp.sink_0 \
    videotestsrc pattern="snow" \
        ! video/x-raw, framerate=10/1, width=200, height=150 \
        ! comp.sink_1
```

[receiver](#receive-h264-rtp-stream)

### Mixing video+audio

sender(mpegts + rtp/udp),

```sh
# sender(videotestsrc/audiotestsrc)
gst-launch-1.0 -v \
    mpegtsmux name=mux alignment=7 ! rtpmp2tpay \
    ! udpsink port=5000 host=$HOST sync=false \
    compositor name=videomix ! x264enc ! queue ! mux. \
    audiomixer name=audiomix ! audioconvert ! audioresample ! avenc_ac3 ! queue ! mux. \
    videotestsrc pattern=ball ! videomix. \
    videotestsrc pattern=pinwheel ! videoscale ! video/x-raw,width=100 ! videomix. \
    audiotestsrc freq=400 ! audiomix. \
    audiotestsrc freq=600 ! audiomix.

# sender(mp4 file)
SRC=/home/jetson/Videos/why_I_left_China_for_Good.mp4
gst-launch-1.0 -v \
    mpegtsmux name=mux alignment=7 ! rtpmp2tpay \
    ! udpsink port=5000 host=$HOST sync=false \
    compositor name=videomix ! omxh264enc bitrate=16000000 ! queue2 ! mux. \
    audiomixer name=audiomix ! audioconvert ! audioresample ! avenc_ac3 ! queue2 ! mux. \
    filesrc location=$SRC ! qtdemux name=demux \
    demux.video_0 ! queue2 ! h264parse ! omxh264dec ! videoconvert ! videomix. \
    demux.audio_0 ! queue2 ! decodebin ! audioconvert ! audioresample ! audiomix. \
    videotestsrc pattern=ball ! videoscale ! video/x-raw,width=100,height=100 ! videomix. \
    audiotestsrc freq=600 volume=0.1 ! audiomix.

# sender(mp4 file) `uridecodebin`
gst-launch-1.0 \
    mpegtsmux name=mux ! rtpmp2tpay \
    ! udpsink port=5000 host=$HOST sync=false \
    compositor name=videomix ! x264enc ! queue2 ! mux. \
    audiomixer name=audiomix ! audioconvert ! audioresample ! avenc_ac3 ! queue2 ! mux. \
    uridecodebin uri=file://$SRC name=dec \
    dec. ! queue2 ! audioconvert ! audioresample ! audiomix. \
    dec. ! queue2 ! nvvidconv ! videoconvert ! video/x-raw,width=640,height=360 ! videomix. \
    videotestsrc pattern=ball ! video/x-raw,width=100,height=100 ! videomix. \
    audiotestsrc freq=400 volume=0.2 ! audiomix.
```

tcp server,

```sh
# View this in VLC with tcp://localhost:7001
gst-launch-1.0 \
    mpegtsmux name=mux ! rtpmp2tpay ! \
    tcpserversink port=7001 host=0.0.0.0 recover-policy=keyframe sync-method=latest-keyframe sync=false \
    compositor name=videomix ! x264enc ! queue2 ! mux. \
    audiomixer name=audiomix ! audioconvert ! audioresample ! avenc_ac3 ! queue2 ! mux. \
    uridecodebin uri=file://$SRC name=demux ! \
    queue2 ! audioconvert ! audioresample ! audiomix. \
    demux. ! queue2 ! decodebin ! nvvidconv ! videoconvert ! videoscale ! video/x-raw,width=640,height=360 ! videomix. \
    videotestsrc pattern=ball ! videoscale ! video/x-raw,width=100,height=100 ! videomix. \
    audiotestsrc freq=400 volume=0.2 ! audiomix.
```

> **tips**
> for jetson nano, use `nvvidconv` instead of `videoconvert` because `decodebin` use `nvv4l2decoder` to decode H.264 in default. Otherwise, explictly decode H.264 with `omxh264dec`.

receiver,

```sh
# receiver
[mpegts receiver](#mpegts-receiver)
gst-launch-1.0 -v udpsrc port=5000 caps="application/x-rtp" \
  ! rtpmp2tdepay ! tsparse ! tsdemux name=demux \
  demux. ! queue ! decodebin ! videoconvert ! fpsdisplaysink text-overlay=false sync=false \
  demux. ! queue leaky=1 ! decodebin ! audioconvert ! autoaudiosink sync=false
```

## SHM(Shared Memory)

### raw video

```sh
# send
gst-launch-1.0 -v videotestsrc is-live=true ! 'video/x-raw,width=1280,height=720,format=(string)RGB,framerate=(fraction)60/1' ! videoconvert ! shmsink socket-path=/tmp/foo name=/tmp/shm sync=false wait-for-connection=false shm-size=20000000

# receive
gst-launch-1.0 -v shmsrc do-timestamp=true socket-path=/tmp/foo name=/tmp/shm ! 'video/x-raw,width=1280,height=720,format=(string)RGB,framerate=(fraction)60/1' ! videoconvert ! fpsdisplaysink text-overlay=false sync=false -e
```

**tips:**

1. `do-timestamp=true`: solve `gst_segment_to_stream_time: assertion 'segment->format == format' failed` error. Seeing at[Getting shmsink/shmsrc to work with videomixer](https://mazdermind.wordpress.com/2014/08/29/getting-shmsinkshmsrc-to-work-with-videomixer/)
2. In local host, use `raw video` faster than `h264` due to memory cheaper/faster that cpu
3. increase `shm-size` for large image

### h264 encode/decode

```sh
# send
gst-launch-1.0 -v videotestsrc ! x264enc ! shmsink socket-path=/tmp/foo sync=false wait-for-connection=false shm-size=10000000

gst-launch-1.0 -v videotestsrc ! 'video/x-raw,width=1280,height=720,format=NV12,framerate=60/1' ! x264enc ! shmsink socket-path=/tmp/foo sync=false wait-for-connection=false shm-size=10000000

# receive
gst-launch-1.0 -v shmsrc socket-path=/tmp/foo ! h264parse ! decodebin ! videoconvert ! fpsdisplaysink text-overlay=false sync=false
```

## Fallbacksrc


```sh
gst-launch-1.0 fallbacksrc uri=http://192.168.2.24:8080/live.ts \
    fallback-uri=file:///tmp/black_frame.png restart-on-eos=True ! \
    tsdemux name=demux \
    demux. ! queue ! h264parse! flvmux name=mux ! rtmpsink location="rtmp://192.168.2.24/live/camera2" \
    demux. ! queue ! aacparse ! mux.

gst-launch-1.0 fallbacksrc uri=http://192.168.2.24:8080/live.ts \
    fallback-uri=file:///tmp/black_frame.png restart-on-eos=True ! \
    videoconvert ! autovideosink

gst-launch-1.0 fallbacksrc uri=http://192.168.2.24:8080/live.ts \
    fallback-uri=file:///tmp/black_frame.png restart-on-eos=True ! \
    decodebin ! audioconvert ! autoaudiosink

gst-launch-1.0 fallbacksrc uri=http://192.168.2.24:8080/live.ts \
    fallback-uri=file:///tmp/black_frame.png restart-on-eos=True name=d \
    d.video ! queue ! videoconvert ! autovideosink \
    d.audio ! queue ! audioconvert ! autoaudiosink

gst-launch-1.0 fallbacksrc uri=http://192.168.2.24:8080/live.ts \
    fallback-uri=file:///tmp/black_frame.png restart-on-eos=True name=d \
    d.video ! queue ! videoconvert ! x264enc ! flvmux name=mux ! rtmpsink location="rtmp://192.168.2.24/live/camera2" \
    d.audio ! queue ! audioconvert ! faac ! mux.
```

## Live Stream, Format, Codec Comparison

| Feature     | Protocol                    | Container Format           | Codec Format                    |
|-------------|-----------------------------|----------------------------|---------------------------------|
| Role        | Transport data over network | Holds multimedia streams   | Compresses and encodes streams  |
| Examples    | HLS, DASH, RTMP, RTSP, RTP  | MP4, MKV, FLV, MPEG-TS     | H.264, H.265, AAC, MP3          |
| Components  |                             | Audio, video, metadata     | Audio or video encoding methods |
| Flexibility |                             | Can support various codecs | Typically codec-specific        |
| Purpose     | Transport data over network | Organizes data for storage | Reduces size for transmission   |

## python-opencv

```py
import cv2
import time
# capture

# videotestsrc
gst_str = 'videotestsrc ! video/x-raw,framerate=20/1 ! videoscale ! videoconvert ! appsink'

# udpsrc
gst_str = 'udpsrc port=5000 ! "application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)H264, payload=(int)96" ! rtph264depay ! h264parse ! decodebin ! videoconvert ! autovideosink'

gst_str = 'udpsrc port=5000 caps = "application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)H264, payload=(int)96" ! rtph264depay ! decodebin ! videoconvert ! appsink'

cap = cv2.VideoCapture(gst_str, cv2.CAP_GSTREAMER)

cap.isOpened()
ret, frame = cap.read()
cv2.imwrite("result.jpg", frame)
cap.release()

# write

# udpsink
gst_str = 'appsrc ! videoconvert ! x264enc tune=zerolatency bitrate=500 speed-preset=superfast ! rtph264pay ! udpsink host=127.0.0.1 port=5000'

fps = 30
frame_width = 640
frame_height = 480
out = cv2.VideoWriter(gst_str, cv2.CAP_GSTREAMER, 0, fps, (frame_width, frame_height), True)
out.isOpened()

img = cv2.imread('WechatIMG1.jpeg')
img.shape
img = cv2.resize(img, (frame_width, frame_height))
img.shape
cv2.imwrite("result.jpg", img)
while True:
    out.write(img)
    time.sleep(1/60)

out.release()
```

[convert gstreamer pipeline to opencv in python](https://stackoverflow.com/questions/51539706/convert-gstreamer-pipeline-to-opencv-in-python)  
[python-opencv-gstreamer-examples](https://github.com/madams1337/python-opencv-gstreamer-examples)