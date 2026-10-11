# Orange Robot economy — spec v0.1 (draft for review)

Status: proposal. Nothing here is built. Numbers are starting points to tune.
Not legal advice: items marked ⚖ need a lawyer's eye before launch.

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

## 5. Forward-test payout (the core mechanic)

Eligibility, all required:

- Started on the website's clock: the client submits the **rule fingerprint**
  *before* the first day closes; the server timestamps it and stores it. A
  fingerprint first seen after its start day is rejected.
- Ran the full horizon: 30 or 90 days (14-day tests are practice, no payout).
- At least **2 closed trades** (a robot that never trades has no evidence).
- The rules are not a near-duplicate of a robot already paid in this season
  (normalized-rules hash; prevents farming the same idea).

Score (computed by the server from its own stored daily candles, never the
client's):

```
excess   = robot return − holding return        (percentage points)
profit   = max(robot return, 0)
safety   = max(holding max-drawdown − robot max-drawdown, 0)

payout   = base(horizon)
         + 8  × clamp(excess, 0, 40)      // beat holding
         + 4  × clamp(profit, 0, 40)      // made money
         + 6  × clamp(safety, 0, 30)      // smoother ride
         capped at payout_cap(horizon)
```

Starting values: `base` = 40 (30-day) / 150 (90-day); `payout_cap` = 800 / 2,500.
The mix rewards beating the market, profiting, *and* avoiding big falls, so
sitting in cash through a crash scores something (safety) but not a lot.

Notes:
- Losing robots still receive `base` only if they finish; they are never
  charged. (Players should not be punished for experimenting.)
- Payouts are credited **7 days after** the test ends (a short delay makes
  coordinated gaming and data corrections easier to catch).
- Results are public on the robot's page with the fingerprint and rules.

## 6. Sinks (what sats are for)

Sinks keep the supply from just inflating and give sats a reason to exist.

- Extra concurrent live-test slots (free: 3 at once).
- Handle change, profile flair, robot-page themes.
- Entry to **seasonal cups** (a pool paid back out to top forward tests).
- City cosmetics (plots, signs, decorations) in the Bitcoin-city phase.
- A small **burn** (2%) on every transfer once transfers exist.

Never a sink: anything redeemable for money, goods, store discounts or
Bitcoin. ⚖ (Store discounts need a specific legal read first.)

## 7. Emission

- **Season** = 90 days.
- Season 1 budget: **5,000,000** sats. Each season the budget **halves**
  (on-theme). Unspent budget does not roll over.
- The budget is public on the website ("1,820,310 of 5,000,000 minted").
- Per-account daily caps (§4) make it impossible for one account to drain it.

## 8. Transfers (phase 3 only)

Off by default. When enabled:

- Account must be ≥ 14 days old and have completed ≥ 1 forward test.
- Sats received in the last 7 days cannot be re-sent (stops chain-laundering).
- Daily send limit: 500 sats; max 5 recipients/day; 2% burn.
- Every transfer is public in the ledger with both handles.
- Block/report is available on any account.

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
| **3** | Wallets visible, sinks, seasonal cups, limited transfers | Gini/whale check; abuse reports low |
| **4** | Mining + other games feed the same wallet; city | — |

## 12. Open decisions for you

1. **Handles in phase 1** — or stay anonymous until phase 2?
2. **Are sats ever allowed to unlock anything of real value** (store
   discount, signed copy, early chapter)? My advice: no, at least until a
   lawyer has looked. ⚖
3. **Public notes** — opt-in per report (my advice) or on by default?
4. **Season length and Season-1 budget** — 90 days / 5,000,000 okay?
5. **Do you want transfers at all**, given the abuse surface? A "gift" with
   tight caps is the middle path.
6. **The legacy Vault** — keep as a hall of fame (my advice), or migrate?

## 13. Risks I want on record

- **Complexity:** this is a real product (accounts, ledger, moderation). It is
  weeks of work, not days.
- **Perverse incentives:** any reward shapes behaviour. Expect people to chase
  the formula; monitor and retune each season.
- **Regulatory:** virtual currency, UGC and any link to real-world value
  need a legal check before phase 2 goes live. ⚖
- **Small-sample luck:** 30-day, few-trade results are noisy; the min-trades
  rule and the delay mitigate but do not remove it.
