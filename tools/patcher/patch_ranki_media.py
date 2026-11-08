import sys
import xml.etree.ElementTree as ET
import re

def patch_binary(path):
    print(f"Patching {path}...")
    with open(path, "rb") as f:
        data = bytearray(f.read())

    # 1. Patch instructions:
    # Look for the sync_media instruction sequence: 67 61 01 27 a7 61
    pattern = bytes.fromhex("67610127a761")
    pos = data.find(pattern)
    if pos == -1:
        pattern_off = bytes.fromhex("67610027a761")
        pos = data.find(pattern_off)
    assert pos != -1, f"Could not find sync_media instruction pattern in {path}"

    offset_3946 = pos + 16
    assert data[offset_3946:offset_3946+2] in (b"\x39\x46", b"\x01\x21"), (
        f"Expected 39 46 at offset 0x{offset_3946:x}, got {data[offset_3946:offset_3946+2].hex()}"
    )
    if data[offset_3946:offset_3946+2] == b"\x39\x46":
        data[offset_3946:offset_3946+2] = b"\x01\x21"
        print(f"  Patched instruction at 0x{offset_3946:x} to movs r1, #1 (01 21)")
    else:
        print(f"  Instruction at 0x{offset_3946:x} already patched to 01 21")

    # 2. Patch XML template in rodata:
    p = data.find(b"Custom sync server")
    if p != -1:
        xml_start = data.rfind(b"<interface>", 0, p)
        xml_end = data.find(b"</interface>", p) + len(b"</interface>")
        orig_xml = data[xml_start:xml_end].decode("utf-8")
        print(f"  Found Settings XML at 0x{xml_start:x}-0x{xml_end:x}, len: {len(orig_xml)}")

        if "sync_media_toggle" in orig_xml:
            print("  XML template already contains sync_media_toggle")
        else:
            toggle_snippet = (
                '\n    <child>'
                '\n      <object class="InkRowToggleButton" id="sync_media_toggle">'
                '\n        <property name="label">Sync media</property>'
                '\n        <property name="description">download images &amp; audio</property>'
                '\n      </object>'
                '\n      <packing>'
                '\n        <property name="expand">False</property>'
                '\n        <property name="fill">False</property>'
                '\n      </packing>'
                '\n    </child>\n'
            )

            target = 'id="hbox2"'
            idx = orig_xml.find(target)
            child_idx = orig_xml.rfind("<child>", 0, idx)

            new_xml = orig_xml[:child_idx] + toggle_snippet + orig_xml[child_idx:]
            diff = len(new_xml) - len(orig_xml)

            # Absorb excess spaces from indentation
            while diff > 0:
                m = re.search(r'   +', new_xml)
                if not m:
                    break
                remove = min(diff, len(m.group(0)) - 1)
                new_xml = new_xml[:m.start()] + ' ' + new_xml[m.start() + remove + 1:]
                diff -= remove

            assert len(new_xml) == len(orig_xml), f"Length mismatch: {len(new_xml)} != {len(orig_xml)}"
            # Verify XML parses
            ET.fromstring(new_xml)
            print("  Validated modified XML with ElementTree successfully")

            data[xml_start:xml_end] = new_xml.encode("utf-8")
            print("  Patched XML template in rodata successfully")

    with open(path, "wb") as f:
        f.write(data)
    print(f"Done patching {path}!")

if __name__ == "__main__":
    for p in sys.argv[1:]:
        patch_binary(p)
