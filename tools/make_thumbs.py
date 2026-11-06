#!/usr/bin/env python3
"""Convert wheel art / box art into /THUMBS/thumbs.pak for the EverDrive GG wheel
(OS v9 + wheel, build 9 or later: pack format 2, larger art).

Usage:
  python3 make_thumbs.py ART_DIR ROM_DIR [ROM_DIR ...] -o OUT_DIR [--preview preview.png]
                         [--folder "NAME=picture.png" ...]

  ART_DIR   PNG/JPG images named like the ROMs, e.g.
            "Sonic Chaos (USA, Europe).png" for "Sonic Chaos (USA, Europe).gg".
            Names in the libretro-thumbnails style (& * / : ` < > ? \\ | " -> _)
            match too. Transparent logos work best (wheel packs).
  ROM_DIR   folders with your .gg / .sms files (only the names are used)
  OUT_DIR   becomes /THUMBS on the SD card; the script writes thumbs.pak there
  --folder  a picture for a folder (or "Favourites"), e.g.
            --folder "GG=gamegear.png" --folder "Master system=sms.png"

Each picture is drawn as large as the wheel allows: up to 144x56 pixels, and
at most 72 different 8x8 blocks (empty and repeated blocks are free). Wide
logos come out about twice the size of the old 64x56 thumbnails.

The Game Gear shows two 16-colour palettes at once and every 8x8 block picks
one; both are built from your whole collection, so re-run this for everything
when you add games. Black, white and yellow are fixed (text and highlights).

Needs Python 3 with Pillow and numpy:  pip3 install pillow numpy
"""
import os, sys, argparse
import numpy as np
from PIL import Image

CW, CH = 20, 7                      # slot in cells (160x56 px)
W, H = CW * 8, CH * 8
MAXW, MAXH = 144, 56                # picture box
TILES = 72                          # VRAM tiles per wheel slot
REC = 2560                          # 5 sectors per thumbnail
FIXED0 = {0: (0, 0, 0), 1: (15, 15, 15)}
FIXED1 = {0: (0, 0, 0), 1: (15, 15, 0)}
ROM_EXT = ('.gg', '.sms', '.sg')
IMG_EXT = ('.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp')
MAGIC = b'GTH2'


def djb2(filename):
    """Same hash as the Game Gear side: lower-case (A-Z only), without the
    extension (up to the last '.', unless the only dot is the first char)."""
    b = filename.encode('latin-1', 'replace')
    dot = b.rfind(b'.')
    if dot > 0:
        b = b[:dot]
    h = 5381
    for c in b:
        if 65 <= c <= 90:
            c += 32
        h = (h * 33 + c) & 0xFFFFFFFF
    return h


def norm(s):
    for ch in '&*/:`<>?\\|"':
        s = s.replace(ch, '_')
    return s.lower()


def key_background(im):
    """An opaque picture on a flat background (all four corners the same colour):
    make that background transparent, so it costs no tiles and gets cropped."""
    px = np.asarray(im).astype(np.int32)
    if px[:, :, 3].min() < 255:
        return im                                  # already has transparency
    h, w = px.shape[:2]
    corners = np.array([px[0, 0, :3], px[0, w - 1, :3], px[h - 1, 0, :3], px[h - 1, w - 1, :3]])
    if np.abs(corners - corners[0]).max() > 12:
        return im                                  # no flat background
    d = np.sqrt(((px[:, :, :3] - corners.mean(0)) ** 2).sum(-1))
    px[:, :, 3] = np.clip((d - 24) * 8, 0, 255)    # soft edge from 24 to 56 away
    return Image.fromarray(px.astype(np.uint8), 'RGBA')


def load(path, key=False):
    im = Image.open(path).convert('RGBA')
    if key:
        im = key_background(im)
    a = im.getchannel('A').point(lambda v: 255 if v > 24 else 0)
    bb = a.getbbox()
    return im.crop(bb) if bb else im


