#!/bin/bash

set -euo pipefail

VOLUME_NAME="${1:?volume name is required}"
MOUNT_POINT="${2:?mount point is required}"
BACKGROUND_SOURCE="${3:?background source is required}"

BACKGROUND_DIR="${MOUNT_POINT}/.background"
BACKGROUND_NAME="dmg-background.png"
BACKGROUND_PATH="${BACKGROUND_DIR}/${BACKGROUND_NAME}"

mkdir -p "${BACKGROUND_DIR}"
cp "${BACKGROUND_SOURCE}" "${BACKGROUND_PATH}"
chflags hidden "${BACKGROUND_DIR}" || true
chflags hidden "${BACKGROUND_PATH}" || true

osascript <<EOF
tell application "Finder"
    set dmgFolder to POSIX file "${MOUNT_POINT}" as alias
    open dmgFolder
    delay 1

    set containerWindow to front Finder window
    set target of containerWindow to dmgFolder
    set current view of containerWindow to icon view
    set toolbar visible of containerWindow to false
    set statusbar visible of containerWindow to false
    set bounds of containerWindow to {120, 140, 840, 600}

    set iconOptions to the icon view options of containerWindow
    set arrangement of iconOptions to not arranged
    set icon size of iconOptions to 128
    set text size of iconOptions to 13
    set background picture of iconOptions to file ".background:${BACKGROUND_NAME}"

    set position of item "Crona.app" of containerWindow to {170, 235}
    set position of item "Applications" of containerWindow to {530, 235}

    close containerWindow
    open dmgFolder
    update without registering applications
    delay 2
end tell
EOF
