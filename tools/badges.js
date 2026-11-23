// Draws Custodian's mark badges: four 64x64 icons the addon shows over marked items in the bags (about 15 px,
// 75% opacity by default). Each is a filled circle in the mark's color, a dark outline ring so it reads on any
// item picture, and one bold white glyph whose shape, not just its color, tells the marks apart: Junk a coin,
// Mail an envelope, Locked a padlock, OnMe ("Always on me") a diamond. Antialiased by 8x8 supersampling.
// Writes StandingOrders_Custodian/Media/<Name>.tga in Icon.tga's format. Uses only fs, path and zlib.
//
//   node tools/badges.js                   regenerates the four TGAs
//   node tools/badges.js --preview <png>   also writes a PNG sheet to look them over. One row per badge; each view on a
//                                          dark, item-icon-like square and on a light one: 64 px as drawn, then
//                                          20 px, 16 px and 16 px enlarged 4x (nearest), shrunk with a box filter
//                                          and shown at the game's default 75% opacity.
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const SIZE = 64, SAMPLES = 8; // pixels per side; samples per pixel along each axis
const C = 32, OUTER = 30.5, INNER = 26.5; // badge center; ring's outer radius (1.5 px clear margin); fill radius
const RING_SHADE = 0.25; // the ring is the fill color times this
const WHITE = [1, 1, 1];
const OPACITY = 0.75; // the game's default mark opacity, for the preview's small sizes

// Shapes: functions of a point (x, y), in pixels from the top left, that say whether it's inside.
const disc = (cx, cy, r) => (x, y) => (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
const rect = (x0, y0, x1, y1) => (x, y) => x >= x0 && x <= x1 && y >= y0 && y <= y1;
const union = (...shapes) => (x, y) => shapes.some((s) => s(x, y));
const minus = (shape, ...holes) => (x, y) => shape(x, y) && !holes.some((h) => h(x, y));
const ring = (cx, cy, r0, r1) => minus(disc(cx, cy, r1), disc(cx, cy, r0));
const roundRect = (x0, y0, x1, y1, r) => (x, y) => {
  const dx = Math.max(x0 + r - x, x - x1 + r, 0), dy = Math.max(y0 + r - y, y - y1 + r, 0);
  return rect(x0, y0, x1, y1)(x, y) && dx * dx + dy * dy <= r * r;
};
const diamond = (cx, cy, rx, ry) => (x, y) => Math.abs(x - cx) / rx + Math.abs(y - cy) / ry <= 1;
const stroke = (ax, ay, bx, by, w) => (x, y) => { // a line w wide from a to b, with round ends
  const dx = bx - ax, dy = by - ay, t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)));
  return (x - ax - t * dx) ** 2 + (y - ay - t * dy) ** 2 <= (w * w) / 4;
};

// The glyphs are white; holes cut from them show the fill. Keep strokes and holes 4 px or wider (a pixel at
// 16 px), or they blur away.
const BADGES = [
  { name: "Junk", fill: "868686", // a coin: a disc with a rim line
    glyph: minus(disc(C, C, 19.5), ring(C, C, 9.5, 14.5)) },
  { name: "Mail", fill: "3a8fd6", // an envelope: a rectangle with a V flap
    glyph: minus(roundRect(12, 18, 52, 46, 3), stroke(15, 21, C, 36, 4), stroke(49, 21, C, 36, 4)) },
  { name: "Locked", fill: "e03c3c", // a padlock: shackle arc, body, keyhole
    glyph: minus(union(roundRect(15, 29, 49, 51, 4), minus(ring(C, 25.5, 6.5, 11.5), rect(0, 25.5, SIZE, SIZE)),
      rect(20.5, 25.5, 25.5, 30), rect(38.5, 25.5, 43.5, 30)), disc(C, 38.5, 3.5), rect(30, 39, 34, 45.5)) },
  { name: "OnMe", fill: "a457e0", // a diamond, like the raid marker it replaces
    glyph: diamond(C, C, 17, 23) },
];

