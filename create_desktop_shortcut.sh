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

# Must match APPLICATION_ID in linux/CMakeLists.txt: on Wayland, GNOME matches
# windows to launchers by app ID, so the .desktop file has to carry that name.
APP_ID="com.kairos.kairos"

echo "🎨 Installing app icon..."
ICON_SRC="$DIR/assets/icon/app_icon_linux.png"
ICON_ROOT="$HOME/.local/share/icons/hicolor"
for SIZE in 48 64 128 256 512; do
  mkdir -p "$ICON_ROOT/${SIZE}x${SIZE}/apps"
  if command -v magick >/dev/null 2>&1; then
    magick "$ICON_SRC" -resize "${SIZE}x${SIZE}" "$ICON_ROOT/${SIZE}x${SIZE}/apps/kairos.png"
  else
    cp "$ICON_SRC" "$ICON_ROOT/${SIZE}x${SIZE}/apps/kairos.png"
  fi
done
gtk-update-icon-cache -f -t "$ICON_ROOT" 2>/dev/null || true

# Remove the launcher created by older versions of this script
rm -f "$APP_DIR/kairos.desktop"

cat <<EOF > "$APP_DIR/$APP_ID.desktop"
[Desktop Entry]
Name=Kairos
Comment=Student Smart Calendar, Habits & Auto-Scheduler
Exec=$EXEC_PATH
Icon=kairos
Terminal=false
Type=Application
Categories=Office;Calendar;Utility;
StartupWMClass=$APP_ID
EOF

chmod +x "$APP_DIR/$APP_ID.desktop"
update-desktop-database "$APP_DIR" 2>/dev/null || true
# KDE Plasma's taskbar resolves launchers/icons from its own cache, not the desktop database
if command -v kbuildsycoca6 >/dev/null 2>&1; then
  kbuildsycoca6 >/dev/null 2>&1 || true
  rm -f "$HOME/.cache/icon-cache.kcache"
fi

echo "✅ Success! 'Kairos' is now in your Linux Application Menu / Taskbar search."

