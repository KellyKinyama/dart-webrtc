# **1. RUNNING IN DEVELOPMENT MODE**

The Go original required Docker + a VS Code dev container. The Dart
port runs as a normal Dart process.

## **1.1. Clone and bootstrap**

```pwsh
git clone <this-repo> dart-webrtc
cd dart-webrtc
dart pub get

cd example/ion_style_sfu
dart pub get
```

## **1.2. Discover your LAN IP**

The browser and the SFU exchange ICE candidates. The candidate the
client will actually use is one the browser can reach over the LAN, so
the SFU has to *announce* an address that is reachable from your
laptop — not `0.0.0.0`, and not the Docker bridge.

```pwsh
# Windows:
ipconfig | Select-String 'IPv4'

# macOS / Linux:
ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'
```

Note the address (e.g. `192.168.1.42`) — you'll pass it as
`--announce-ip`.

## **1.3. Start the SFU**

From the repo root:

```pwsh
dart run example/ion_style_sfu/bin/sfu_server.dart `
  --ip 0.0.0.0 `
  --ws-port 9090 `
  --rtp-base 51000 `
  --announce-ip 192.168.1.42 `
  --ice-server stun:stun.l.google.com:19302
```

You should see the WebSocket listener start:

```text
ion-style SFU listening
  ws://0.0.0.0:9090
  rtp UDP base port 51000
  announce IP 192.168.1.42
```

The full set of flags lives in
[example/ion_style_sfu/bin/sfu_server.dart](../../example/ion_style_sfu/bin/sfu_server.dart).

## **1.4. Debugging in VS Code**

The repo ships no `.vscode/launch.json`, but Dart's debugger picks up
any program with a `main()` automatically:

1. Open `example/ion_style_sfu/bin/sfu_server.dart` in VS Code.
2. Press <kbd>F5</kbd>. Choose **"Dart"** when asked for an environment.
3. Pass CLI args via the auto-generated `launch.json`:

   ```jsonc
   {
     "type": "dart",
     "name": "SFU",
     "request": "launch",
     "program": "example/ion_style_sfu/bin/sfu_server.dart",
     "args": ["--announce-ip", "192.168.1.42",
              "--ice-server", "stun:stun.l.google.com:19302"]
   }
   ```

Set breakpoints anywhere in [lib/src/dtls/](../../lib/src/dtls/),
[lib/src/srtp/](../../lib/src/srtp/) or
[example/ion_style_sfu/lib/src/](../../example/ion_style_sfu/lib/src/)
— they will hit on the first inbound packet.

## **1.5. Tests**

```pwsh
# Core protocol tests (DTLS handshake, ICE gathering, SRTP replay …)
dart test

# SFU-level tests
cd example/ion_style_sfu
dart test
```

The list of test files lives under [test/](../../test/) and
[example/ion_style_sfu/test/](../../example/ion_style_sfu/test/).

## **1.6. The browser side**

There is no bundled UI. Any standard WebRTC sample page that
posts/receives SDP over a WebSocket can drive the SFU. The wire
format the SFU speaks is documented in chapter 3.

For quick smoke-testing, the `WebRTC-Simple-SDP-Handshake-Demo/` folder
at the repo root contains a static HTML page you can open with any
local web-server (e.g. `dart pub global activate dhttpd && dhttpd`).

You're now ready for the SFU to actually wake up.

---

<div align="right">

[&lt;&nbsp;&nbsp;Previous chapter: INFRASTRUCTURE](./00-INFRASTRUCTURE.md)&nbsp;&nbsp;|&nbsp;&nbsp;[Next chapter: SERVER INITIALIZATION&nbsp;&nbsp;&gt;](./02-BACKEND-INITIALIZATION.md)

</div>
