# Orange Robot economy — spec v0.2

Status: proposal. Nothing here is built. Numbers are starting points to tune.
Not legal advice: items marked ⚖ need a lawyer's eye before launch.


## 0. Decisions log (v0.2) — these override anything below that conflicts

Made by the owner on 2026-10-11:

1. **No unlocks of any kind for now.** Sats are for recognition only. Digital
   rewards on the website (a "pog" image, a book chapter) are back-burnered; if
   they ever return they must be purely digital, with no real-world value, and
   get a legal read first. The book itself is the product, so chapters stay out.
2. **No transfers.** Section 8 is struck. No sending sats between accounts.
3. **Short tests are welcome.** Minimum forward test is **7 days ("Sprint")**,
   because people want results quickly. Long tests earn a separate
   **Marathon** award for rules that withstand the test of time (§5).
4. **Stay clear of legal gray areas.** Where in doubt, leave it out: no cash
   value, no purchases of sats, no redemption, no prizes, no gambling-like
   mechanics (no stakes, no pools funded by players, no random loot boxes).
5. **Haptics and sound** are part of the design, with a switch to turn each off.
6. **Background engagement:** push notifications when a robot paper-buys or
   paper-sells (see the notes on how this must work in §14).

## 1. What this is

A small, closed-loop game economy that connects the games, the Lab and the
website. Players earn **virtual sats**, build a public identity (a handle), and
get recognition for robots whose rules held up on days that had not happened
when the rules were locked. Over time it becomes the "Bitcoin city" on
theorangerobot.com.

## 2. Principles

1. **Closed loop.** Virtual sats have no cash value, cannot be bought with real
   money, cannot be cashed out, and are not Bitcoin. This is what keeps the
   project out of gambling, securities and crypto-rewards territory. ⚖
2. **Reward what is hard to fake.** Reward results on *unseen* time, not
   hindsight returns. A forward test cannot be overfit.
3. **The server is the judge.** Clients propose; the server recomputes. The
   engine is deterministic, so any report can be re-run exactly.
4. **Scarcity by design.** A fixed emission budget per season, halving each
   season. Prices of cosmetic sinks can then be tuned against a known supply.
5. **Privacy first.** No email, no phone, no real name. A device key and a
   handle. The usage counters already follow this rule.
6. **Stage it.** Each phase is useful on its own and can be the last one.

## 3. Identity

- **Account** = an Ed25519 key pair generated on the device (Keychain), plus a
  public **handle** (3–16 chars, unique, case-insensitive, profanity-filtered).
- **Recovery** = a 12-word phrase shown once at creation (BIP-39 style). Lose
  it and the device, lose the account. No email reset, by design.
- Every write is signed by the device key. The server stores the public key,
  the handle, and nothing else about the person.
- Handle changes cost sats (anti-impersonation) and are limited to one per 30 days.
- Existing leaderboard "initials" are *not* migrated as identities (they are
  claimable by anyone). The legacy Vault stays as a read-only hall of fame; the
  new economy starts every account at zero.

## 4. Where sats come from (minting)

| Source | Reward | Verified by | Daily cap per account |
|---|---|---|---|
| **Trader game run** (random start only) | 1 sat per $1 profit, max 5,000 per run | Leaderboard check (see §9: needs server-side run proof) | 10,000 |
| **Forward test finished** (Lab) | see §5 | Server recompute | 3 payouts/day |
| **Mining game / other games** | per-game table, small | Same pattern as the trader game | 2,000 each |
| **Daily visit** | 10 sats | Signed request | once per UTC day |
| **Streaks / seasons / badges** | cosmetic, no sats | n/a | n/a |

Global rule: total sats minted per season never exceeds the **season budget**
(§7). When it is spent, earning pauses until the next season.

## 5. Forward-test payouts (the core mechanic)

Two tracks, both judged only on days that had not happened when the rules were
locked:

**Sprint (7 days)** — quick feedback, small reward.

- Eligible: ran the full 7 days, rules fingerprinted before day 1 closed.
- No minimum-trade rule (a week often has 0–1 trades) — but a Sprint pays only
  the small participation amount if it made **no** trades.
- Payout: `base 15` + `4 × clamp(profit, 0, 15)` + `4 × clamp(excess, 0, 15)`,
  capped at **150**. Max 2 Sprint payouts per account per day.

**Marathon (30 / 60 / 90 days)** — the "stood the test of time" award.

- Eligible: ran the full length; ≥ 2 closed trades; not a near-duplicate
  of a robot already paid this season (normalized-rules hash).
- Payout: `base` (40 / 90 / 150) + `8 × clamp(excess, 0, 40)` +
  `4 × clamp(profit, 0, 40)` + `6 × clamp(safety, 0, 30)`, capped at
  800 / 1,600 / 2,500.
- **Marathon badge** (cosmetic, no sats) when a robot completes 30, 60, 90
  days **and** stays ahead of just holding at the end.
- **Longevity bonus:** a Sprint that is then *continued* as a Marathon with
  the same locked rules keeps its original start date, so one robot can earn
  both tracks without being re-tuned.

Definitions (same as before): `excess` = robot return − holding return in
percentage points; `profit` = max(robot return, 0); `safety` = how much smaller
the robot's worst fall was than holding's.

Both tracks: results computed by the server from its own stored candles; paid
7 days after the test ends; losing robots are never charged.