def place(im, scale):
    """-> (rgb in GG units HxWx3, mask HxW, box x0,y0,x1,y1)"""
    w = max(1, min(MAXW, round(im.width * scale)))
    h = max(1, min(MAXH, round(im.height * scale)))
    t = im.resize((w, h), Image.LANCZOS)
    x0, y0 = (W - w) // 2, (H - h) // 2
    canvas = Image.new('RGBA', (W, H), (0, 0, 0, 255))
    canvas.alpha_composite(t, (x0, y0))
    rgb = np.asarray(canvas.convert('RGB'), dtype=np.float64) / 255.0 * 15.0
    alpha = np.zeros((H, W), bool)
    alpha[y0:y0 + h, x0:x0 + w] = np.asarray(t.getchannel('A')) > 24
    mask = alpha & (rgb.max(-1) > 0.6)         # pixels that aren't (nearly) black
    return rgb, mask, (x0, y0, x0 + w, y0 + h)


def cells_used(mask):
    return int(mask.reshape(CH, 8, CW, 8).any((1, 3)).sum())


def fit_scale(im):
    s = min(MAXW / im.width, MAXH / im.height)
    while s > 0.02:
        _, mask, _ = place(im, s)
        if cells_used(mask) <= TILES:
            return s
        s *= 0.94
    return s


def kmeans(px, k, fixed, iters=12, seed=1):
    rng = np.random.default_rng(seed)
    free = k - len(fixed)
    pinned = np.array(list(fixed.values()), dtype=np.float64).reshape(-1, 3)
    if len(px) == 0:
        px = rng.uniform(0, 15, (64, 3))

    def nearest_d(cents):
        return ((px[:, None, :] - cents[None]) ** 2).sum(-1).min(1)

    cent = []
    for _ in range(free):
        d = nearest_d(np.vstack([pinned] + ([np.array(cent)] if cent else [])))
        cent.append(rng.uniform(0, 15, 3) if d.sum() <= 0 else px[rng.choice(len(px), p=d / d.sum())])
    cent = np.array(cent, dtype=np.float64)
    for it in range(iters + 1):
        allc = np.vstack([pinned, cent])
        d = ((px[:, None, :] - allc[None]) ** 2).sum(-1)
        lab = d.argmin(1)
        best = d.min(1)
        if it == iters:
            break
        for j in range(free):
            m = lab == len(pinned) + j
            if m.any():
                cent[j] = px[m].mean(0)
            else:
                w = best.argmax()
                cent[j] = px[w]
                best[w] = 0
    cent = np.clip(np.round(cent), 0, 15)
    used = {tuple(c) for c in pinned.astype(int)}
    best = nearest_d(np.vstack([pinned, cent]))
    order = list(np.argsort(-best))
    for j in range(free):
        c = tuple(int(v) for v in cent[j])
        while c in used and order:
            c = tuple(int(v) for v in np.clip(np.round(px[order.pop(0)]), 0, 15))
        used.add(c)
        cent[j] = c
    pal = [None] * k
    for i, c in fixed.items():
        pal[i] = c
    it = iter(cent)
    for i in range(k):
        if pal[i] is None:
            pal[i] = tuple(int(v) for v in next(it))
    return np.array(pal, dtype=np.float64)


def build_palettes(placed):
    tiles = []
    for rgb, mask, _ in placed:
        t = rgb.reshape(CH, 8, CW, 8, 3).transpose(0, 2, 1, 3, 4).reshape(-1, 64, 3)
        m = mask.reshape(CH, 8, CW, 8).transpose(0, 2, 1, 3).reshape(-1, 64).any(1)
        tiles.append(t[m])
    tiles = np.vstack(tiles)
    if len(tiles) > 8000:
        tiles = tiles[np.random.default_rng(0).choice(len(tiles), 8000, replace=False)]
    lum = tiles.mean((1, 2))
    assign = lum > np.median(lum)
    for _ in range(5):
        p0 = kmeans(tiles[~assign].reshape(-1, 3)[::3], 16, FIXED0)
        p1 = kmeans(tiles[assign].reshape(-1, 3)[::3], 16, FIXED1)
        e0 = ((tiles[:, :, None] - p0[None, None]) ** 2).sum(-1).min(-1).sum(-1)
        e1 = ((tiles[:, :, None] - p1[None, None]) ** 2).sum(-1).min(-1).sum(-1)
        assign = e1 < e0
    return p0, p1


