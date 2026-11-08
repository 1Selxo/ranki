#!/bin/sh

BASE="/mnt/us/extensions/ranki"
LOG="$BASE/ranki.log"

exec > "$LOG" 2>&1

# Determine architecture: ARMHF (modern Kindles like PW2+, KT2+, Oasis) vs ARMEL (Kindle Touch 5.3.7.3, K4)
if [ -f /lib/ld-linux-armhf.so.3 ] || [ -f /usr/lib/ld-linux-armhf.so.3 ]; then
    ARCH="armhf"
    SYNC_MEDIA_OFFSET=$((0x204484))
else
    ARCH="armel"
    SYNC_MEDIA_OFFSET=$((0x21d0ec))
fi

# Fallback check if detected architecture binary is missing but the other exists
if [ ! -f "$BASE/ranki-$ARCH" ]; then
    if [ "$ARCH" = "armhf" ] && [ -f "$BASE/ranki-armel" ]; then
        ARCH="armel"
        SYNC_MEDIA_OFFSET=$((0x21d0ec))
    elif [ "$ARCH" = "armel" ] && [ -f "$BASE/ranki-armhf" ]; then
        ARCH="armhf"
        SYNC_MEDIA_OFFSET=$((0x204484))
    fi
fi

echo "=========================================="
echo "Starting Ranki ($ARCH)"
echo "Date: $(date)"
echo "Uname: $(uname -a)"
echo "=========================================="

# Immediate on-screen feedback
eips 1 1 "Starting Ranki..." 2>/dev/null

if [ ! -f "$BASE/ranki-$ARCH" ]; then
    echo "FATAL: Binary $BASE/ranki-$ARCH not found!"
    eips 1 2 "Ranki binary not found ($ARCH)" 2>/dev/null
    exit 127
fi

# Ensure executable permissions
chmod +x "$BASE/ranki-$ARCH" 2>/dev/null

# Apply sync_media setting from config.ini to ranki binary before launch
if grep -qi "sync_media=false" "$BASE/config.ini" 2>/dev/null; then
    echo "Media sync: DISABLED (sync_media=false in config.ini)"
    printf '\x00\x27' | dd of="$BASE/ranki-$ARCH" bs=1 seek=$SYNC_MEDIA_OFFSET conv=notrunc 2>/dev/null
else
    echo "Media sync: ENABLED (sync_media=true in config.ini)"
    printf '\x01\x27' | dd of="$BASE/ranki-$ARCH" bs=1 seek=$SYNC_MEDIA_OFFSET conv=notrunc 2>/dev/null
fi

# Create a clean tmpfs directory for libraries and symlinks (FAT32 on /mnt/us does not support symlinks)
TMPLIB="/var/tmp/ranki-lib"
rm -rf "$TMPLIB" 2>/dev/null
mkdir -p "$TMPLIB"

# For legacy ARMEL devices (Kindle Touch 5.3.7.3), copy bundled compatibility shims
if [ "$ARCH" = "armel" ]; then
    cp -f "$BASE/libk5compat.so" "$TMPLIB/libk5compat.so" 2>/dev/null
    cp -f "$BASE/liblipc.so.1" "$TMPLIB/liblipc.so.1" 2>/dev/null
    cp -f "$BASE/libcurl.so.4" "$TMPLIB/libcurl.so.4" 2>/dev/null
fi

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

echo "=== Configured Libraries in $TMPLIB ==="
ls -l "$TMPLIB"

echo "=== Dynamic Linking Check ==="
if [ "$ARCH" = "armhf" ] && [ -x /lib/ld-linux-armhf.so.3 ]; then
    /lib/ld-linux-armhf.so.3 --list "$BASE/ranki-$ARCH"
elif [ -x /lib/ld-linux.so.3 ]; then
    /lib/ld-linux.so.3 --list "$BASE/ranki-$ARCH"
fi

echo "=== System Keyboard LIPC Diagnostic ==="
lipc-probe com.lab126.keyboard 2>&1

# Prevent screensaver while reviewing
lipc-set-prop -i com.lab126.powerd preventScreenSaver 1 2>/dev/null

echo "=== Launching $BASE/ranki-$ARCH ==="
cd "$BASE"
if [ "$ARCH" = "armel" ] && [ -f "$TMPLIB/libk5compat.so" ]; then
    LD_PRELOAD="$TMPLIB/libk5compat.so" "$BASE/ranki-$ARCH" "$@"
else
    "$BASE/ranki-$ARCH" "$@"
fi
EXIT_CODE=$?

echo "=== Ranki exited with code: $EXIT_CODE ==="

# Re-enable screensaver
lipc-set-prop -i com.lab126.powerd preventScreenSaver 0 2>/dev/null

if [ $EXIT_CODE -ne 0 ]; then
    eips 1 2 "Ranki exited ($EXIT_CODE). Check ranki.log" 2>/dev/null
fi

exit $EXIT_CODE