> Because a daily-candle robot makes only ~7 decisions in a week, Sprint
> results are mostly luck. That is why they pay little and why Marathon pays
> much more. The app labels Sprint results "early look".

## 6. Sinks (what sats are for)

Sinks keep the supply from just inflating and give sats a reason to exist.

- Extra concurrent live-test slots (free: 3 at once).
- Handle change, profile flair, robot-page themes.
- Cosmetic **seasonal badges** (no pools, no prizes funded by players).
- City cosmetics (plots, signs, decorations) in the Bitcoin-city phase.

Never a sink: anything redeemable for money, goods, store discounts, content
unlocks or Bitcoin (owner decision 2026-10-11). ⚖

## 7. Emission

- **Season** = 90 days.
- Season 1 budget: **5,000,000** sats. Each season the budget **halves**
  (on-theme). Unspent budget does not roll over.
- The budget is public on the website ("1,820,310 of 5,000,000 minted").
- Per-account daily caps (§4) make it impossible for one account to drain it.

## 8. Transfers — struck (v0.2)

No transfers between accounts. Revisit only if there is a clear reason and a
legal read. This removes the largest abuse surface.

## 9. Anti-abuse

| Threat | Defence |
|---|---|
| Fake scores posted straight to the API (true today) | Signed requests; **server-side run proof**: the app sends the sequence of orders, the server replays it on the price data and recomputes the score |
| Backdated "predictions" | Server timestamps fingerprints; start day must be ≥ the day of receipt |
| Many accounts / handle farms | Per-account caps, 7-day delay, no transfers for young accounts, near-duplicate-rule detection, IP/device rate limits (stored short-term, never linked to the person) |
| Overfit robots | Only forward tests pay; practice-period results never do |
| Price-feed manipulation | The **server** records daily candles itself (Kraken, cross-checked with Coinbase; disagreement > 1% pauses payouts) |
| Hostile notes / handles | Filter + report + block + manual takedown (App Store 1.2) |

## 10. Server design (sketch)

- **Cloudflare Worker + D1** (SQLite) for accounts, robots, reports, ledger.
  Balances are derived from an **append-only ledger** with idempotency keys,
  so retries cannot double-pay. Durable Object only if contention appears.
- A **cron** pulls and stores daily candles at 00:05 UTC.
- A **JS port of the Backtester**, checked against Swift golden outputs in CI
  (the Swift package already has the reference tests).
- Existing `orange-robot-leaderboard` Worker is left alone and later retired.

## 11. Phases

| Phase | Ships | Exit criteria |
|---|---|---|
| **0** | Notebook, live tests (done, on device) | — |
| **1** | Handles + keys, share a report to a public gallery (no sats), report/block, daily candles recorded server-side | People actually share; moderation load is manageable |
| **2** | Fingerprint timestamping + forward-test payouts + server recompute + public robot pages + season budget | Payout mismatch rate ≈ 0; no unexplained minting |
| **3** | Wallet visible, cosmetic sinks, Marathon badges | Abuse reports low |
| **4** | Mining + other games feed the same wallet; city | — |

## 12. Open decisions

Resolved in §0: unlocks (none), transfers (none), minimum test length (7 days).
Still open:

1. **Handles in phase 1**, or anonymous until phase 2? (My advice: handles —
   people want a name on a public robot.)
2. **Public notes:** opt-in per report (advice) or on by default?
3. **Season length / Season-1 budget:** 90 days / 5,000,000 okay?
4. **Legacy Vault:** keep as a hall of fame (advice) or retire?

## 13. Risks I want on record

- **Complexity:** this is a real product (accounts, ledger, moderation). It is
  weeks of work, not days.
- **Perverse incentives:** any reward shapes behaviour. Expect people to chase
  the formula; monitor and retune each season.
- **Regulatory:** virtual currency, UGC and any link to real-world value
  need a legal check before phase 2 goes live. ⚖
- **Small-sample luck:** 30-day, few-trade results are noisy; the min-trades
  rule and the delay mitigate but do not remove it.

## 14. Background engagement (how it actually has to work)

iOS does not let an app run a robot continuously in the background. What works:

- **Server-side evaluation + push notifications (APNs).** The server holds
  each locked robot, evaluates it when the daily candle closes (00:05 UTC) and
  sends "Your robot paper-bought at $X". Reliable, battery-free, and matches
  how daily-candle robots actually decide. Needs: a server, an APNs key from
  the Apple Developer account, and the user's explicit notification
  permission. Arrives with phase 2 (it needs the same server).
- **Local best-effort (no server, earlier):** schedule a background refresh
  that wakes the app after each daily close, recompute, and post a *local*
  notification if the robot traded. iOS decides when/if it runs, so it may
  arrive late or not at all; the app shows the result on next open either way.
- **Faster robots (optional):** live tests could use hourly candles (the
  exchange feed provides ~30 days of them) so a Sprint has ~170 decisions
  instead of 7. More exciting, but a different kind of robot, and noisier.

Notifications are opt-in, can be silenced per robot, and never contain
anything beyond the robot's name and the paper action.

## 15. Feel: haptics and sound

- Haptics: buy, sell, breaking news, finished test, payout. System haptics
  only (no private APIs).
- Sound: short, quiet cues for the same events. Synthesised tones bundled
  with the app, no third-party assets.
- **Settings: separate switches for Haptics and Sound**, default on, and
  honour the phone's silent switch and "Reduce motion".
- Never required for play; every cue has a visual equivalent.
