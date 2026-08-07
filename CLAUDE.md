# The Orange Robot — main site

Static site for theorangerobot.com, served by GitHub Pages from this repo (`WebMaven50/Orange`). No build step — HTML files are edited and pushed directly.

## Multi-machine workflow — read this first

This repo gets worked on from more than one machine (at least a Mac mini and a MacBook Pro), sometimes in parallel Claude Code sessions that don't know about each other. There is no other coordination mechanism, so:

- **Before starting any work**, run `git fetch origin && git log HEAD..origin/main --oneline`. If that shows commits, `git pull` and actually read what changed before assuming you know the current state of any file you're about to edit.
- **After finishing a change and getting confirmation to ship it**, commit and `git push` right away — don't leave work uncommitted/unpushed across a session boundary. A change sitting locally on one machine is invisible to work happening on the other.
- If you find unexpected commits from "yourself" (same git author identity) that you have no memory of making, that's the other machine, not a bug — read the diffs before touching anything nearby.

## Related infrastructure

- **`orange-robot-leaderboard`** — separate Cloudflare Worker (KV-backed) powering the games leaderboard (`games/leaderboard.js`). No git history of its own; pull its actual deployed source via the Cloudflare API before editing it (see the pull-then-edit-then-deploy pattern used for the store worker in the OrangeRobotStore repo's CLAUDE.md — same technique applies here).
- **`WebMaven50/OrangeRobotStore`** — separate repo/site (buy.html, admin pages) backed by the `orange-robot-store` Worker. Has its own CLAUDE.md with the Worker-pull workflow.
- Games pages (`games/*.html`) load live BTC price data from CoinGecko/mempool.space and hit the leaderboard Worker directly — check `games/index.html`'s CSP `connect-src` if adding new external calls.

## Content-Security-Policy

Every HTML page carries a `<meta http-equiv="Content-Security-Policy">` tag (GitHub Pages can't send real HTTP headers, so this is the only enforcement mechanism available — it does not cover clickjacking/X-Frame-Options or HSTS). If a page starts fetching from or loading a script/font from a new external host, that host needs to be added to the relevant `-src` directive in that page's CSP tag or the browser will silently block it.
