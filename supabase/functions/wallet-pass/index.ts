// Pasr → Apple Wallet. Builds a signed .pkpass for one card, on request of the app.
//
// The app sends the card (store, number, code type, colour, logo, nearby branches); this function turns it into
// a Wallet pass, signs it with Pasr's pass certificate and sends it straight back. Nothing is stored.
//
// Function secrets (set by the workflow Backend from the GitHub secrets):
//   PASS_TYPE_ID         e.g. pass.nl.lrvdlinden.pasr
//   PASS_TEAM_ID         EU3UY476T6
//   PASS_CERT_P12        the pass certificate + private key as .p12, base64
//   PASS_CERT_PASSWORD   password of that .p12
//   PASR_PUBLISHABLE_KEY the app's publishable key (only the Pasr app may ask for passes)
import forge from "npm:node-forge@1.3.1";
import { zipSync, strToU8 } from "npm:fflate@0.8.2";
import { ICONS } from "./icons.ts";

const WWDR_URL = "https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer";
let wwdr: forge.pki.Certificate | null = null;
let signer: { cert: forge.pki.Certificate; key: forge.pki.PrivateKey } | null = null;
const hits = new Map<string, number[]>();

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Card = {
  id: string;
  name: string;
  number: string;
  format: string;             // ean13, code128, qr, pdf417, aztec, ...
  colorHex: string;
  kind?: string;              // loyalty | voucher
  balance?: number;
  currency?: string;
  expiresAt?: string;         // ISO date
  note?: string;
  logo?: string;              // PNG, base64 (white or brand-coloured logo, transparent background)
  locations?: { latitude: number; longitude: number; name?: string }[];
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const key = Deno.env.get("PASR_PUBLISHABLE_KEY");
  if (key && req.headers.get("apikey") !== key) return json({ error: "forbidden" }, 403);

  // Light rate limit per IP: 30 passes per 10 minutes
  const ip = (req.headers.get("cf-connecting-ip") ?? req.headers.get("x-forwarded-for")?.split(",").pop() ?? "?").trim();
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < 600_000);
  if (recent.length >= 30) return json({ error: "rate_limited" }, 429);
  hits.set(ip, [...recent, now]);

  let card: Card;
  try {
    card = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  if (!card?.id || !card?.number || !card?.name || String(card.number).length > 200) return json({ error: "bad_request" }, 400);

  try {
    const pkpass = await buildPass(card);
    return new Response(pkpass, {
      headers: {
        ...cors,
        "Content-Type": "application/vnd.apple.pkpass",
        "Content-Disposition": `attachment; filename="pasr.pkpass"`,
        "Cache-Control": "no-store",
      },
    });
  } catch (e) {
    console.error("wallet-pass:", (e as Error).message);
    return json({ error: "unavailable" }, 503);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

// ---------------------------------------------------------------------------------------------------------------

async function buildPass(card: Card): Promise<Uint8Array> {
  const passTypeIdentifier = Deno.env.get("PASS_TYPE_ID") ?? "pass.nl.lrvdlinden.pasr";
  const teamIdentifier = Deno.env.get("PASS_TEAM_ID") ?? "EU3UY476T6";
  const bg = hexToRgb(card.colorHex);
  const light = luminance(bg) > 0.55;
  const fg = light ? "rgb(17, 17, 17)" : "rgb(255, 255, 255)";
  const label = light ? "rgb(90, 90, 90)" : "rgba(255, 255, 255, 0.75)";
  const grouped = groupNumber(card.number);
  const voucher = card.kind === "voucher";

  const pass: Record<string, unknown> = {
    formatVersion: 1,
    passTypeIdentifier,
    teamIdentifier,
    serialNumber: card.id,
    organizationName: "Pasr",
    description: `${card.name} (Pasr)`,
    backgroundColor: `rgb(${bg.join(", ")})`,
    foregroundColor: fg,
    labelColor: label,
    barcodes: [{
      format: walletFormat(card.format),
      message: card.number,
      messageEncoding: "iso-8859-1",
      altText: grouped,
    }],
    storeCard: {
      headerFields: voucher && card.balance != null
        ? [{ key: "balance", label: "TEGOED", value: card.balance, currencyCode: card.currency ?? "EUR" }]
        : [],
      secondaryFields: [{ key: "number", label: voucher ? "KAARTNUMMER" : "NUMMER", value: grouped }],
      auxiliaryFields: voucher && card.expiresAt
        ? [{ key: "expires", label: "GELDIG TOT", value: card.expiresAt, dateStyle: "PKDateStyleMedium" }]
        : [],
      backFields: [
        ...(card.note ? [{ key: "note", label: "Notitie", value: card.note }] : []),
        { key: "pasr", label: "Pasr", value: "Deze pas komt uit Pasr, de gratis app voor je klantenkaarten. pasr.nl" },
      ],
    },
  };
  if (!card.logo) pass.logoText = card.name;
  if (voucher && card.expiresAt) pass.expirationDate = card.expiresAt;
  const locations = (card.locations ?? []).filter((l) => isFinite(l.latitude) && isFinite(l.longitude)).slice(0, 10);
  if (locations.length) {
    pass.locations = locations.map((l) => ({
      latitude: l.latitude,
      longitude: l.longitude,
      relevantText: `Je ${card.name}-kaart`,
    }));
  }

  const files: Record<string, Uint8Array> = {
    "pass.json": strToU8(JSON.stringify(pass)),
    "icon.png": await asset("icon.png"),
    "icon@2x.png": await asset("icon@2x.png"),
    "icon@3x.png": await asset("icon@3x.png"),
  };
  if (card.logo) {
    const logo = Uint8Array.from(atob(card.logo), (c) => c.charCodeAt(0));
    if (logo.length > 600_000) throw new Error("logo too large");
    files["logo.png"] = logo;
    files["logo@2x.png"] = logo;
    files["logo@3x.png"] = logo;
  }

  const manifest: Record<string, string> = {};
  for (const [name, data] of Object.entries(files)) manifest[name] = await sha1(data);
  const manifestBytes = strToU8(JSON.stringify(manifest));
  files["manifest.json"] = manifestBytes;
  files["signature"] = await sign(manifestBytes);
  return zipSync(files, { level: 6 });
}

async function asset(name: string) {
  return Uint8Array.from(atob(ICONS[name]), (c) => c.charCodeAt(0));
}

async function sha1(data: Uint8Array) {
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-1", data));
  return Array.from(hash).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Detached PKCS#7 signature of manifest.json with the pass certificate, Apple WWDR G4 in the chain. */
async function sign(manifest: Uint8Array): Promise<Uint8Array> {
  if (!signer) {
    const p12b64 = Deno.env.get("PASS_CERT_P12");
    if (!p12b64) throw new Error("PASS_CERT_P12 missing");
    const p12 = forge.pkcs12.pkcs12FromAsn1(forge.asn1.fromDer(forge.util.decode64(p12b64.replace(/\s+/g, ""))),
      Deno.env.get("PASS_CERT_PASSWORD") ?? "");
    const cert = p12.getBags({ bagType: forge.pki.oids.certBag })[forge.pki.oids.certBag]?.[0]?.cert;
    const key = (p12.getBags({ bagType: forge.pki.oids.pkcs8ShroudedKeyBag })[forge.pki.oids.pkcs8ShroudedKeyBag]?.[0]
      ?? p12.getBags({ bagType: forge.pki.oids.keyBag })[forge.pki.oids.keyBag]?.[0])?.key;
    if (!cert || !key) throw new Error("certificate or key not found in PASS_CERT_P12");
    signer = { cert, key };
  }
  if (!wwdr) {
    const der = new Uint8Array(await (await fetch(WWDR_URL)).arrayBuffer());
    wwdr = forge.pki.certificateFromAsn1(forge.asn1.fromDer(forge.util.binary.raw.encode(der)));
  }
  const p7 = forge.pkcs7.createSignedData();
  p7.content = forge.util.createBuffer(forge.util.binary.raw.encode(manifest));
  p7.addCertificate(signer.cert);
  p7.addCertificate(wwdr);
  p7.addSigner({
    key: signer.key,
    certificate: signer.cert,
    digestAlgorithm: forge.pki.oids.sha256,
    authenticatedAttributes: [
      { type: forge.pki.oids.contentType, value: forge.pki.oids.data },
      { type: forge.pki.oids.messageDigest },
      { type: forge.pki.oids.signingTime, value: new Date() as unknown as string },
    ],
  });
  p7.sign({ detached: true });
  const der = forge.asn1.toDer(p7.toAsn1()).getBytes();
  return Uint8Array.from(der, (c) => c.charCodeAt(0));
}

// Wallet knows QR, PDF417, Aztec and Code 128. EAN/UPC/Code 39/ITF become Code 128 with the same number,
// which checkout scanners read just the same.
function walletFormat(format: string) {
  switch (format) {
    case "qr": return "PKBarcodeFormatQR";
    case "pdf417": return "PKBarcodeFormatPDF417";
    case "aztec": return "PKBarcodeFormatAztec";
    default: return "PKBarcodeFormatCode128";
  }
}

function groupNumber(n: string) {
  const c = n.replace(/\s+/g, "");
  return c.length > 8 && /^\d+$/.test(c) ? c.match(/.{1,4}/g)!.join(" ") : n;
}

function hexToRgb(hex: string): [number, number, number] {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex ?? "");
  const v = m ? parseInt(m[1], 16) : 0x2b2f3a;
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
}

function luminance([r, g, b]: [number, number, number]) {
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
}