const hex = (h) => [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
const byte = (v) => Math.max(0, Math.min(255, Math.round(v * 255)));
const contrast = (h) => { // WCAG contrast ratio of white on the fill
  const [r, g, b] = hex(h).map((v) => (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 1.05 / (0.2126 * r + 0.7152 * g + 0.0722 * b + 0.05);
};

// A badge as premultiplied RGBA (0-1), top row first: glyph over fill over ring.
function render(badge) {
  const fill = hex(badge.fill), edge = fill.map((v) => v * RING_SHADE), share = 1 / SAMPLES ** 2;
  const outer = disc(C, C, OUTER), inner = disc(C, C, INNER), px = new Float64Array(SIZE * SIZE * 4);
  for (let y = 0; y < SIZE; y++) for (let x = 0; x < SIZE; x++) {
    const o = (y * SIZE + x) * 4;
    for (let sy = 0; sy < SAMPLES; sy++) for (let sx = 0; sx < SAMPLES; sx++) {
      const u = x + (sx + 0.5) / SAMPLES, v = y + (sy + 0.5) / SAMPLES;
      const color = badge.glyph(u, v) ? WHITE : inner(u, v) ? fill : outer(u, v) ? edge : null;
      if (!color) continue;
      for (let k = 0; k < 3; k++) px[o + k] += color[k] * share;
      px[o + 3] += share;
    }
  }
  return { w: SIZE, h: SIZE, px, edge };
}

// Icon.tga's format: an 18-byte header (no image ID, no color map, type 2 = uncompressed true-color, 64 x 64,
// 32 bits, descriptor 8 = 8 alpha bits and bottom-left origin), then BGRA with straight alpha, bottom row first.
// Clear pixels get the ring's color, so the game's filtering blends the edge toward the ring, not black.
function tga(img) {
  const out = Buffer.alloc(18 + SIZE * SIZE * 4);
  out[2] = 2; out.writeUInt16LE(SIZE, 12); out.writeUInt16LE(SIZE, 14); out[16] = 32; out[17] = 8;
  let p = 18;
  for (let y = SIZE - 1; y >= 0; y--) for (let x = 0; x < SIZE; x++) {
    const o = (y * SIZE + x) * 4, a = img.px[o + 3];
    const rgb = a > 0 ? [0, 1, 2].map((k) => img.px[o + k] / a) : img.edge;
    out[p++] = byte(rgb[2]); out[p++] = byte(rgb[1]); out[p++] = byte(rgb[0]); out[p++] = byte(a);
  }
  return out;
}

// Reads such a file back (premultiplied, top row first), so the preview shows exactly what the game loads.
function fromTga(buf) {
  const px = new Float64Array(SIZE * SIZE * 4);
  for (let i = 0; i < SIZE * SIZE; i++) {
    const p = 18 + i * 4, a = buf[p + 3] / 255, o = ((SIZE - 1 - Math.floor(i / SIZE)) * SIZE + (i % SIZE)) * 4;
    px[o] = (buf[p + 2] / 255) * a; px[o + 1] = (buf[p + 1] / 255) * a; px[o + 2] = (buf[p] / 255) * a; px[o + 3] = a;
  }
  return { w: SIZE, h: SIZE, px };
}

// Box filter: shrinks a premultiplied image to n x n, each pixel the average of the source area it covers.
function shrink(img, n) {
  const s = img.w / n, px = new Float64Array(n * n * 4);
  const overlap = (i, j) => Math.min(j + 1, (i + 1) * s) - Math.max(j, i * s); // target pixel i, source pixel j
  const end = (i) => Math.min(img.w, Math.ceil((i + 1) * s));
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
    for (let sy = Math.floor(y * s); sy < end(y); sy++) for (let sx = Math.floor(x * s); sx < end(x); sx++) {
      const w = (overlap(y, sy) * overlap(x, sx)) / (s * s);
      for (let k = 0; k < 4; k++) px[(y * n + x) * 4 + k] += w * img.px[(sy * img.w + sx) * 4 + k];
    }
  }
  return { w: n, h: n, px };
}

// Composites a premultiplied image onto the RGB sheet (W wide) at (x0, y0), each pixel as a mag x mag block.
function draw(sheet, W, img, x0, y0, mag, opacity) {
  for (let y = 0; y < img.h * mag; y++) for (let x = 0; x < img.w * mag; x++) {
    const o = (Math.floor(y / mag) * img.w + Math.floor(x / mag)) * 4, s = ((y0 + y) * W + x0 + x) * 3;
    for (let k = 0; k < 3; k++) sheet[s + k] = img.px[o + k] * opacity + sheet[s + k] * (1 - img.px[o + 3] * opacity);
  }
}

const DARK = hex("3b2a1c"), LIGHT = hex("e6e1d6"); // an item-icon-like dark brown, and a light square
const VIEWS = [[SIZE, 1, 1], [20, 1, OPACITY], [16, 1, OPACITY], [16, 4, OPACITY]]; // size, enlarged, opacity
const CELL = 80, GAP = 8;

function preview(file, imgs) {
  const W = GAP + VIEWS.length * 2 * (CELL + GAP), H = GAP + imgs.length * (CELL + GAP);
  const sheet = new Float64Array(W * H * 3).fill(0.3);
  imgs.forEach((img, row) => {
    VIEWS.forEach(([n, mag, opacity], v) => {
      const shown = n === SIZE ? img : shrink(img, n), off = (CELL - n * mag) >> 1;
      [DARK, LIGHT].forEach((bg, b) => {
        const x0 = GAP + (v * 2 + b) * (CELL + GAP), y0 = GAP + row * (CELL + GAP);
        for (let y = y0; y < y0 + CELL; y++) for (let x = x0; x < x0 + CELL; x++) sheet.set(bg, (y * W + x) * 3);
        draw(sheet, W, shown, x0 + off, y0 + off, mag, opacity);
      });
    });
  });
  writePng(file, W, H, sheet);
}

function crc32(buf) {
  let c = ~0;
  for (const b of buf) { c ^= b; for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1)); }
  return ~c >>> 0;
}

