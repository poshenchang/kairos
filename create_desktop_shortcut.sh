#!/bin/bash
# create_desktop_shortcut.sh
# Creates a Linux desktop app shortcut for Kairos in your app menu.

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
APP_DIR="$HOME/.local/share/applications"
mkdir -p "$APP_DIR"

echo "🔨 Building Kairos release bundle..."
flutter build linux --release

EXEC_PATH="$DIR/build/linux/x64/release/bundle/kairos"

cat <<EOF > "$APP_DIR/kairos.desktop"
[Desktop Entry]
Name=Kairos
Comment=Student Smart Calendar, Habits & Auto-Scheduler
Exec=$EXEC_PATH
Icon=appointment-soon
Terminal=false
Type=Application
Categories=Office;Calendar;Utility;
StartupWMClass=kairos
EOF

chmod +x "$APP_DIR/kairos.desktop"
update-desktop-database "$APP_DIR" 2>/dev/null || true

echo "✅ Success! 'Kairos' is now in your Linux Application Menu / Taskbar search."

