// Pasr beheer › Mail: wie mag de functie aanroepen. Twee kopregels, geen JWT:
//   x-pasr-admin  de functie admin (heeft al de sessiecontrole van het beheer) stuurt door met een sleutel die uit
//                 PASR_TOKEN_SECRET volgt (HMAC-SHA256 van "pasr-mail-admin"); beide functies rekenen hem zelf uit
//   x-pasr-cron   pg_cron/pg_net (pasr_mail_poll_kick) met het hook_secret uit pasr_secret; alleen poll_inbox
// Vergelijken zonder tijdverschil.

export function sameBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}
export const sameText = (a: string, b: string) => {
  const te = new TextEncoder();
  return sameBytes(te.encode(a), te.encode(b));
};

/** De sleutel tussen admin en mail (hex). Leeg als PASR_TOKEN_SECRET te kort is. */
export async function adminKey(tokenSecret: string): Promise<string> {
  if (!tokenSecret || tokenSecret.length < 32) return "";
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(tokenSecret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode("pasr-mail-admin")));
  return Array.from(sig, (x) => x.toString(16).padStart(2, "0")).join("");
}
export async function adminOk(given: string | null, tokenSecret: string): Promise<boolean> {
  if (!given || given.length > 200) return false;
  const want = await adminKey(tokenSecret);
  return want !== "" && sameText(given, want);
}
