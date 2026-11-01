"""shotdiff.py <a.png> <b.png> [x0 y0 x1 y1]: how many pixels of two 8-bit PNG shots
differ (in the box, if given), how many by more than 8 of 255, and the most. No imaging
library needed (zlib and the PNG filters by hand). Two runs of the same build already
differ (wind, motes, clouds move with the clock), so compare a box round the thing you
changed against a box of bare ground in the same pair: the change is safe when the thing
differs no more than the ground does. Run it with `python -I`."""
import sys, zlib, struct

def load(path):
    data = open(path, 'rb').read()
    pos = 8; idat = b''; w = h = ch = 0
    while pos < len(data):
        n, t = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if t == b'IHDR':
            w, h, depth, ctype = struct.unpack('>IIBB', body[:10])
            ch = {2: 3, 6: 4, 0: 1}[ctype]
        elif t == b'IDAT':
            idat += body
        pos += 12 + n
    raw = zlib.decompress(idat)
    stride = w * ch
    out = bytearray(h * stride)
    prev = bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - ch] if x >= ch else 0
            b = prev[x]
            c = prev[x - ch] if x >= ch else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, ch, out

wa, ha, ca, a = load(sys.argv[1])
wb, hb, cb, b = load(sys.argv[2])
assert (wa, ha, ca) == (wb, hb, cb), "shots differ in size"
box = [int(v) for v in sys.argv[3:7]] if len(sys.argv) > 6 else [0, 0, wa, ha]
diff = big = most = cnt = 0
for y in range(box[1], box[3]):
    for x in range(box[0], box[2]):
        p = y * wa + x
        cnt += 1
        d = max(abs(a[p * ca + k] - b[p * ca + k]) for k in range(3))
        if d: diff += 1
        if d > 8: big += 1
        most = max(most, d)
print(f"{diff / cnt * 100:.2f}% pixels differ, {big / cnt * 100:.2f}% by >8, max {most}")
