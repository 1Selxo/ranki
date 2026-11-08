#!/bin/sh

BASE="/mnt/us/extensions/ranki"
CONF="$BASE/config.ini"

if [ -f /lib/ld-linux-armhf.so.3 ] || [ -f /usr/lib/ld-linux-armhf.so.3 ]; then
    ARCH="armhf"
    OFFSET=$((0x204484))
else
    ARCH="armel"
    OFFSET=$((0x21d0ec))
fi

BIN="$BASE/ranki-$ARCH"

if [ ! -f "$BIN" ]; then
    if [ "$ARCH" = "armhf" ] && [ -f "$BASE/ranki-armel" ]; then
        ARCH="armel"
        OFFSET=$((0x21d0ec))
        BIN="$BASE/ranki-$ARCH"
    elif [ "$ARCH" = "armel" ] && [ -f "$BASE/ranki-armhf" ]; then
        ARCH="armhf"
        OFFSET=$((0x204484))
        BIN="$BASE/ranki-$ARCH"
    fi
fi

if [ ! -f "$BIN" ]; then
    eips 1 1 "RAnki: Binary not found" 2>/dev/null
    exit 1
fi

if grep -qi "sync_media=false" "$CONF" 2>/dev/null; then
    sed -i 's/sync_media=false/sync_media=true/gI' "$CONF"
    printf '\x01\x27' | dd of="$BIN" bs=1 seek=$OFFSET conv=notrunc 2>/dev/null
    eips 1 1 "RAnki: Media sync ENABLED" 2>/dev/null
else
    if grep -qi "sync_media=" "$CONF" 2>/dev/null; then
        sed -i 's/sync_media=true/sync_media=false/gI' "$CONF"
    else
        sed -i '/\[General\]/a sync_media=false' "$CONF"
    fi
    printf '\x00\x27' | dd of="$BIN" bs=1 seek=$OFFSET conv=notrunc 2>/dev/null
    eips 1 1 "RAnki: Media sync DISABLED" 2>/dev/null
fi
