#!/bin/sh

BASE="/mnt/us/extensions/ranki"
CONF="$BASE/config.ini"
BIN="$BASE/ranki-armel"

if grep -qi "sync_media=false" "$CONF" 2>/dev/null; then
    sed -i 's/sync_media=false/sync_media=true/gI' "$CONF"
    printf '\x01\x27' | dd of="$BIN" bs=1 seek=$((0x21d0ec)) conv=notrunc 2>/dev/null
    eips 1 1 "RAnki: Media sync ENABLED" 2>/dev/null
else
    if grep -qi "sync_media=" "$CONF" 2>/dev/null; then
        sed -i 's/sync_media=true/sync_media=false/gI' "$CONF"
    else
        sed -i '/\[General\]/a sync_media=false' "$CONF"
    fi
    printf '\x00\x27' | dd of="$BIN" bs=1 seek=$((0x21d0ec)) conv=notrunc 2>/dev/null
    eips 1 1 "RAnki: Media sync DISABLED" 2>/dev/null
fi
