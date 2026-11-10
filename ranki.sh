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

ARMEL_LOADER="/lib/ld-linux.so.3"
ARMHF_LOADER="/lib/ld-linux-armhf.so.3"

echo "=== ARM Binary / Loader Check ==="
if [ -x "$ARMEL_LOADER" ]; then
    echo "Found ARMEL loader: $ARMEL_LOADER"
else
    echo "ARMEL loader unavailable: $ARMEL_LOADER"
fi
if [ -x "$ARMHF_LOADER" ]; then
    echo "Found ARMHF loader: $ARMHF_LOADER"
else
    echo "ARMHF loader unavailable: $ARMHF_LOADER"
fi

if [ -x "$ARMEL_LOADER" ] && [ -f "$BASE/ranki-armel" ]; then
    ARCH="armel"
    LOADER="$ARMEL_LOADER"
elif [ -x "$ARMHF_LOADER" ] && [ -f "$BASE/ranki-armhf" ]; then
    ARCH="armhf"
    LOADER="$ARMHF_LOADER"
else
    echo "ERROR: No Ranki binary matches an executable Kindle ARM loader."
    echo "Expected ranki-armel with $ARMEL_LOADER or ranki-armhf with $ARMHF_LOADER."
    eips 1 2 "No compatible Ranki binary. Check ranki.log" 2>/dev/null
    exit 1
fi
echo "Selected Ranki binary: ranki-$ARCH ($LOADER)"

# The media-sync binary patch is specific to the ARMEL build.
if grep -qi "sync_media=false" "$BASE/config.ini" 2>/dev/null; then
    echo "Media sync: DISABLED (sync_media=false in config.ini)"
    if [ "$ARCH" = "armel" ]; then
        printf '\x00\x27' | dd of="$BASE/ranki-armel" bs=1 seek=$((0x21d0ec)) conv=notrunc 2>/dev/null
    else
        echo "WARNING: Media sync setting is not applied to the ARMHF binary."
    fi
else
    echo "Media sync: ENABLED (sync_media=true in config.ini)"
    if [ "$ARCH" = "armel" ]; then
        printf '\x01\x27' | dd of="$BASE/ranki-armel" bs=1 seek=$((0x21d0ec)) conv=notrunc 2>/dev/null
    fi
fi

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

echo "=== Configured Libraries in $TMPLIB ==="
ls -l "$TMPLIB"

echo "=== Dynamic Linking Check ==="
"$LOADER" --list "$BASE/ranki-$ARCH"
LINK_CHECK_EXIT=$?
if [ $LINK_CHECK_EXIT -ne 0 ]; then
    echo "WARNING: Dynamic linking check exited with code $LINK_CHECK_EXIT."
fi

echo "=== System Keyboard LIPC Diagnostic ==="
lipc-probe com.lab126.keyboard 2>&1

# Prevent screensaver while reviewing
lipc-set-prop -i com.lab126.powerd preventScreenSaver 1 2>/dev/null

echo "=== Launching $BASE/ranki-$ARCH ==="
cd "$BASE"
if [ "$ARCH" = "armel" ]; then
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
