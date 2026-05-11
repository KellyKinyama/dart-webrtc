# packet_loss_simulator

Bidirectional UDP middlebox that drops, reorders, duplicates and delays
packets. The single most useful tool when debugging WebRTC.

```
peer A ──▶ [listen] ── lossy A→B ──▶ [target]
peer A ◀── [listen] ◀── lossy B→A ── [target]
```

## Run

```powershell
cd C:\www\dart\dart-webrtc\example\packet_loss_simulator
dart pub get
dart run bin\packet_loss_simulator.dart `
  --listen 0.0.0.0:7000 `
  --target 192.168.1.50:5000 `
  --drop 5 --delay 30 --jitter 20
```

Now point the *client* at `127.0.0.1:7000` instead of the real server.
The simulator learns the client's source address from the first packet
and uses it for the return path.

## Flags

| Flag | Default | Meaning |
|---|---|---|
| `--listen`         | `0.0.0.0:7000` | Where the client connects |
| `--target`         | *(required)*   | Real server `host:port` |
| `--drop`           | `0`            | Drop % both directions (0–100) |
| `--reorder`        | `0`            | Reorder % both directions |
| `--duplicate`      | `0`            | Duplicate % both directions |
| `--delay`          | `0`            | Base delay (ms) both directions |
| `--jitter`         | `0`            | ± jitter (ms) both directions |
| `--drop-a2b` / `--drop-b2a` | inherit | Per-direction drop overrides |
| `--delay-a2b` / `--delay-b2a` | inherit | Per-direction delay overrides |
| `--seed`           | random | RNG seed for reproducible runs |

Stats print every 5 s: `rx`, `delivered`, `dropped`, `reordered`,
`duplicated`.

## Recipes

**Mild lossy network (cellular):** `--drop 1 --delay 80 --jitter 30`

**Bad WiFi:** `--drop 5 --reorder 2 --delay 60 --jitter 40`

**Asymmetric DSL (uplink worse than down):**
`--drop-a2b 8 --drop-b2a 1 --delay-a2b 120 --delay-b2a 30`

**Catastrophic:** `--drop 30 --delay 200 --jitter 100`

## Limitations

- UDP only.
- Per-packet random model; not a real network emulator (no bandwidth
  cap, no buffer-overflow tail-drop). For that, use `tc netem` on Linux
  or `clumsy` on Windows.