// A minimal PNG: 8-bit RGB, unfiltered rows (filter byte 0), one deflated IDAT chunk.
function writePng(file, w, h, rgb) {
  const chunk = (type, data) => {
    const b = Buffer.alloc(12 + data.length);
    b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8);
    b.writeUInt32BE(crc32(b.subarray(4, 8 + data.length)), 8 + data.length);
    return b;
  };
  const head = Buffer.alloc(13);
  head.writeUInt32BE(w, 0); head.writeUInt32BE(h, 4); head[8] = 8; head[9] = 2; // bit depth 8, color type RGB
  const raw = Buffer.alloc(h * (1 + w * 3));
  for (let y = 0; y < h; y++) for (let i = 0; i < w * 3; i++) raw[y * (1 + w * 3) + 1 + i] = byte(rgb[y * w * 3 + i]);
  fs.writeFileSync(file, Buffer.concat([Buffer.from("89504e470d0a1a0a", "hex"), chunk("IHDR", head),
    chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}

const args = process.argv.slice(2), at = args.indexOf("--preview");
if (at >= 0 && !args[at + 1]) { console.error("Usage: node tools/badges.js [--preview <file.png>]"); process.exit(1); }
const dir = path.join(__dirname, "..", "StandingOrders_Custodian", "Media");
fs.mkdirSync(dir, { recursive: true });
const written = BADGES.map((badge) => {
  const file = path.join(dir, badge.name + ".tga");
  fs.writeFileSync(file, tga(render(badge)));
  console.log(`${path.relative(process.cwd(), file)}  #${badge.fill}  white glyph contrast ${contrast(badge.fill).toFixed(2)}:1`);
  return fromTga(fs.readFileSync(file));
});
if (at >= 0) { preview(args[at + 1], written); console.log(`Preview: ${path.resolve(args[at + 1])}`); }
