# Draws the Forever mark: a flat, broad-nib infinity, white with alpha, as TGA and PNG.
import math, struct, sys, zlib
W, H, SS = 64, 32, 4
YS = 1.2
def curve(gap):
    pts = []
    n = 900
    for i in range(n):
        t = 2 * math.pi * i / n
        d = 1 + math.sin(t) ** 2
        x, y = math.cos(t) / d, math.sin(t) * math.cos(t) / d
        y = y * YS
        pts.append((t, x, y))
    return [p for p in pts if not (gap and gap[0] <= p[0] <= gap[1])]
def draw(gap, thin, thick, name):
    pts = curve(gap)
    sw, sh = W * SS, H * SS
    cover = bytearray(sw * sh)
    sx, ox, oy = 26.5 * SS, W * SS / 2, H * SS / 2
    for i, (t, x, y) in enumerate(pts):
        # A ribbon: fat around the outer loops, pinched through the crossing.
        r = (thin + (thick - thin) * min(1, abs(x) / 0.8) ** 1.4) * SS / 2
        cx, cy = ox + x * sx, oy + y * sx
        for py in range(int(cy - r - 1), int(cy + r + 2)):
            for px in range(int(cx - r - 1), int(cx + r + 2)):
                if 0 <= px < sw and 0 <= py < sh and (px - cx) ** 2 + (py - cy) ** 2 <= r * r:
                    cover[py * sw + px] = 1
    alpha = [[0] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            s = sum(cover[(y * SS + j) * sw + x * SS + i] for j in range(SS) for i in range(SS))
            alpha[y][x] = round(255 * s / (SS * SS))
    # TGA, bottom-up, BGRA.
    with open(name + ".tga", "wb") as f:
        f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 8))
        for y in range(H - 1, -1, -1):
            for x in range(W):
                f.write(bytes((255, 255, 255, alpha[y][x])))
    raw = b"".join(b"\0" + b"".join(bytes((255, 255, 255, a)) for a in row) for row in alpha)
    def chunk(k, d): return struct.pack(">I", len(d)) + k + d + struct.pack(">I", zlib.crc32(k + d))
    with open(name + ".png", "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
out = sys.argv[1]
draw(None, 2.5, 7.5, out + "/closed")
draw(None, 3.5, 9.0, out + "/curled")
