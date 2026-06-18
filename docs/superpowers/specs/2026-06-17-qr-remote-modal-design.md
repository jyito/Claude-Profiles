# QR of the SSH attach line — design

## Goal
In the Remote modal, show a QR of the SSH attach line so you can read it onto a
phone/iPad camera instead of retyping a long `ssh … screen -r …` command.

## Constraint & approach
Zero dependencies, no network — so no QR library and no remote QR service. A
self-contained **byte-mode QR encoder** is added inline to `dashboard.html`:

- Versions **1–5, ECC level L, single block** (data capacity 17→106 bytes — any SSH
  attach line fits; longer input returns null and the QR is simply hidden).
- Full pipeline per ISO/IEC 18004: UTF-8 byte encoding → Reed-Solomon ECC over
  GF(256) (primitive 0x11D) → matrix skeleton (finders, separators, timing,
  single alignment pattern for v2–5, dark module) → zig-zag data placement →
  all-8-mask penalty evaluation → format-info BCH(15,5). Placement/format/mask
  follow Nayuki's reference.
- `qrSvg(text)` renders **dark-on-light** inline SVG (with a 4-module quiet zone) —
  light background is required to scan, even though the app is dark-themed.

`updateRemote` renders the QR of the any-network (Tailscale) line when available,
else the same-network line, into `#rm-qr`.

## Testing
Node-driven (the encoder is pure JS):
- **Format-info BCH** matches the authoritative spec table for all 8 masks.
- **GF(256)** tables spot-checked (α⁸ = 29).
- **Finder patterns** + v1 size (21×21) for short input.
- **Round-trip**: encode → place → mask → unmask → read zig-zag → identical
  codewords. This exercises the most bug-prone parts (placement, masking, reserved
  areas) end-to-end.
- SVG output shape; version bumps for longer text.

The one thing the suite can't do is confirm a real scanner reads it — that's a
quick **phone-scan check** for the maintainer (a 29×29 v3 render was eyeballed and
is structurally a valid QR).

## Non-negotiables
Zero deps (encoder is ~120 lines of inline JS, no library), zero network, no
external assets. Pure client-side rendering; touches no credentials or data dirs.
