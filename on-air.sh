#!/bin/bash
#
# On Air v1.0.0
# https://github.com/UtkarshJain98/OnAir
#
# Automatic "on air" busy light for macOS.
# Turns on a HomeKit/Matter smart switch when your camera or microphone
# is in use, letting others know you're in a meeting.
#
# Features:
#   - Event-based detection (0% CPU when idle)
#   - Instant response
#   - Works with any app: Zoom, Google Meet, Teams, Slack, FaceTime, etc.
#   - Supports HomeKit/Matter devices via Apple Shortcuts
#
# Requirements:
#   - macOS 12 (Monterey) or later
#   - HomeKit/Matter smart switch configured in Apple Home
#   - Two Shortcuts: "On Air" and "Off Air"
#
# Usage:
#   ./on-air.sh install    # Install and start
#   ./on-air.sh uninstall  # Remove completely
#   ./on-air.sh status     # Check status
#   ./on-air.sh --help     # Show all commands
#

set -euo pipefail

VERSION="1.0.0"

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/on-air.conf"

# Default configuration
DEFAULT_SHORTCUT_ON="On Air"
DEFAULT_SHORTCUT_OFF="Off Air"
DEFAULT_ENABLE_DEBUG_LOGS=false
DEFAULT_DETECTION_MODE="both"  # "camera", "mic", or "both"

# Load configuration
load_config() {
    SHORTCUT_ON="$DEFAULT_SHORTCUT_ON"
    SHORTCUT_OFF="$DEFAULT_SHORTCUT_OFF"
    ENABLE_DEBUG_LOGS="$DEFAULT_ENABLE_DEBUG_LOGS"
    DETECTION_MODE="$DEFAULT_DETECTION_MODE"

    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi
}

# Generate default config file
generate_default_config() {
    cat > "$CONFIG_FILE" <<'EOF'
# On Air Configuration
# Edit these values and restart: ./on-air.sh install

# =============================================================================
# SHORTCUTS
# =============================================================================
# Names must match exactly with shortcuts in the Shortcuts app

SHORTCUT_ON="On Air"
SHORTCUT_OFF="Off Air"

# =============================================================================
# DETECTION MODE
# =============================================================================
# Options:
#   "camera" - Only detect camera usage
#   "mic"    - Only detect microphone usage
#   "both"   - Detect either camera OR microphone (recommended)

DETECTION_MODE="both"

# =============================================================================
# DEBUG
# =============================================================================
# Set to true for verbose logging (useful for troubleshooting)

ENABLE_DEBUG_LOGS=false
EOF
}

load_config

# =============================================================================
# CONSTANTS
# =============================================================================

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
PLIST_NAME="com.onair"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"
LOG_DIR="$HOME/.onair"
LOG_FILE="$LOG_DIR/on-air.log"
STATE_FILE="$LOG_DIR/state"

# Ensure directories exist
mkdir -p "$LOG_DIR"

# =============================================================================
# LOGGING
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_quiet() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

