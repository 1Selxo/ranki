#!/bin/sh

BASE="/mnt/us/extensions/ranki"
LOG="$BASE/ranki.log"

# Log everything to ranki.log
exec > "$LOG" 2>&1

echo "=========================================="
echo "Starting Ranki on Kindle Touch 4th Gen"
echo "Date: $(date)"
echo "Uname: $(uname -a)"
echo "=========================================="

# Immediate on-screen feedback
eips 1 1 "Starting Ranki..." 2>/dev/null

# Determine architecture
if [ -f /lib/ld-linux-armhf.so.3 ]; then
    ARCH="armhf"
else
    ARCH="armel"
fi
echo "Architecture: $ARCH"

# Create local lib directory for compatibility symlinks
mkdir -p "$BASE/lib"

# Check and symlink WebKitGTK library if needed
if [ ! -f /usr/lib/libwebkitgtk-1.0.so ]; then
    if [ -f /usr/lib/libwebkitgtk-1.0.so.0 ]; then
        echo "Symlinking /usr/lib/libwebkitgtk-1.0.so.0 -> $BASE/lib/libwebkitgtk-1.0.so"
        ln -sf /usr/lib/libwebkitgtk-1.0.so.0 "$BASE/lib/libwebkitgtk-1.0.so"
    elif [ -f /usr/lib/libwebkit-1.0.so ]; then
        echo "Symlinking /usr/lib/libwebkit-1.0.so -> $BASE/lib/libwebkitgtk-1.0.so"
        ln -sf /usr/lib/libwebkit-1.0.so "$BASE/lib/libwebkitgtk-1.0.so"
    fi
fi

# Set essential GTK / X11 / Library environment variables
export DISPLAY=":0"
export HOME="/mnt/us"
export LD_LIBRARY_PATH="$BASE/lib:$BASE:/usr/lib:/lib"

if [ -f "$BASE/libk5compat.so" ]; then
    echo "Using compatibility shim: $BASE/libk5compat.so"
    export LD_PRELOAD="$BASE/libk5compat.so"
else
    echo "WARNING: libk5compat.so not found!"
fi

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
    eips 1 2 "Ranki error ($EXIT_CODE). Check ranki.log" 2>/dev/null
fi

exit $EXIT_CODE
