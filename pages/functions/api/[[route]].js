/**
 * Feedloop API as a Cloudflare Pages Function — SAME ORIGIN as the dashboard.
 *
 * This exists because `workers.dev` is blocked on some networks/DNS filters
 * (it happened to Ali, even in incognito). Serving the API from the same
 * pages.dev origin as the page removes both the blocked domain and CORS.
 *
 * Routes:  POST /api/login        email+password -> 180-day JWT
 *          ALL  /api/gh/<path>    proxy to api.github.com, path-locked
 *
 * Secrets (Pages project env vars): LOGIN_EMAIL, LOGIN_HASH ("saltHex:hashHex",
 * PBKDF2-SHA256 100k), SESSION_SECRET, GITHUB_PAT.
 */

const REPO = "IamAliSufyan/unloop-app";
const PATH_PREFIX = `/repos/${REPO}/contents/docs/marketing/feedloop/`;
const SESSION_DAYS = 180;

const enc = new TextEncoder();
const hex = (b) => [...new Uint8Array(b)].map(x => x.toString(16).padStart(2, "0")).join("");
const b64url = (b) => btoa(String.fromCharCode(...new Uint8Array(b)))
  .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlJSON = (o) => b64url(enc.encode(JSON.stringify(o)));
const json = (status, body) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function pbkdf2Hex(password, saltHex, iterations = 100000) {
  const salt = new Uint8Array(saltHex.match(/.{2}/g).map(h => parseInt(h, 16)));
  const key = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt, iterations }, key, 256);
  return hex(bits);
}
const hmacKey = (secret) =>
  crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);

async function signJWT(payload, secret) {
  const head = b64urlJSON({ alg: "HS256", typ: "JWT" });
  const body = b64urlJSON(payload);
  const sig = await crypto.subtle.sign("HMAC", await hmacKey(secret), enc.encode(`${head}.${body}`));
  return `${head}.${body}.${b64url(sig)}`;
}
async function verifyJWT(token, secret) {
  const p = (token || "").split(".");
  if (p.length !== 3) return null;
  const sig = Uint8Array.from(atob(p[2].replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0));
  if (!await crypto.subtle.verify("HMAC", await hmacKey(secret), sig, enc.encode(`${p[0]}.${p[1]}`))) return null;
  try {
    const payload = JSON.parse(atob(p[1].replace(/-/g, "+").replace(/_/g, "/")));
    return (payload.exp && payload.exp > Date.now() / 1000) ? payload : null;
  } catch { return null; }
}
function safeEqual(a, b) {
  if (a.length !== b.length) return false;
  let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

export async function onRequest(context) {
  const { request, env } = context;
  const url = new URL(request.url);
  const route = url.pathname.replace(/^\/api/, "");

  if (route === "/health" || route === "" || route === "/") {
    return json(200, { ok: true, service: "feedloop-pages" });
  }

  if (route === "/login" && request.method === "POST") {
    let body;
    try { body = await request.json(); } catch { return json(400, { error: "bad json" }); }
    const email = (body.email || "").trim().toLowerCase();
    const [saltHex, wantHex] = (env.LOGIN_HASH || ":").split(":");
    const gotHex = await pbkdf2Hex(body.password || "", saltHex || "00");
    if (email !== (env.LOGIN_EMAIL || "").toLowerCase() || !safeEqual(gotHex, wantHex || "")) {
      return json(401, { error: "wrong email or password" });
    }
    const exp = Math.floor(Date.now() / 1000) + SESSION_DAYS * 86400;
    return json(200, { token: await signJWT({ sub: email, exp }, env.SESSION_SECRET), exp });
  }

  if (route.startsWith("/gh/")) {
    const auth = (request.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!await verifyJWT(auth, env.SESSION_SECRET)) return json(401, { error: "not signed in" });

    const ghPath = route.slice(3); // strip "/gh"
    if (!ghPath.startsWith(PATH_PREFIX)) return json(403, { error: "path outside feedloop scope" });

    const init = {
      method: request.method,
      headers: {
        "Authorization": `Bearer ${env.GITHUB_PAT}`,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "feedloop-pages",
      },
    };
    if (request.method !== "GET" && request.method !== "HEAD") init.body = await request.text();
    return fetch(`https://api.github.com${ghPath}${url.search}`, init);
  }

  return json(404, { error: "not found" });
}