log_debug() {
    if [[ "$ENABLE_DEBUG_LOGS" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $*" >> "$LOG_FILE"
    fi
}

# =============================================================================
# STATE TRACKING
# =============================================================================

CAMERA_ON=false
MIC_ON=false
LIGHT_STATE="off"

save_state() {
    cat > "$STATE_FILE" <<EOF
CAMERA_ON=$CAMERA_ON
MIC_ON=$MIC_ON
LIGHT_STATE=$LIGHT_STATE
EOF
}

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$STATE_FILE"
    fi
}

# =============================================================================
# LIGHT CONTROL
# =============================================================================

run_shortcut() {
    local shortcut_name="$1"
    # Use AppleScript for better reliability with HomeKit shortcuts
    osascript -e "tell application \"Shortcuts Events\" to run shortcut \"$shortcut_name\"" 2>/dev/null
}

update_light() {
    local should_be_on=false

    case "$DETECTION_MODE" in
        camera)
            [[ "$CAMERA_ON" == "true" ]] && should_be_on=true
            ;;
        mic)
            [[ "$MIC_ON" == "true" ]] && should_be_on=true
            ;;
        both|*)
            [[ "$CAMERA_ON" == "true" || "$MIC_ON" == "true" ]] && should_be_on=true
            ;;
    esac

    if [[ "$should_be_on" == "true" && "$LIGHT_STATE" != "on" ]]; then
        log "🔴 ON AIR (camera=$CAMERA_ON, mic=$MIC_ON)"
        if run_shortcut "$SHORTCUT_ON"; then
            LIGHT_STATE="on"
            save_state
        else
            log "ERROR: Failed to run shortcut '$SHORTCUT_ON'"
        fi
    elif [[ "$should_be_on" == "false" && "$LIGHT_STATE" != "off" ]]; then
        log "⚪ OFF AIR (camera=$CAMERA_ON, mic=$MIC_ON)"
        if run_shortcut "$SHORTCUT_OFF"; then
            LIGHT_STATE="off"
            save_state
        else
            log "ERROR: Failed to run shortcut '$SHORTCUT_OFF'"
        fi
    fi
}

# =============================================================================
# EVENT MONITORS
# =============================================================================

# Monitor camera events via macOS ControlCenter
# Fires when any app activates/deactivates camera hardware
monitor_camera() {
    log_debug "Camera monitor started"

    /usr/bin/log stream --predicate 'subsystem == "com.apple.controlcenter" and eventMessage contains "Frame publisher cameras"' 2>/dev/null | \
    while IFS= read -r line; do
        [[ "$line" =~ ^(Filtering|Timestamp|---) ]] && continue

        log_debug "Camera event: $line"

        if echo "$line" | grep -q "Frame publisher cameras changed to \[:"; then
            CAMERA_ON=false
            log "Camera OFF"
            update_light
        elif echo "$line" | grep -q "Frame publisher cameras changed to"; then
            CAMERA_ON=true
            log "Camera ON"
            update_light
        fi
    done
}

# Monitor microphone events via audiomxd
# Fires when any app starts/stops recording audio
monitor_mic() {
    log_debug "Microphone monitor started"

    /usr/bin/log stream --predicate 'process == "audiomxd" and (eventMessage contains "starting recording" or eventMessage contains "stopping recording")' 2>/dev/null | \
    while IFS= read -r line; do
        [[ "$line" =~ ^(Filtering|Timestamp|---) ]] && continue

        # Skip system processes
        if echo "$line" | grep -qE "corespeechd|Siri|SpeechRecognition|systemsound"; then
            log_debug "Ignoring system audio: $line"
            continue
        fi

        log_debug "Mic event: $line"

        if echo "$line" | grep -q "starting recording"; then
            local app_name
            app_name=$(echo "$line" | grep -oE "Chrome|Slack|Zoom|Teams|Meet|FaceTime|Discord|WebEx" | head -1 || echo "app")
            MIC_ON=true
            log "Microphone ON ($app_name)"
            update_light
        elif echo "$line" | grep -q "stopping recording"; then
            sleep 0.3  # Debounce rapid events
            MIC_ON=false
            log "Microphone OFF"
            update_light
        fi
    done
}

# Run both monitors in parallel
monitor_combined() {
    log "On Air v$VERSION started"
    log "Detection mode: $DETECTION_MODE"
    log "Shortcuts: ON='$SHORTCUT_ON', OFF='$SHORTCUT_OFF'"
    log "Monitoring for camera/mic events (0% CPU when idle)..."

    load_state

    monitor_camera &
    local camera_pid=$!

    monitor_mic &
    local mic_pid=$!

    trap 'kill $camera_pid $mic_pid 2>/dev/null; log "On Air stopped"; exit 0' SIGTERM SIGINT

    wait $camera_pid $mic_pid
}

# =============================================================================
# INSTALLATION
# =============================================================================

