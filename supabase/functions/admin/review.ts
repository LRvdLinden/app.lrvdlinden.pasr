// Review-account voor Apple App Review: invoer controleren. Het wachtwoord gaat alleen door naar de auth admin API
// en wordt nergens bewaard, gelogd of teruggestuurd.

export type ReviewInput = { email: string; password: string; firstName: string; reset: boolean };

const EMAIL = /^[^\s@<>()",;:]{1,64}@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/;

export function cleanReview(body: Record<string, unknown>): { ok: true; value: ReviewInput } | { ok: false; error: string } {
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const password = typeof body.password === "string" ? body.password : "";
  const name = typeof body.first_name === "string" ? body.first_name.replace(/[<>]/g, "").replace(/\s+/g, " ").trim().slice(0, 40) : "";
  if (!EMAIL.test(email) || email.length > 254) return { ok: false, error: "bad_email" };
  // minimaal 10 tekens, met letters én cijfers; maximaal 72 bytes (bcrypt)
  if (password.length < 10 || new TextEncoder().encode(password).length > 72 || !/[a-zA-Z]/.test(password) || !/\d/.test(password)) {
    return { ok: false, error: "weak_password" };
  }
  return { ok: true, value: { email, password, firstName: name || "App Review", reset: body.reset === true } };
}

/** Bestaat het account al? (Foutmelding van de auth admin API.) */
export const alreadyExists = (message: string, status?: number) =>
  status === 422 || /already (been )?registered|already exists|email_exists/i.test(message);
