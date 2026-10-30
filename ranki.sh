#!/bin/sh

BASE="/mnt/us/extensions/ranki"
LOG="$BASE/ranki.log"

exec > "$LOG" 2>&1

echo "=========================================="
echo "Starting Ranki on Kindle Touch 4th Gen"
echo "Date: $(date)"
echo "Uname: $(uname -a)"
echo "=========================================="

# Immediate on-screen feedback
eips 1 1 "Starting Ranki..." 2>/dev/null

ARCH="armel"

# Create a clean tmpfs directory for libraries and symlinks (FAT32 on /mnt/us does not support symlinks)
TMPLIB="/var/tmp/ranki-lib"
rm -rf "$TMPLIB" 2>/dev/null
mkdir -p "$TMPLIB"

# Copy our bundled compatibility shims into tmpfs
cp -f "$BASE/libk5compat.so" "$TMPLIB/libk5compat.so" 2>/dev/null
cp -f "$BASE/liblipc.so.1" "$TMPLIB/liblipc.so.1" 2>/dev/null
cp -f "$BASE/libcurl.so.4" "$TMPLIB/libcurl.so.4" 2>/dev/null

# Check and symlink system WebKitGTK into tmpfs
for f in /usr/lib/libwebkitgtk-1.0.so* /usr/lib/libwebkit-1.0.so* /lib/libwebkitgtk-1.0.so*; do
    if [ -f "$f" ]; then
        echo "Found system WebKit: $f -> symlinking to $TMPLIB/libwebkitgtk-1.0.so"
        ln -sf "$f" "$TMPLIB/libwebkitgtk-1.0.so"
        break
    fi
done

# If system liblipc exists, symlink it so native IPC works
for f in /usr/lib/liblipc.so /usr/lib/liblipc.so.0 /lib/liblipc.so; do
    if [ -f "$f" ]; then
        echo "Found system LIPC: $f -> symlinking to $TMPLIB/liblipc.so.1"
        ln -sf "$f" "$TMPLIB/liblipc.so.1"
        break
    fi
done

# If system libcurl exists, symlink it
for f in /usr/lib/libcurl.so* /lib/libcurl.so*; do
    if [ -f "$f" ]; then
        echo "Found system libcurl: $f -> symlinking to $TMPLIB/libcurl.so.4"
        ln -sf "$f" "$TMPLIB/libcurl.so.4"
        break
    fi
done

# Set essential GTK / X11 / Library environment variables
export DISPLAY=":0"
export HOME="/mnt/us"
export LD_LIBRARY_PATH="$TMPLIB:$BASE/lib:$BASE:/usr/lib:/lib"
export LD_PRELOAD="$TMPLIB/libk5compat.so"

echo "=== Configured Libraries in $TMPLIB ==="
ls -l "$TMPLIB"

echo "=== Dynamic Linking Check ==="
if [ -x /lib/ld-linux.so.3 ]; then
    /lib/ld-linux.so.3 --list "$BASE/ranki-$ARCH"
fi

# Prevent screensaver while reviewing
lipc-set-prop -i com.lab126.powerd preventScreenSaver 1 2>/dev/null

echo "=== Launching $BASE/ranki-$ARCH ==="
cd "$BASE"
"$BASE/ranki-$ARCH" "$@"
EXIT_CODE=$?

echo "=== Ranki exited with code: $EXIT_CODE ==="

# Re-enable screensaver
lipc-set-prop -i com.lab126.powerd preventScreenSaver 0 2>/dev/null

if [ $EXIT_CODE -ne 0 ]; then
    eips 1 2 "Ranki exited ($EXIT_CODE). Check ranki.log" 2>/dev/null
fi

exit $EXIT_CODE