generate_plist() {
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ServiceDescription</key>
    <string>On Air - Busy light for video meetings</string>
    <key>ProgramArguments</key>
    <array>
        <string>${SCRIPT_PATH}</string>
        <string>monitor</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/stderr.log</string>
    <key>ThrottleInterval</key>
    <integer>5</integer>
</dict>
</plist>
EOF
}

check_requirements() {
    # Check macOS version
    local macos_version
    macos_version=$(sw_vers -productVersion | cut -d. -f1)
    if [[ "$macos_version" -lt 12 ]]; then
        echo "ERROR: On Air requires macOS 12 (Monterey) or later."
        echo "You have macOS $(sw_vers -productVersion)."
        return 1
    fi

    # Check shortcuts command
    if ! command -v shortcuts &> /dev/null; then
        echo "ERROR: 'shortcuts' command not found."
        echo "This should be available on macOS 12+."
        return 1
    fi

    return 0
}

install_agent() {
    echo ""
    echo "On Air v$VERSION Installer"
    echo "=========================="
    echo ""

    # Check requirements
    if ! check_requirements; then
        return 1
    fi

    # Generate config if needed
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Creating configuration file..."
        generate_default_config
    fi

    # Check shortcuts exist
    echo "Checking shortcuts..."
    local missing_shortcuts=false

    if ! shortcuts list 2>/dev/null | grep -q "^${SHORTCUT_ON}$"; then
        echo ""
        echo "ERROR: Shortcut '$SHORTCUT_ON' not found!"
        missing_shortcuts=true
    fi

    if ! shortcuts list 2>/dev/null | grep -q "^${SHORTCUT_OFF}$"; then
        echo ""
        echo "ERROR: Shortcut '$SHORTCUT_OFF' not found!"
        missing_shortcuts=true
    fi

    if [[ "$missing_shortcuts" == "true" ]]; then
        echo ""
        echo "Please create the missing shortcuts in the Shortcuts app:"
        echo ""
        echo "  1. Open Shortcuts app"
        echo "  2. Click '+' to create new shortcut"
        echo "  3. Name it exactly: $SHORTCUT_ON (or $SHORTCUT_OFF)"
        echo "  4. Add action: 'Control Home'"
        echo "  5. Select your switch and set to Turn On (or Turn Off)"
        echo "  6. Save and run this installer again"
        echo ""
        return 1
    fi

    echo "Shortcuts found!"

    # Test shortcuts
    echo "Testing shortcuts..."
    if ! run_shortcut "$SHORTCUT_ON"; then
        echo "WARNING: Could not run '$SHORTCUT_ON'. You may need to grant permissions."
    fi
    sleep 1
    run_shortcut "$SHORTCUT_OFF" 2>/dev/null || true

    # Unload existing
    if [[ -f "$PLIST_PATH" ]]; then
        echo "Removing existing installation..."
        launchctl unload "$PLIST_PATH" 2>/dev/null || true
    fi

    # Also remove old MeetingSignal if present
    if [[ -f "$HOME/Library/LaunchAgents/com.meetingsignal.plist" ]]; then
        echo "Removing old MeetingSignal installation..."
        launchctl unload "$HOME/Library/LaunchAgents/com.meetingsignal.plist" 2>/dev/null || true
        rm -f "$HOME/Library/LaunchAgents/com.meetingsignal.plist"
    fi

    # Install
    mkdir -p "$HOME/Library/LaunchAgents"
    echo "Installing LaunchAgent..."
    generate_plist > "$PLIST_PATH"

    echo "Starting On Air..."
    if launchctl load -w "$PLIST_PATH"; then
        sleep 2

        if launchctl list | grep -q "$PLIST_NAME"; then
            echo ""
            echo "============================================"
            echo " Installation complete!"
            echo "============================================"
            echo ""
            echo " 🔴 Your light will turn ON when:"
            case "$DETECTION_MODE" in
                camera) echo "    • Camera is activated" ;;
                mic)    echo "    • Microphone is activated" ;;
                both)   echo "    • Camera OR microphone is activated" ;;
            esac
            echo ""
            echo " Supported apps:"
            echo "    Zoom, Google Meet, Microsoft Teams, Slack,"
            echo "    FaceTime, Discord, WebEx, and any other app"
            echo ""
            echo " Commands:"
            echo "    ./on-air.sh status     Check status"
            echo "    ./on-air.sh test       Test shortcuts"
            echo "    ./on-air.sh uninstall  Remove"
            echo ""
            echo " Logs:"
            echo "    tail -f $LOG_FILE"
            echo ""
        else
            echo ""
            echo "WARNING: Service may not have started correctly."
            echo "Check: $LOG_DIR/stderr.log"
            return 1
        fi
    else
        echo "ERROR: Failed to load LaunchAgent"
        return 1
    fi
}

