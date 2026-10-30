#!/usr/bin/env python3
"""
patch_glibc.py - Patch ARM ELF binaries to run on legacy glibc (glibc 2.12 on Kindle Touch 5.3.7.3)

Specifically:
- Unlinks Vernaux entries for GLIBC > 2.12 from libc.so.6 in .gnu.version_r
- Changes the versym entries for the affected symbols in .gnu.version to 1 (unversioned global)
"""

import sys
import struct
import os

def patch_binary(src_path: str, dst_path: str, target_versions=('GLIBC_2.15', 'GLIBC_2.16', 'GLIBC_2.17', 'GLIBC_2.18')):
    with open(src_path, 'rb') as f:
        data = bytearray(f.read())

    magic = data[:4]
    if magic != b'\x7fELF':
        raise ValueError("Not an ELF binary")
    if data[4] != 1:
        raise ValueError("Expected 32-bit ELF")

    e_shoff = struct.unpack('<I', data[32:36])[0]
    e_shentsize = struct.unpack('<H', data[46:48])[0]
    e_shnum = struct.unpack('<H', data[48:50])[0]
    e_shstrndx = struct.unpack('<H', data[50:52])[0]
    shstr_offset = struct.unpack('<I', data[e_shoff + e_shstrndx*e_shentsize + 16 : e_shoff + e_shstrndx*e_shentsize + 20])[0]

    sec_list = {}
    for i in range(e_shnum):
        sec = data[e_shoff + i*e_shentsize : e_shoff + (i+1)*e_shentsize]
        sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size, sh_link, sh_info = struct.unpack('<IIIIIIII', sec[:32])
        name_end = data.find(b'\x00', shstr_offset + sh_name)
        sec_name = data[shstr_offset + sh_name:name_end].decode('latin1', 'replace')
        sec_list[sec_name] = (sh_offset, sh_size, sh_link, sh_info)

    if '.gnu.version_r' not in sec_list:
        print("No .gnu.version_r section found; skipping version unlinking.")
        with open(dst_path, 'wb') as f:
            f.write(data)
        return

    v_off, v_size, v_link, v_num = sec_list['.gnu.version_r']
    dynstr_off = sec_list['.dynstr'][0]
    versym_off, versym_sz, _, _ = sec_list['.gnu.version']
    dynsym_off, dynsym_sz, _, _ = sec_list['.dynsym']

    # Discover target version indices
    target_indices = set()
    pos = v_off
    for i in range(v_num):
        vn_version, vn_cnt, vn_file, vn_aux, vn_next = struct.unpack('<HHIII', data[pos:pos+16])
        file_end = data.find(b'\x00', dynstr_off + vn_file)
        filename = data[dynstr_off + vn_file : file_end].decode()
        if filename == 'libc.so.6':
            aux_pos = pos + vn_aux
            for j in range(vn_cnt):
                vna_hash, vna_flags, vna_other, vna_name, vna_next = struct.unpack('<IHHI I', data[aux_pos:aux_pos+16])
                name_end = data.find(b'\x00', dynstr_off + vna_name)
                ver_name = data[dynstr_off + vna_name : name_end].decode()
                if ver_name in target_versions:
                    target_indices.add(vna_other)
                    print(f"Targeting {ver_name} (index {vna_other}) for removal from {filename}")
                if vna_next == 0:
                    break
                aux_pos += vna_next
        if vn_next == 0:
            break
        pos += vn_next

    # Patch symbol version table (.gnu.version)
    num_syms = dynsym_sz // 16
    patched_count = 0
    for i in range(num_syms):
        v_idx = struct.unpack('<H', data[versym_off + i*2 : versym_off + (i+1)*2])[0] & 0x7fff
        if v_idx in target_indices:
            st_name = struct.unpack('<I', data[dynsym_off + i*16 : dynsym_off + i*16 + 4])[0]
            sym_name = data[dynstr_off + st_name : data.find(b'\x00', dynstr_off + st_name)].decode()
            print(f"  Unversioning symbol: {sym_name} (was index {v_idx})")
            # Set to 1 (VER_NDX_GLOBAL)
            data[versym_off + i*2 : versym_off + (i+1)*2] = struct.pack('<H', 1)
            patched_count += 1

    print(f"Total symbols unversioned: {patched_count}")

    # Unlink target Vernaux entries in .gnu.version_r
    pos = v_off
    for i in range(v_num):
        vn_version, vn_cnt, vn_file, vn_aux, vn_next = struct.unpack('<HHIII', data[pos:pos+16])
        file_end = data.find(b'\x00', dynstr_off + vn_file)
        filename = data[dynstr_off + vn_file : file_end].decode()
        if filename == 'libc.so.6':
            aux_pos = pos + vn_aux
            valid_aux = []
            for j in range(vn_cnt):
                vna_hash, vna_flags, vna_other, vna_name, vna_next = struct.unpack('<IHHI I', data[aux_pos:aux_pos+16])
                if vna_other not in target_indices:
                    valid_aux.append(aux_pos)
                if vna_next == 0:
                    break
                aux_pos += vna_next

            # Relink valid Vernaux nodes
            for idx in range(len(valid_aux)):
                curr = valid_aux[idx]
                if idx == len(valid_aux) - 1:
                    struct.pack_into('<I', data, curr + 12, 0)
                else:
                    struct.pack_into('<I', data, curr + 12, valid_aux[idx+1] - curr)

            struct.pack_into('<H', data, pos + 2, len(valid_aux))
            print(f"Updated libc.so.6 Vernaux count from {vn_cnt} to {len(valid_aux)}")
        if vn_next == 0:
            break
        pos += vn_next

    with open(dst_path, 'wb') as f:
        f.write(data)
    print(f"Successfully saved patched ELF to: {dst_path}")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: patch_glibc.py <input_elf> <output_elf>")
        sys.exit(1)
    patch_binary(sys.argv[1], sys.argv[2])
