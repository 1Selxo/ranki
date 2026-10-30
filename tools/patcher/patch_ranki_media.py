import sys
import xml.etree.ElementTree as ET
import re

def patch_binary(path):
    print(f"Patching {path}...")
    with open(path, "rb") as f:
        data = bytearray(f.read())

    # 1. Patch instructions:
    # 0x0022d0ec: offset in file = 0x21d0ec
    # 0x0022d0fa: offset in file = 0x21d0fa
    # Check original bytes:
    # At 0x21d0ea: 67 61 01 27 a7 61 ...
    # At 0x21d0fa: 39 46 (mov r1, r7)
    assert data[0x21d0fa:0x21d0fc] == b"\x39\x46", f"Expected 39 46 at 0x21d0fa, got {data[0x21d0fa:0x21d0fc].hex()}"
    # Change to movs r1, #1 (01 21)
    data[0x21d0fa:0x21d0fc] = b"\x01\x21"
    print("  Patched instruction at 0x21d0fa to movs r1, #1 (01 21)")

    # 2. Patch XML template in rodata:
    p = data.find(b"Custom sync server")
    xml_start = data.rfind(b"<interface>", 0, p)
    xml_end = data.find(b"</interface>", p) + len(b"</interface>")
    orig_xml = data[xml_start:xml_end].decode("utf-8")
    print(f"  Found Settings XML at 0x{xml_start:x}-0x{xml_end:x}, len: {len(orig_xml)}")

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