uninstall_agent() {
    echo ""
    echo "Uninstalling On Air..."

    if [[ -f "$PLIST_PATH" ]]; then
        launchctl unload "$PLIST_PATH" 2>/dev/null || true
        rm -f "$PLIST_PATH"
        echo "LaunchAgent removed."
    fi

    rm -f "$STATE_FILE"
    echo ""
    echo "On Air has been uninstalled."
    echo ""
    echo "Note: Configuration and logs preserved at:"
    echo "  $LOG_DIR"
    echo ""
    echo "To remove completely:"
    echo "  rm -rf $LOG_DIR"
    echo "  rm -f $CONFIG_FILE"
    echo ""
}

test_shortcuts() {
    echo ""
    echo "Testing shortcuts..."
    echo ""

    echo "1. Testing '$SHORTCUT_ON'..."
    if run_shortcut "$SHORTCUT_ON"; then
        echo "   ✓ Success - light should be ON"
    else
        echo "   ✗ Failed"
    fi

    sleep 2

    echo ""
    echo "2. Testing '$SHORTCUT_OFF'..."
    if run_shortcut "$SHORTCUT_OFF"; then
        echo "   ✓ Success - light should be OFF"
    else
        echo "   ✗ Failed"
    fi

    echo ""
    echo "Test complete."
    echo ""
}

show_status() {
    echo ""
    echo "On Air Status"
    echo "============="
    echo ""
    echo "Version: $VERSION"
    echo ""

    if launchctl list 2>/dev/null | grep -q "$PLIST_NAME"; then
        echo "Service: RUNNING"
    else
        echo "Service: STOPPED"
    fi

    echo "Detection: $DETECTION_MODE"
    echo ""

    if [[ -f "$STATE_FILE" ]]; then
        echo "Current State:"
        sed 's/^/  /' "$STATE_FILE"
        echo ""
    fi

    echo "Recent Activity:"
    if [[ -f "$LOG_FILE" ]]; then
        tail -8 "$LOG_FILE" | sed 's/^/  /'
    else
        echo "  (no logs yet)"
    fi
    echo ""
}

usage() {
    cat <<EOF

On Air v$VERSION - Automatic busy light for video meetings

Usage: $0 <command>

Commands:
    install     Install and start On Air
    uninstall   Stop and remove On Air
    status      Show current status and recent logs
    test        Test that shortcuts work correctly
    on          Manually turn light on
    off         Manually turn light off
    logs        Show live log stream
    help        Show this help message

Configuration:
    $CONFIG_FILE

Logs:
    $LOG_FILE

Documentation:
    https://github.com/UtkarshJain98/OnAir

EOF
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local command="${1:-}"

    case "$command" in
        install)
            install_agent
            ;;
        uninstall)
            uninstall_agent
            ;;
        monitor)
            monitor_combined
            ;;
        test)
            test_shortcuts
            ;;
        status)
            show_status
            ;;
        on)
            run_shortcut "$SHORTCUT_ON"
            echo "🔴 ON AIR"
            ;;
        off)
            run_shortcut "$SHORTCUT_OFF"
            echo "⚪ Off Air"
            ;;
        logs)
            tail -f "$LOG_FILE"
            ;;
        -h|--help|help)
            usage
            ;;
        -v|--version)
            echo "On Air v$VERSION"
            ;;
        "")
            usage
            ;;
        *)
            echo "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
