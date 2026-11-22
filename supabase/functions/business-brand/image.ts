// Logo's ontcijferen en als PNG opslaan, in puur JavaScript (pngjs + jpeg-js).
// Niet npm:imagescript: die laadt bij de import een native .node-module (FFI). De Supabase Edge Runtime kan dat niet,
// waardoor de functies admin en business-brand bij het opstarten crashten (500 WORKER_ERROR, beheer.pasr.nl:
// "Geen verbinding met de server."). image_test.ts draait daarom zonder --allow-ffi.
import { PNG } from "npm:pngjs@7.0.0";
import jpeg from "npm:jpeg-js@0.4.4";
import { Buffer } from "node:buffer";

/** RGBA, 4 bytes per pixel. */
export type Bitmap = { width: number; height: number; data: Uint8Array };

const MAX_PIXELS = 4096 * 4096;

/** PNG of JPEG naar RGBA; andere formaten (WebP, GIF) of kapotte bestanden: null. */
export function decodeImage(bytes: Uint8Array): Bitmap | null {
  try {
    if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) {
      const p = PNG.sync.read(Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength));
      if (!p.width || !p.height || p.width * p.height > MAX_PIXELS) return null;
      return { width: p.width, height: p.height, data: new Uint8Array(p.data.buffer, p.data.byteOffset, p.data.byteLength) };
    }
    if (bytes[0] === 0xff && bytes[1] === 0xd8) {
      const j = jpeg.decode(bytes, { useTArray: true, formatAsRGBA: true, maxResolutionInMP: 17, maxMemoryUsageInMB: 128 });
      if (!j.width || !j.height) return null;
      return { width: j.width, height: j.height, data: new Uint8Array(j.data.buffer, j.data.byteOffset, j.data.byteLength) };
    }
  } catch { /* kapot of niet te lezen */ }
  return null;
}

/** Verkleinen (box-filter) tot binnen max×max, verhouding blijft. Kleiner dan max: ongewijzigd. */
export function contain(img: Bitmap, max: number): Bitmap {
  const scale = Math.min(max / img.width, max / img.height);
  if (scale >= 1) return img;
  const w = Math.max(1, Math.round(img.width * scale)), h = Math.max(1, Math.round(img.height * scale));
  const out = new Uint8Array(w * h * 4);
  const sx = img.width / w, sy = img.height / h;
  for (let y = 0; y < h; y++) {
    const y0 = Math.floor(y * sy), y1 = Math.max(y0 + 1, Math.floor((y + 1) * sy));
    for (let x = 0; x < w; x++) {
      const x0 = Math.floor(x * sx), x1 = Math.max(x0 + 1, Math.floor((x + 1) * sx));
      let r = 0, g = 0, b = 0, a = 0, n = 0;
      for (let yy = y0; yy < y1; yy++) {
        let i = (yy * img.width + x0) * 4;
        for (let xx = x0; xx < x1; xx++, i += 4) {
          const al = img.data[i + 3];
          r += img.data[i] * al; g += img.data[i + 1] * al; b += img.data[i + 2] * al; a += al; n++;
        }
      }
      const o = (y * w + x) * 4;
      if (a > 0) { out[o] = Math.round(r / a); out[o + 1] = Math.round(g / a); out[o + 2] = Math.round(b / a); }
      out[o + 3] = Math.round(a / n);
    }
  }
  return { width: w, height: h, data: out };
}

/** RGBA naar PNG. */
export function encodePng(img: Bitmap): Uint8Array {
  const p = new PNG({ width: img.width, height: img.height });
  p.data.set(img.data);
  const b = PNG.sync.write(p, { deflateLevel: 9 });
  return new Uint8Array(b.buffer, b.byteOffset, b.byteLength);
}
