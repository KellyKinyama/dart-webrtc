# Running the ion-style SFU demo locally (Windows / PowerShell)

Quick reference for starting and stopping the two servers needed to test the
SFU in a browser. Picks up where [`README.md`](README.md) leaves off.

## Prerequisites (one-time)

- Dart SDK on `PATH` (`dart --version`).
- Python 3 on `PATH` (`python --version`) — used as the static file server.
- A real LAN IPv4 address. Re-check whenever your network changes:

  ```powershell
  Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.PrefixOrigin -ne 'WellKnown' } |
    Select-Object IPAddress, InterfaceAlias | Format-Table -AutoSize
  ```

  Pick the one on your `Ethernet` / `Wi-Fi` adapter — **not** `vEthernet (WSL ...)`,
  `vEthernet (Default Switch)`, or VirtualBox / Hyper-V virtual adapters.
  Substitute that IP for `10.100.54.133` everywhere below.

- Browser whitelist for `getUserMedia` over plain HTTP (one-time per browser):
  open `chrome://flags/#unsafely-treat-insecure-origin-as-secure`, set it to
  **Enabled**, paste both origins, and relaunch:

  ```text
  http://10.100.54.133:8000,http://10.100.54.133:9091
  ```

  (Edge: same flag at `edge://flags/#unsafely-treat-insecure-origin-as-secure`.)

## Start

Run each command in **its own PowerShell window** so you can stop them
individually with Ctrl+C.

### 1. SFU (WebSocket signaling + media)

```powershell
cd C:\www\dart\dart-webrtc
dart run example/ion_style_sfu/bin/sfu_server.dart `
  --ip 0.0.0.0 `
  --ws-port 9091 `
  --rtp-base 51000 `
  --announce-ip 10.100.54.133 `
  --ice-server stun:stun.l.google.com:19302 `
  --ice-server stun:stun1.l.google.com:19302
```

Healthy log line:

```text
INFO  sfu listening {wsUrl=ws://10.100.54.133:9091/ws/<sessionId>, rtpBase=51000, announce=10.100.54.133}
```

### 2. Static page server (serves `web/index.html`)

```powershell
cd C:\www\dart\dart-webrtc\example\ion_style_sfu\web
python -m http.server 8000 --bind 0.0.0.0
```

Healthy log line:

```text
Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...
```

### 3. Open in the browser (one tab per peer)

Polished Google-Meet-style UI (recommended):

```text
http://10.100.54.133:8000/meet.html?server=ws://10.100.54.133:9091&sid=room1
http://10.100.54.133:8000/meet.html?server=ws://10.100.54.133:9091&sid=room1
```

Each tab gets a unique uid automatically (no `&uid=` in the URL), so you
can open as many as you like without colliding at the SFU.

Bare debug UI (raw `<video>` tags + log + stats panel):

```text
http://10.100.54.133:8000/?server=ws://10.100.54.133:9091&sid=room1&uid=alice
http://10.100.54.133:8000/?server=ws://10.100.54.133:9091&sid=room1&uid=bob
```

Each tab prompts for camera/mic, then shows its own preview plus one remote
`<video>` per other peer.

## Verify it's up

```powershell
# TCP reachable from the LAN?
Test-NetConnection 10.100.54.133 -Port 8000 -InformationLevel Quiet
Test-NetConnection 10.100.54.133 -Port 9091 -InformationLevel Quiet

# SFU JSON endpoints
curl http://10.100.54.133:9091/healthz
curl http://10.100.54.133:9091/stats
curl http://10.100.54.133:9091/metrics
```

## Stop

The clean way is **Ctrl+C in each terminal window**. If a window is gone or
unresponsive, kill by port from any PowerShell:

```powershell
# Stop the page server (port 8000)
Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue |
  Select-Object -Expand OwningProcess -Unique |
  ForEach-Object { Stop-Process -Id $_ -Force }

# Stop the SFU (port 9091)
Get-NetTCPConnection -LocalPort 9091 -State Listen -ErrorAction SilentlyContinue |
  Select-Object -Expand OwningProcess -Unique |
  ForEach-Object { Stop-Process -Id $_ -Force }
```

Verify nothing is left listening on those ports:

```powershell
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
  Where-Object { $_.LocalPort -in 8000, 9091 }
```

Empty output = both stopped.

## Optional one-time firewall rules (admin PowerShell)

Only needed when other devices on your LAN can't reach 8000 / 9091:

```powershell
New-NetFirewallRule -DisplayName "ion-sfu http (8000)"  -Direction Inbound -Protocol TCP -LocalPort 8000        -Action Allow -Profile Private
New-NetFirewallRule -DisplayName "ion-sfu ws (9091)"    -Direction Inbound -Protocol TCP -LocalPort 9091        -Action Allow -Profile Private
New-NetFirewallRule -DisplayName "ion-sfu rtp (51000+)" -Direction Inbound -Protocol UDP -LocalPort 51000-51999 -Action Allow -Profile Private
```

Remove later:

```powershell
Remove-NetFirewallRule -DisplayName "ion-sfu http (8000)"
Remove-NetFirewallRule -DisplayName "ion-sfu ws (9091)"
Remove-NetFirewallRule -DisplayName "ion-sfu rtp (51000+)"
```

## Common issues

| Symptom in the browser | Cause | Fix |
|---|---|---|
| `ERR_CONNECTION_TIMED_OUT` on `:8000` | Page server not running, or firewall | Start it (step 2); see firewall section |
| `Cannot read properties of undefined (reading 'getUserMedia')` | Origin not a secure context | Whitelist origin in `chrome://flags` (Prerequisites) or use `http://localhost:8000` |
| `pub ice: disconnected` right after `checking` | Browser can't reach `--announce-ip` | Re-check the IP picked above; restart the SFU with the right one |
| Works on the host machine, not on phone/laptop | LAN firewall / "AP isolation" on router | Add firewall rules above; disable AP isolation in router admin |
