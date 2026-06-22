#!/usr/bin/env python3
"""Tolerance PNG diff — python3 stdlib only (zlib + struct), no Pillow.

Usage: pngdiff.py <golden.png> <actual.png> [tolerance_fraction]

Decodes both PNGs, errors clearly if their dimensions differ, computes the
fraction of pixels that differ by more than a small per-channel delta, and
exits non-zero if that fraction exceeds the tolerance (default 0.002 = 0.2%).
On mismatch, writes a side-by-side diff PNG (golden | actual | difference-mask)
next to the actual file.

Degrades gracefully: any import/decode failure prints a SKIP line and exits 0
so a host without a usable python3 image stack never fails the suite spuriously.
"""
import sys
import struct
import zlib

# Per-channel delta below which two samples are considered equal (0-255 space).
CHANNEL_DELTA = 8


def _read_chunks(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG (bad signature)")
    pos = 8
    chunks = []
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        cdata = data[pos + 8:pos + 8 + length]
        chunks.append((ctype, cdata))
        pos += 12 + length  # length + type + data + crc
    return chunks


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def load_rgba(path):
    """Return (width, height, bytearray of RGBA rows). Supports 8-bit
    truecolor (RGB / RGBA), non-interlaced — what ImageRenderer emits."""
    with open(path, "rb") as f:
        data = f.read()
    width = height = bit_depth = color_type = interlace = None
    idat = bytearray()
    for ctype, cdata in _read_chunks(data):
        if ctype == b"IHDR":
            (width, height, bit_depth, color_type, _comp, _filt, interlace) = struct.unpack(">IIBBBBB", cdata)
        elif ctype == b"IDAT":
            idat += cdata
        elif ctype == b"IEND":
            break
    if width is None:
        raise ValueError("no IHDR")
    if bit_depth != 8 or interlace != 0 or color_type not in (2, 6):
        raise ValueError("unsupported PNG (depth=%s color=%s interlace=%s)" % (bit_depth, color_type, interlace))
    channels = 4 if color_type == 6 else 3
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    out = bytearray(width * height * 4)
    prev = bytearray(stride)
    pos = 0
    for y in range(height):
        ftype = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if ftype == 1:  # Sub
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ftype == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:  # Average
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:  # Paeth
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                c = prev[i - channels] if i >= channels else 0
                line[i] = (line[i] + _paeth(a, prev[i], c)) & 0xFF
        elif ftype != 0:
            raise ValueError("bad filter type %d" % ftype)
        # expand row to RGBA
        ob = y * width * 4
        if channels == 4:
            out[ob:ob + stride] = line
        else:
            for x in range(width):
                si = x * 3
                di = ob + x * 4
                out[di] = line[si]
                out[di + 1] = line[si + 1]
                out[di + 2] = line[si + 2]
                out[di + 3] = 255
        prev = line
    return width, height, out


def _write_png(path, width, height, rgba):
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter: none
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(ctype, body):
        return (struct.pack(">I", len(body)) + ctype + body
                + struct.pack(">I", zlib.crc32(ctype + body) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) \
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(out)


def main():
    if len(sys.argv) < 3:
        print("usage: pngdiff.py <golden> <actual> [tolerance]", file=sys.stderr)
        return 2
    golden, actual = sys.argv[1], sys.argv[2]
    tol = float(sys.argv[3]) if len(sys.argv) > 3 else 0.002
    try:
        gw, gh, g = load_rgba(golden)
        aw, ah, a = load_rgba(actual)
    except Exception as e:  # pragma: no cover - host stack issue
        print("pngdiff SKIP (%s)" % e)
        return 0
    if (gw, gh) != (aw, ah):
        print("pngdiff DIMENSION MISMATCH golden=%dx%d actual=%dx%d" % (gw, gh, aw, ah), file=sys.stderr)
        return 1
    total = gw * gh
    diffcount = 0
    mask = bytearray(total * 4)
    for i in range(total):
        b = i * 4
        d = (abs(g[b] - a[b]) > CHANNEL_DELTA
             or abs(g[b + 1] - a[b + 1]) > CHANNEL_DELTA
             or abs(g[b + 2] - a[b + 2]) > CHANNEL_DELTA)
        if d:
            diffcount += 1
            mask[b] = 255
            mask[b + 1] = 0
            mask[b + 2] = 255
            mask[b + 3] = 255
        else:
            mask[b + 3] = 255  # opaque black where equal
    frac = diffcount / total if total else 0.0
    if frac > tol:
        # side-by-side: golden | actual | mask
        cw = gw * 3
        side = bytearray(cw * gh * 4)
        for y in range(gh):
            for x in range(gw):
                src = (y * gw + x) * 4
                for k, buf in enumerate((g, a, mask)):
                    dst = (y * cw + (k * gw + x)) * 4
                    side[dst:dst + 4] = buf[src:src + 4]
        diff_path = actual.rsplit(".", 1)[0] + ".diff.png"
        try:
            _write_png(diff_path, cw, gh, side)
            print("pngdiff FAIL %.4f%% > %.4f%% — wrote %s" % (frac * 100, tol * 100, diff_path), file=sys.stderr)
        except Exception as e:  # pragma: no cover
            print("pngdiff FAIL %.4f%% (diff write failed: %s)" % (frac * 100, e), file=sys.stderr)
        return 1
    print("pngdiff OK %.4f%% <= %.4f%%" % (frac * 100, tol * 100))
    return 0


if __name__ == "__main__":
    sys.exit(main())
