#!/bin/bash
# Grand Unified AI Home Lab - Command Center Desktop Icon Installer
# Installs a desktop shortcut that launches node-a-command-center.js
# and opens the Command Center in the browser.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SCRIPT="$SCRIPT_DIR/node-a-command-center.js"
PORT="${COMMAND_CENTER_PORT:-3099}"

LAUNCHER_DIR="$HOME/.local/share/node-a-command-center"
LAUNCHER_SCRIPT="$LAUNCHER_DIR/launch.sh"
ICON_SRC="$SCRIPT_DIR/command-center.png"
DESKTOP_FILE_NAME="node-a-command-center.desktop"
APPS_DIR="$HOME/.local/share/applications"
DESKTOP_DIR="$HOME/Desktop"

# Verify node-a-command-center.js is present
if [ ! -f "$APP_SCRIPT" ]; then
    echo "ERROR: Cannot find $APP_SCRIPT" >&2
    exit 1
fi

# Verify node is available
if ! command -v node >/dev/null 2>&1; then
    echo "ERROR: 'node' is not installed or not on PATH." >&2
    exit 1
fi

echo "Installing Command Center desktop icon..."

# Create launcher directory
mkdir -p "$LAUNCHER_DIR"
mkdir -p "$APPS_DIR"

# Write the launcher script that starts the server and opens the browser
cat > "$LAUNCHER_SCRIPT" <<'LAUNCHER'
#!/bin/bash
# Launch node-a-command-center and open the browser

PORT="${COMMAND_CENTER_PORT:-3099}"

# Resolve the directory containing this launcher
LAUNCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo's node-a-command-center directory is two levels up from
# ~/.local/share/node-a-command-center, but we store the real path at
# install time so this script is self-contained.
APP_SCRIPT="__APP_SCRIPT__"

# Returns 0 if something is already listening on PORT, 1 otherwise
port_in_use() {
    ss -ltn 2>/dev/null | grep -qE ":${PORT}([^0-9]|$)" ||
    netstat -ltn 2>/dev/null | grep -qE ":${PORT}([^0-9]|$)"
}

# Start the server in the background if it is not already running on that port
if ! port_in_use; then
    cd "$(dirname "$APP_SCRIPT")"
    nohup node "$APP_SCRIPT" >"$HOME/.local/share/node-a-command-center/server.log" 2>&1 &
    echo "Server starting on port $PORT (PID $!)..."
    # Wait up to 10 seconds for the server to be ready
    for _ in $(seq 1 20); do
        sleep 0.5
        if port_in_use; then
            break
        fi
    done
else
    echo "Server already running on port $PORT."
fi

# Open the Command Center in the default browser
URL="http://localhost:${PORT}"
if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL"
elif command -v gnome-open >/dev/null 2>&1; then
    gnome-open "$URL"
elif command -v kde-open >/dev/null 2>&1; then
    kde-open "$URL"
else
    echo "Could not detect a browser opener. Open $URL manually."
fi
LAUNCHER

# Substitute the real app script path
sed -i "s|__APP_SCRIPT__|$APP_SCRIPT|g" "$LAUNCHER_SCRIPT"
chmod +x "$LAUNCHER_SCRIPT"

# Determine icon path (use bundled PNG if present, otherwise fall back to a
# standard system icon so the .desktop file is always valid)
if [ -f "$ICON_SRC" ]; then
    ICON_PATH="$ICON_SRC"
else
    ICON_PATH="utilities-terminal"
fi

# Write the .desktop file
DESKTOP_CONTENT="[Desktop Entry]
Version=1.0
Type=Application
Name=AI Command Center
Comment=Launch the Grand Unified AI Home Lab Command Center
Exec=$LAUNCHER_SCRIPT
Icon=$ICON_PATH
Terminal=false
Categories=Network;Development;
StartupNotify=true
"

APPS_DESKTOP="$APPS_DIR/$DESKTOP_FILE_NAME"
echo "$DESKTOP_CONTENT" > "$APPS_DESKTOP"
chmod +x "$APPS_DESKTOP"

echo "  ✓ Application entry: $APPS_DESKTOP"

# Also place a copy on the Desktop if that directory exists
if [ -d "$DESKTOP_DIR" ]; then
    cp "$APPS_DESKTOP" "$DESKTOP_DIR/$DESKTOP_FILE_NAME"
    chmod +x "$DESKTOP_DIR/$DESKTOP_FILE_NAME"
    # Mark it as trusted on GNOME desktops (if gio is available)
    if command -v gio >/dev/null 2>&1; then
        gio set "$DESKTOP_DIR/$DESKTOP_FILE_NAME" metadata::trusted true 2>/dev/null || true
    fi
    echo "  ✓ Desktop shortcut:  $DESKTOP_DIR/$DESKTOP_FILE_NAME"
fi

# Refresh the desktop database so the icon appears immediately
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
fi

echo ""
echo "Installation complete!"
echo "  Command Center will be available at: http://localhost:${PORT}"
echo "  Server log: $LAUNCHER_DIR/server.log"
echo ""
echo "To launch manually: $LAUNCHER_SCRIPT"
