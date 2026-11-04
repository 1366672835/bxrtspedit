#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把多个单架构 Mach-O 合成一个 FAT（universal）文件。

用法:
  python3 make_fat.py 输出文件 0x0100000c:0:arm64.dylib 0x0100000c:0x80000002:arm64e.dylib
"""
import struct
import sys

FAT_MAGIC = 0xCAFEBABE
ALIGN = 0x4000  # 2^14，和原版 dylib 一致


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    out = sys.argv[1]
    specs = []
    for a in sys.argv[2:]:
        parts = a.split(":")
        if len(parts) != 3:
            print("bad spec:", a)
            return 1
        ct, cs, path = parts
        specs.append((int(ct, 0), int(cs, 0), path))

    entries, blobs, off = [], [], ALIGN
    for ct, cs, path in specs:
        with open(path, "rb") as fh:
            b = fh.read()
        entries.append((ct, cs, off, len(b), 14))
        blobs.append(b)
        off = (off + len(b) + ALIGN - 1) // ALIGN * ALIGN

    hdr = struct.pack(">II", FAT_MAGIC, len(entries))
    for ct, cs, o, ln, al in entries:
        hdr += struct.pack(">IIIII", ct, cs, o, ln, al)

    buf = bytearray(off)
    buf[0:len(hdr)] = hdr
    for (ct, cs, o, ln, al), b in zip(entries, blobs):
        buf[o:o + ln] = b

    with open(out, "wb") as fh:
        fh.write(buf)
    print("wrote %s  %d bytes  slices=%d" % (out, len(buf), len(entries)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