def convert(rgb, mask, p0, p1):
    """Floyd-Steinberg inside the picture; outside it stays black (index 0)."""
    def terr(pal):
        d = ((rgb[:, :, None, :] - pal[None, None]) ** 2).sum(-1).min(-1)
        return d.reshape(CH, 8, CW, 8).sum((1, 3))
    psel = (terr(p1) < terr(p0)).astype(np.uint8)
    work = rgb.copy()
    idx = np.zeros((H, W), dtype=np.uint8)
    ys, xs = np.nonzero(mask.reshape(CH, 8, CW, 8).any((1, 3)).repeat(8, 0).repeat(8, 1))
    for y, x in zip(ys, xs):
        if not mask[y, x]:
            continue
        pal = p1 if psel[y // 8, x // 8] else p0
        old = work[y, x]
        i = int(((pal - old) ** 2).sum(1).argmin())
        idx[y, x] = i
        err = old - pal[i]
        for dy, dx, f in ((0, 1, 7), (1, -1, 3), (1, 0, 5), (1, 1, 1)):
            yy, xx = y + dy, x + dx
            if 0 <= yy < H and 0 <= xx < W and mask[yy, xx]:
                work[yy, xx] += err * f / 16
    return idx, psel


def tile_bytes(block):
    out = bytearray()
    for y in range(8):
        for plane in range(4):
            b = 0
            for x in range(8):
                b |= ((int(block[y, x]) >> plane) & 1) << (7 - x)
            out.append(b)
    return bytes(out)


def record(idx, psel, box):
    """-> 2560-byte record or None if more than 72 tiles are needed."""
    tiles, seen = [], {}
    cmap = bytearray(CW * CH)
    for r in range(CH):
        for c in range(CW):
            block = idx[r * 8:r * 8 + 8, c * 8:c * 8 + 8]
            if not block.any():
                continue
            key = (tile_bytes(block), int(psel[r, c]))
            if key not in seen:
                seen[key] = len(tiles)
                tiles.append(key[0])
            cmap[r * CW + c] = (seen[key] + 1) | (0x80 if psel[r, c] else 0)
    if len(tiles) > TILES:
        return None
    rec = bytearray(REC)
    rec[0:len(tiles) * 32] = b''.join(tiles)
    rec[2304:2304 + 140] = cmap
    rec[2444:2448] = bytes(box)
    rec[2556:2560] = MAGIC
    return bytes(rec)


def cram(p0, p1):
    out = bytearray()
    for pal in (p0, p1):
        for r, g, b in pal.astype(int):
            out += bytes([(g << 4) | r, b])
    return out


def write_pack(path, entries, pal):
    """entries: (name, record); the same record object under several names is stored once."""
    seen, items, datas, where = {}, [], [], {}
    for fn, data in entries:
        h = djb2(fn)
        if h in seen:
            if seen[h] != fn:
                print('warning: %r and %r share a hash, keeping the first' % (seen[h], fn))
            continue
        seen[h] = fn
        if id(data) not in where:
            where[id(data)] = len(datas)
            datas.append(data)
        items.append((h, where[id(data)]))
    k = 1
    while True:
        buckets = [[] for _ in range(k)]
        for i, (h, _) in enumerate(items):
            buckets[h & (k - 1)].append(i)
        if max(len(b) for b in buckets) <= 63 and k * 40 >= len(items):
            break
        k *= 2
    first = 1 + k
    hdr = bytearray(512)
    hdr[0:4] = b'GTPK'
    hdr[4:6] = len(items).to_bytes(2, 'little')
    hdr[6:8] = k.to_bytes(2, 'little')
    hdr[8:10] = first.to_bytes(2, 'little')
    hdr[10] = 2                                  # format 2: 5 sectors, 20x7 map
    hdr[64:128] = pal
    out = bytearray(hdr)
    for b in buckets:
        sec = bytearray(512)
        sec[0] = len(b)
        for j, i in enumerate(b):
            o = 8 + j * 8
            sec[o:o + 4] = items[i][0].to_bytes(4, 'little')
            sec[o + 4:o + 6] = (first + 5 * items[i][1]).to_bytes(2, 'little')
        out += sec
    for data in datas:
        out += data
    with open(path, 'wb') as f:
        f.write(out)
    return len(items), k


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('art')
    ap.add_argument('roms', nargs='+')
    ap.add_argument('-o', '--out', required=True)
    ap.add_argument('--preview')
    ap.add_argument('--folder', action='append', default=[], metavar='NAME=PICTURE')
    a = ap.parse_args()

    arts = {}
    for f in os.listdir(a.art):
        b, e = os.path.splitext(f)
        if e.lower() in IMG_EXT and not f.startswith('._'):
            arts[norm(b)] = os.path.join(a.art, f)
    games = []
    for d in a.roms:
        for f in sorted(os.listdir(d)):
            b, e = os.path.splitext(f)
            if e.lower() in ROM_EXT and not f.startswith('._'):
                games.append((b, f))
    found = [(f, arts[norm(b)]) for b, f in games if norm(b) in arts]
    missing = [b for b, f in games if norm(b) not in arts]
    print('%d ROMs, %d with art, %d without' % (len(games), len(found), len(missing)))
    for spec in a.folder:
        name, _, pic = spec.partition('=')
        if not os.path.isfile(pic):
            sys.exit('--folder %r: no such picture %r' % (name, pic))
        found.append((name, pic))
        if len(name) <= 8 and '.' not in name:
            # a folder stored with only a short DOS name (e.g. "GG") reaches
            # the OS as its 11-character 8.3 form, "GG" + 9 spaces
            found.append((name.upper().ljust(11), pic))
        print('folder %r: %s' % (name, os.path.basename(pic)))
    if not found:
        sys.exit('nothing to convert')

    srcs = {}
    folder_pics = {spec.partition('=')[2] for spec in a.folder}
    for _, p in found:
        if p not in srcs:
            im = load(p, key=p in folder_pics)
            srcs[p] = (im, fit_scale(im))
    placed = {p: place(im, s) for p, (im, s) in srcs.items()}
    p0, p1 = build_palettes(list(placed.values()))
    recs, previews = {}, {}
    for p, (im, s) in srcs.items():
        while True:
            rgb, mask, box = place(im, s)
            idx, psel = convert(rgb, mask, p0, p1)
            rec = record(idx, psel, box)
            if rec is not None:
                break
            s *= 0.94                               # dithering added blocks: a bit smaller
        recs[p] = rec
        if a.preview:
            out = np.zeros((H, W, 3))
            for y in range(H):
                for x in range(W):
                    out[y, x] = (p1 if psel[y // 8, x // 8] else p0)[idx[y, x]]
            previews[p] = Image.fromarray((out * 17).astype(np.uint8))
    os.makedirs(a.out, exist_ok=True)
    n, k = write_pack(os.path.join(a.out, 'thumbs.pak'), [(fn, recs[p]) for fn, p in found], cram(p0, p1))
    print('wrote %s: %d thumbnails, %d index sectors, %d KB' % (os.path.join(a.out, 'thumbs.pak'), n, k,
                                                             os.path.getsize(os.path.join(a.out, 'thumbs.pak')) // 1024))
    if a.preview and previews:
        ims = list(previews.values())
        cols = 4
        rows = (len(ims) + cols - 1) // cols
        sheet = Image.new('RGB', (cols * (W + 4), rows * (H + 4)), (40, 40, 40))
        for i, im in enumerate(ims):
            sheet.paste(im, ((i % cols) * (W + 4) + 2, (i // cols) * (H + 4) + 2))
        sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(a.preview)
        print('preview:', a.preview)
    if missing:
        print('no art for:', ', '.join(missing[:10]) + (' ...' if len(missing) > 10 else ''))


if __name__ == '__main__':
    main()
