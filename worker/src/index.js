/**
 * Feedloop auth + GitHub proxy worker.
 *
 * Why this exists: the dashboard is a static GitHub Pages site, which cannot
 * hold secrets or verify a password. This worker holds the GitHub token as a
 * deploy-time secret, verifies Ali's email+password, issues a long-lived
 * session token (JWT), and proxies ONLY the Feedloop content directory of the
 * repo. Even a leaked session can touch nothing but the marketing pipeline.
 *
 * Secrets (wrangler secret put): LOGIN_EMAIL, LOGIN_HASH ("saltHex:hashHex",
 * PBKDF2-SHA256 100k iters), SESSION_SECRET, GITHUB_PAT.
 */

const ALLOWED_ORIGINS = new Set([
  "https://iamalisufyan.github.io",
  "http://localhost:8765",
  "http://127.0.0.1:8765",
]);
const REPO = "IamAliSufyan/unloop-app";
const PATH_PREFIX = `/repos/${REPO}/contents/docs/marketing/feedloop/`;
const SESSION_DAYS = 180;

const enc = new TextEncoder();
const hex = (buf) => [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, "0")).join("");
const b64url = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)))
  .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlJSON = (obj) => b64url(enc.encode(JSON.stringify(obj)));

function cors(origin) {
  const o = ALLOWED_ORIGINS.has(origin) ? origin : "https://iamalisufyan.github.io";
  return {
    "Access-Control-Allow-Origin": o,
    "Access-Control-Allow-Methods": "GET,PUT,POST,DELETE,OPTIONS",
    "Access-Control-Allow-Headers": "Authorization,Content-Type",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}
const json = (status, body, origin) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...cors(origin) } });

async function pbkdf2Hex(password, saltHex, iterations = 100000) {
  const salt = new Uint8Array(saltHex.match(/.{2}/g).map(h => parseInt(h, 16)));
  const key = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations }, key, 256);
  return hex(bits);
}

async function hmacKey(secret) {
  return crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}
async function signJWT(payload, secret) {
  const head = b64urlJSON({ alg: "HS256", typ: "JWT" });
  const body = b64urlJSON(payload);
  const sig = await crypto.subtle.sign("HMAC", await hmacKey(secret), enc.encode(`${head}.${body}`));
  return `${head}.${body}.${b64url(sig)}`;
}
async function verifyJWT(token, secret) {
  const parts = (token || "").split(".");
  if (parts.length !== 3) return null;
  const data = enc.encode(`${parts[0]}.${parts[1]}`);
  const sig = Uint8Array.from(atob(parts[2].replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0));
  const ok = await crypto.subtle.verify("HMAC", await hmacKey(secret), sig, data);
  if (!ok) return null;
  try {
    const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
    if (!payload.exp || payload.exp < Date.now() / 1000) return null;
    return payload;
  } catch { return null; }
}

/** Constant-time-ish string compare (both hex, same length in the happy path). */
function safeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const origin = req.headers.get("Origin") || "";

    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(origin) });

    // --- login ---
    if (url.pathname === "/login" && req.method === "POST") {
      let body;
      try { body = await req.json(); } catch { return json(400, { error: "bad json" }, origin); }
      const email = (body.email || "").trim().toLowerCase();
      const password = body.password || "";
      const [saltHex, wantHex] = (env.LOGIN_HASH || ":").split(":");
      const gotHex = await pbkdf2Hex(password, saltHex || "00");
      const emailOK = email === (env.LOGIN_EMAIL || "").toLowerCase();
      if (!emailOK || !safeEqual(gotHex, wantHex || "")) {
        return json(401, { error: "wrong email or password" }, origin);
      }
      const exp = Math.floor(Date.now() / 1000) + SESSION_DAYS * 86400;
      const token = await signJWT({ sub: email, exp }, env.SESSION_SECRET);
      return json(200, { token, exp }, origin);
    }

    // --- authenticated GitHub proxy, scoped to the feedloop content dir ---
    if (url.pathname.startsWith("/gh/")) {
      const auth = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
      const session = await verifyJWT(auth, env.SESSION_SECRET);
      if (!session) return json(401, { error: "not signed in" }, origin);

      const ghPath = url.pathname.slice(3); // strip "/gh"
      if (!ghPath.startsWith(PATH_PREFIX)) {
        return json(403, { error: "path outside feedloop scope" }, origin);
      }
      const target = `https://api.github.com${ghPath}${url.search}`;
      const init = {
        method: req.method,
        headers: {
          "Authorization": `Bearer ${env.GITHUB_PAT}`,
          "Accept": "application/vnd.github+json",
          "X-GitHub-Api-Version": "2022-11-28",
          "User-Agent": "feedloop-dashboard-worker",
        },
      };
      if (req.method !== "GET" && req.method !== "HEAD") init.body = await req.text();
      const resp = await fetch(target, init);
      const out = new Response(resp.body, resp);
      for (const [k, v] of Object.entries(cors(origin))) out.headers.set(k, v);
      return out;
    }

    if (url.pathname === "/") return json(200, { ok: true, service: "feedloop-worker" }, origin);
    return json(404, { error: "not found" }, origin);
  },
};
