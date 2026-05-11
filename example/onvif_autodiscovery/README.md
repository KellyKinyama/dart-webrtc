# onvif_autodiscovery

Find every ONVIF camera on the LAN and print its `rtsp://` stream URLs.
Pure Dart, zero dependencies beyond `args`.

## Run

```powershell
cd C:\www\dart\dart-webrtc\example\onvif_autodiscovery
dart pub get
dart run bin\onvif_discover.dart                  # discover only
dart run bin\onvif_discover.dart --user admin --pass mypw   # auth needed
```

Output (tab-separated):

```
192.168.1.50  IPC-D120  MainStream  rtsp://192.168.1.50:554/Streaming/Channels/101
192.168.1.50  IPC-D120  SubStream   rtsp://192.168.1.50:554/Streaming/Channels/102
192.168.1.51  HFW1200   Profile_1   rtsp://192.168.1.51:554/cam/realmonitor?channel=1&subtype=0
```

## Pipe straight into multicam viewer

```powershell
$rows = dart run bin\onvif_discover.dart --user admin --pass pw
$args = @()
$i = 0
foreach ($row in $rows) {
  $url = ($row -split "`t")[3]
  if ($url -like 'rtsp://*') { $args += '--cam'; $args += "cam$i=$url"; $i++ }
}
cd ..\rtsp_camera_to_webrtc
dart run bin\multicam_pure_to_webrtc.dart --ip 192.168.56.1 @args
```

## Flags

| Flag | Default | Meaning |
|---|---|---|
| `--timeout` | `4`     | Discovery duration (s) |
| `--iface`   | auto    | Local IP to send the multicast probe from |
| `--user` / `--pass` | empty | WS-UsernameToken auth (PasswordDigest) |
| `--rtsp` / `--no-rtsp` | on | Also do `GetProfiles` + `GetStreamUri` per device |

## How it works

1. **WS-Discovery** (OASIS, 2009). Send a SOAP `<Probe>` for
   `dn:NetworkVideoTransmitter` to the multicast group
   `239.255.255.250:3702` over UDP. Cameras reply unicast with a
   `<ProbeMatch>` containing one or more device service URLs (`XAddrs`).
2. **GetCapabilities** on each XAddr → extract the Media service URL.
3. **GetProfiles** on the Media service → list of media profiles.
4. **GetStreamUri** for each profile asking for `RTP-Unicast` / `RTSP`
   transport → the `rtsp://` URL.

Auth uses **WS-UsernameToken** with PasswordDigest
(SHA1(nonce + created + password)). Most ONVIF firmware accepts this
even when the same user would otherwise need HTTP Digest.

## Limitations

- IPv4 only (multicast group `239.255.255.250`).
- Not every "ONVIF" camera answers a Probe — some need ONVIF explicitly
  enabled in the web UI, some expect the legacy `tds:Device` namespace.
- No XML parser — we use a few targeted regexes. Works for every camera
  I've tested but is fragile if the device emits creative whitespace.
- Multi-NIC hosts: pass `--iface` with the IP that's on the same subnet
  as the cameras, otherwise the probe goes out the wrong interface.
