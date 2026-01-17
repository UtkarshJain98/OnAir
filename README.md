# 🔴 On Air

**Automatic "on air" busy light for macOS.**

On Air turns on a smart light when your camera or microphone is in use, letting others know you're in a meeting. Works with any HomeKit/Matter-compatible switch or bulb.

- **Event-based detection** — 0% CPU when idle, instant response
- **Works with any app** — Zoom, Google Meet, Teams, Slack, FaceTime, Discord, etc.
- **Simple setup** — Just two Shortcuts and one command

## How It Works

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────┐
│  Camera/Mic ON  │ ──► │     On Air       │ ──► │  🔴 Light   │
│  (any app)      │     │  (event-based)   │     │     ON      │
└─────────────────┘     └──────────────────┘     └─────────────┘
```

On Air listens for macOS system events when any app activates your camera or microphone. No polling, no battery drain.

## Requirements

- macOS 12 (Monterey) or later
- HomeKit/Matter smart switch or bulb (configured in Apple Home)
- 5 minutes for setup

## Quick Start

### Step 1: Create the Shortcuts

Open the **Shortcuts** app on your Mac and create two shortcuts:

<details>
<summary><b>🔴 "On Air"</b> (click to expand)</summary>

1. Open Shortcuts app
2. Click **+** to create a new shortcut
3. Name it exactly: `On Air`
4. Search for "Control Home" and add it
5. Click on the action and select your switch/bulb
6. Set to **Turn On**
7. Save (Cmd+S)

</details>

<details>
<summary><b>⚪ "Off Air"</b> (click to expand)</summary>

1. Open Shortcuts app
2. Click **+** to create a new shortcut
3. Name it exactly: `Off Air`
4. Search for "Control Home" and add it
5. Click on the action and select your switch/bulb
6. Set to **Turn Off**
7. Save (Cmd+S)

</details>

### Step 2: Install On Air

```bash
git clone https://github.com/UtkarshJain98/OnAir.git
cd OnAir
./on-air.sh install
```

That's it! Your light will now turn on automatically when you join a meeting.

## Usage

```bash
# Check status
./on-air.sh status

# Test shortcuts work
./on-air.sh test

# View live logs
./on-air.sh logs

# Manual control
./on-air.sh on
./on-air.sh off

# Uninstall
./on-air.sh uninstall
```

## Supported Apps

On Air works with **any app** that uses your camera or microphone:

| App | Camera | Microphone |
|-----|:------:|:----------:|
| Zoom | ✅ | ✅ |
| Google Meet | ✅ | ✅ |
| Microsoft Teams | ✅ | ✅ |
| Slack Huddles | ✅ | ✅ |
| FaceTime | ✅ | ✅ |
| Discord | ✅ | ✅ |
| WebEx | ✅ | ✅ |
| Any other app | ✅ | ✅ |

## Behavior Details

### Camera Detection
- Light turns **ON** when any app activates your camera
- Light turns **OFF** when all apps release the camera
- Toggling camera on/off in an app triggers the light immediately

### Microphone Detection
- Light turns **ON** when you join a meeting with mic enabled
- Light turns **OFF** when you leave the meeting
- **Note:** Muting/unmuting within a meeting does NOT toggle the light (apps use "software mute" which keeps the mic hardware active)

This behavior is ideal for a busy light — you want the light on for the entire meeting, not flickering when you mute/unmute.

## Configuration

Edit `on-air.conf` to customize:

```bash
# Shortcut names (must match Shortcuts app exactly)
SHORTCUT_ON="On Air"
SHORTCUT_OFF="Off Air"

# Detection mode: "camera", "mic", or "both" (default)
DETECTION_MODE="both"

# Enable debug logging
ENABLE_DEBUG_LOGS=false
```

After editing, reinstall to apply:
```bash
./on-air.sh install
```

## Troubleshooting

### Light doesn't turn on

1. **Test shortcuts manually:**
   ```bash
   ./on-air.sh test
   ```
   If this fails, check that your shortcuts exist and are named exactly right.

2. **Check the service is running:**
   ```bash
   ./on-air.sh status
   ```

3. **View logs for errors:**
   ```bash
   ./on-air.sh logs
   ```

4. **Enable debug mode** in `on-air.conf`:
   ```bash
   ENABLE_DEBUG_LOGS=true
   ```
   Then reinstall and check logs.

### Shortcuts fail silently

If shortcuts work in the Shortcuts app but fail from terminal, you may need to grant permissions:

1. Open **System Settings → Privacy & Security → Automation**
2. Find Terminal (or your terminal app) and enable access to **Shortcuts Events**
3. Reinstall: `./on-air.sh install`

### Service doesn't start

Check the error log:
```bash
cat ~/.onair/stderr.log
```

## How It Works (Technical)

On Air uses macOS system log streams to detect hardware state changes:

| Detection | Log Predicate | Event |
|-----------|--------------|-------|
| Camera | `com.apple.controlcenter` | `Frame publisher cameras changed` |
| Microphone | `audiomxd` process | `starting recording` / `stopping recording` |

This event-based approach means:
- **Zero polling** — Script sleeps until an event occurs
- **Zero CPU usage** — No overhead when camera/mic are idle
- **Instant response** — Reacts within milliseconds

## Files

```
on-air/
├── on-air.sh        # Main script (run this)
├── on-air.conf      # Configuration (created on install)
├── README.md        # This file
└── LICENSE          # MIT License

~/.onair/
├── on-air.log       # Activity log
├── state            # Current state
├── stdout.log       # Service stdout
└── stderr.log       # Service stderr

~/Library/LaunchAgents/
└── com.onair.plist  # Auto-start config
```

## Uninstalling

```bash
./on-air.sh uninstall
```

To remove all files including logs:
```bash
./on-air.sh uninstall
rm -rf ~/.onair
rm -f on-air.conf
```

## Contributing

Contributions welcome! Ideas for improvements:

- [ ] Menu bar app for status/control
- [ ] Multiple light support
- [ ] Custom color/brightness for different apps
- [ ] Calendar integration (detect scheduled meetings)

## License

MIT License — free to use, modify, and distribute.

---

Made for working from home 🏠
