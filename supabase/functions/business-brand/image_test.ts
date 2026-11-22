// Logo's ontcijferen, verkleinen en als PNG opslaan, plus de opstarttest: admin en business-brand moeten laden zonder
// FFI (native .node-modules), want de Supabase Edge Runtime kan dat niet (22-11-2026: npm:imagescript liet beide
// functies crashen met 500 WORKER_ERROR, beheer.pasr.nl gaf "Geen verbinding met de server.").
import jpeg from "npm:jpeg-js@0.4.4";
import { contain, decodeImage, encodePng } from "./image.ts";
const ok = (c: unknown, m: string) => { if (!c) throw new Error(m); };

const fill = (w: number, h: number, rgba: number[]) => {
  const data = new Uint8Array(w * h * 4);
  for (let i = 0; i < data.length; i += 4) data.set(rgba, i);
  return { width: w, height: h, data };
};

Deno.test("PNG: heen en terug, verkleinen houdt de verhouding en de kleur", () => {
  const png = encodePng(fill(600, 400, [0xd9, 0x16, 0x1e, 0xff]));
  const back = decodeImage(png)!;
  ok(back && back.width === 600 && back.height === 400, "afmetingen");
  const small = contain(back, 300);
  ok(small.width === 300 && small.height === 200, `${small.width}x${small.height}`);
  ok(small.data[0] === 0xd9 && small.data[1] === 0x16 && small.data[2] === 0x1e && small.data[3] === 0xff, "kleur");
  ok(contain(back, 1000) === back, "kleiner dan max: ongewijzigd");
});

Deno.test("JPEG lezen; WebP, GIF en rommel: null", () => {
  const j = jpeg.encode(fill(64, 64, [0x12, 0x34, 0x56, 0xff]), 90);
  const img = decodeImage(new Uint8Array(j.data))!;
  ok(img && img.width === 64 && img.height === 64, "jpeg");
  ok(Math.abs(img.data[2] - 0x56) < 8 && img.data[3] === 255, "jpeg-kleur");
  ok(decodeImage(new TextEncoder().encode("GIF89a........")) === null, "gif");
  ok(decodeImage(new TextEncoder().encode("RIFF....WEBPVP8 ")) === null, "webp");
  ok(decodeImage(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 1, 2, 3])) === null, "kapotte png");
});

Deno.test({
  name: "opstarten zonder FFI: admin en business-brand laden zoals in de Edge Runtime",
  // alleen als de test mag starten (in de workflow: deno test -A); anders overslaan
  ignore: (await Deno.permissions.query({ name: "run" })).state !== "granted",
  async fn() {
    const here = new URL(".", import.meta.url);
    const mods = ["../admin/index.ts", "../business-brand/index.ts"].map((m) => new URL(m, here).href);
    // Deno.serve nagebootst: alleen laden, niet luisteren
    const code = `Deno.serve = () => ({ finished: Promise.resolve(), shutdown() {} });
      for (const m of ${JSON.stringify(mods)}) await import(m);
      console.log("BOOT_OK");`;
    const file = await Deno.makeTempFile({ suffix: ".ts" });
    await Deno.writeTextFile(file, code);
    // bewust zonder --allow-ffi (deno eval zou alles toestaan): zoals de Edge Runtime
    const args = ["run", "--no-check", "--allow-env", "--allow-net", "--allow-read"];
    const map = Deno.env.get("BOOT_IMPORT_MAP");   // alleen lokaal, als jsr.io niet bereikbaar is
    if (map) args.push("--import-map", map);
    args.push(file);
    const out = await new Deno.Command(Deno.execPath(), {
      args, env: { SUPABASE_URL: "http://127.0.0.1:9", SUPABASE_SERVICE_ROLE_KEY: "x", NO_COLOR: "1" },
      stdout: "piped", stderr: "piped",
    }).output();
    await Deno.remove(file).catch(() => {});
    const text = new TextDecoder().decode(out.stdout) + new TextDecoder().decode(out.stderr);
    ok(out.success && text.includes("BOOT_OK"), "functie start niet zonder FFI:\n" + text.slice(-1500));
  },
});
