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

# Ensure local lib directory exists
mkdir -p "$BASE/lib"

# Check and symlink system liblipc if available, else our bundled liblipc.so.1 in $BASE/lib is used
for lipc_candidate in /usr/lib/liblipc.so /usr/lib/liblipc.so.0 /lib/liblipc.so /opt/amazon/ebook/lib/liblipc.so; do
    if [ -f "$lipc_candidate" ]; then
        echo "Found system lipc at $lipc_candidate -> symlinking to $BASE/lib/liblipc.so.1"
        ln -sf "$lipc_candidate" "$BASE/lib/liblipc.so.1"
        break
    fi
done

# If no system lipc was symlinked, ensure our bundled liblipc.so.1 is present in $BASE/lib/
if [ ! -f "$BASE/lib/liblipc.so.1" ]; then
    if [ -f "$BASE/liblipc.so.1" ]; then
        cp -f "$BASE/liblipc.so.1" "$BASE/lib/liblipc.so.1"
    fi
fi

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
    eips 1 2 "Ranki exited ($EXIT_CODE). Check ranki.log" 2>/dev/null
fi

exit $EXIT_CODE
