# The Orange Robot — main site

Static site for theorangerobot.com, served by GitHub Pages from this repo (`WebMaven50/Orange`). No build step — HTML files are edited and pushed directly.

## Multi-machine workflow — read this first

This repo gets worked on from more than one machine (at least a Mac mini and a MacBook Pro), sometimes in parallel Claude Code sessions that don't know about each other. There is no other coordination mechanism, so:

- **Before starting any work**, run `git fetch origin && git log HEAD..origin/main --oneline`. If that shows commits, `git pull` and actually read what changed before assuming you know the current state of any file you're about to edit.
- **After finishing a change and getting confirmation to ship it**, commit and `git push` right away — don't leave work uncommitted/unpushed across a session boundary. A change sitting locally on one machine is invisible to work happening on the other.
- If you find unexpected commits from "yourself" (same git author identity) that you have no memory of making, that's the other machine, not a bug — read the diffs before touching anything nearby.

## Related infrastructure

- **`orange-robot-leaderboard`** — separate Cloudflare Worker (KV-backed) powering the games leaderboard (`games/leaderboard.js`). No git history of its own; pull its actual deployed source via the Cloudflare API before editing it (same technique as `orange-robot-store` below).
- Games pages (`games/*.html`) load live BTC price data from CoinGecko/mempool.space and hit the leaderboard Worker directly — check `games/index.html`'s CSP `connect-src` if adding new external calls.

## The store (`/store/`)

`buy.html`, `admin-orders.html`, `admin-settings.html`, `admin-downloads.html`, `order-status.html`, and `redeem.html` live under `/store/` in this repo, served at `theorangerobot.com/store/*`. This used to be a separate repo (`WebMaven50/OrangeRobotStore`) on `webmaven50.github.io` — that repo now only holds redirect stubs for old links (including ones already emailed to real customers), so **don't delete it**, and don't add new pages there.

Backed by the `orange-robot-store` Cloudflare Worker. It has no git history of its own — the deployed script is the only source of truth. Pull it directly from the Cloudflare API before editing:

```bash
TOKEN=$(node -e "
const fs=require('fs');
const toml=fs.readFileSync('/Users/victorgelfo/Library/Preferences/.wrangler/config/default.toml','utf8');
const m=toml.match(/oauth_token\s*=\s*\"([^\"]+)\"/);
console.log(m ? m[1] : '');
")
ACCOUNT_ID="cb4c4cc98d136e028b55d93b37356c2f"
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/scripts/orange-robot-store" \
  -o /tmp/worker-raw.bin
# response is multipart/form-data; extract the "index.js" part before editing.
# Each deploy re-wraps the source in esbuild's __name/__defProp helpers on top of
# whatever was already there — strip that boilerplate back to clean source before
# editing, or it compounds every cycle. (Diff before/after the strip to confirm
# only wrapper lines were removed.)
```

Then edit, `node --check` for syntax, test the changed logic standalone against extracted code blocks, `wrangler deploy --dry-run` to confirm bindings, get confirmation, `wrangler deploy`, then verify live with curl. `wrangler.jsonc` for this Worker isn't committed anywhere — reconstruct it from the account settings (`.../workers/scripts/orange-robot-store/settings`) and schedules (`.../schedules`) endpoints if starting a fresh scratch directory.

Key things about the store's data model:
- Digital delivery (epub + audiobook) is **gated, not honor-system**: a transaction ID is required at checkout, and `/download/epub` / `/download/audiobook` only release the file once `order.status === "paid"` or `order.mempoolSeen` (visible on the network, even pre-confirmation) — checked server-side. Both reuse the same anti-replay protection (a txid can't be claimed by more than one order).
- Each digital/audiobook order also caps at 5 downloads (`downloadCapExceeded`) to stop a link from being shared/reused indefinitely — admin can reset it per-order in `admin-orders.html` after manually verifying the buyer.
- CORS on the Worker is locked to `https://theorangerobot.com` — the only legitimate frontend origin now that the store lives here. Local testing from `file://` or `localhost` will show fetches failing; that's expected, not a bug.
- The epub, audiobook, and audiobook preview clip live in the R2 bucket `orange-robot-files`, served through the Worker (not static files in any repo) — swappable from `admin-settings.html` without a git push. The full audiobook uses chunked multipart upload (R2 binding's native multipart API, ~20MB parts) since it can run 280–500MB, well past what a single request to the Worker can carry.
- Test orders (`/admin/test-order`) and promo-code redemptions (`/promo/redeem`) both create real order records tagged `isTest` / `isPromoRedemption` so they're visually distinct in `admin-orders.html` and don't trigger real customer notification emails.
- Secrets (write-only, never viewable again once set): `ADMIN_PASSWORD`, `RESEND_API_KEY`. Plain var (visible to anyone with Cloudflare dashboard access): `NOTIFY_EMAIL`.

## Content-Security-Policy

Every HTML page carries a `<meta http-equiv="Content-Security-Policy">` tag (GitHub Pages can't send real HTTP headers, so this is the only enforcement mechanism available — it does not cover clickjacking/X-Frame-Options or HSTS). If a page starts fetching from or loading a script/font from a new external host, that host needs to be added to the relevant `-src` directive in that page's CSP tag or the browser will silently block it.
