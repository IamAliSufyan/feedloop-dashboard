# Feedloop dashboard

Review dashboard for Unloop's Feedloop content pipeline.

**Live: https://feedloop.pages.dev** (sign in with email + password)

Cloudflare Pages hosts the page **and** its API on one origin, so there are no
cross-domain calls: `pages/index.html` is the dashboard, and
`pages/functions/api/[[route]].js` is the Pages Function serving `/api/login`
(email + password -> 180-day JWT) and `/api/gh/*` (GitHub contents proxy,
path-locked to `docs/marketing/feedloop/` in the private `unloop-app` repo).
No content or secrets live in this repo; secrets are Pages env vars.

`index.html` at the root is only a redirect for the old GitHub Pages URL.
**Edit `pages/index.html`** — that is the real dashboard.

## Operate

```bash
pages/deploy-pages.sh    # deploy page + API, set secrets
pages/verify-pages.sh    # prove it end to end (login, proxy, scope guard)
```

Credentials and tokens live outside the repo in `~/.config/unloop-feedloop/`
(`dashboard-login.txt`, `cloudflare.env`, `github-pat.env`, `session-secret.txt`).
`pages/dns-fix.cjs` (gitignored) forces public DNS resolvers for wrangler on a
machine whose router DNS is unreliable.

Actions in the dashboard (approve / reject / edit / flag) are committed to
`unloop-app@main`; Claude's publisher pushes approved posts to Postiz.
Pipeline source of truth: `unloop-app/docs/marketing/feedloop/`.
