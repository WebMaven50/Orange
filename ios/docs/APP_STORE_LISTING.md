# App Store setup: Orange Robot (game) and Orange Robot Lab

Everything to paste into App Store Connect. Items marked 🔸 need a decision
or an action from the owner. Nothing here has been submitted.

## 0. Before you start

| | Game | Lab |
|---|---|---|
| Bundle ID 🔸 (permanent once created) | `com.theorangerobot.trader` | `com.theorangerobot.lab` |
| Display name | Orange Robot | Orange Robot Lab |
| Primary category | Games → Simulation | Education |
| Secondary category | Education | Games → Simulation |
| Price | Free | Free |
| Age rating (answer the questionnaire; expected) | 4+ | 4+ |
| Version / build | 1.0 (1) | 1.0 (1) |

**Avoid the Finance category.** It triggers extra review (financial-services
rules). These apps are a game and an educational simulator with no real money.

**Names are unique across the store.** "Orange Robot" may be taken; check when
creating the app record. Fallbacks: "Orange Robot: BTC Sim", "The Orange Robot
Game".

URLs required by Apple:
- Support URL: https://theorangerobot.com
- Marketing URL: https://theorangerobot.com
- Privacy Policy URL 🔸: https://theorangerobot.com/privacy.html (page must exist; draft in §5)

## 1. Orange Robot (game)

**Subtitle (30):** Bitcoin Trading Simulator

**Promotional text (170):**
Trade real Bitcoin history from 2010 to today with $100,000 of pretend money.
Beat the market, make the leaderboard, and meet the robot.

**Description:**
> Step into Bitcoin's real history and trade it.
>
> ORANGE ROBOT is a trading simulator and game. You start with $100,000 of
> virtual money in a random moment from 2010 to today, or pick a famous moment
> yourself. Buy, sell, short, set limit and stop orders, and try to reach
> $1,000,000 before the market takes it away.
>
> • Real daily Bitcoin prices from 2010 onward
> • Market, limit, stop and trailing-stop orders
> • Candles, hollow candles, bars, line and area charts
> • Moving averages, Bollinger Bands, RSI and MACD on demand
> • Breaking-news banners from the real events of each era
> • Sleep, pause and three game speeds
> • A global leaderboard
> • Hear the prologue of the novel The Orange Robot
> • Optional messages and price alerts (off unless you turn them on)
>
> This is a game played with play money. You start with $100,000 in play money.
> All money is virtual, prices are historical, and virtual sats have no cash
> value. Nothing here is financial advice.
>
> The game is part of the world of The Orange Robot, a novel by V.J. Alden.

**Keywords (100):** bitcoin,btc,crypto,trading,simulator,game,stock,market,satoshi,robot,novel,learn,invest

**What's new (1.0):** First release.

## 2. Orange Robot Lab

**Subtitle (30):** Bitcoin Strategy Simulator

**Promotional text (170):**
Teach a robot when to buy and sell, test it on real Bitcoin history, then lock
its rules and watch it on days that haven't happened yet.

**Description:**
> Build a trading robot, then find out if it would have worked.
>
> ORANGE ROBOT LAB is an educational simulator. Choose simple rules (an RSI
> level, a moving-average cross, a price drop, a stop-loss, a dollar-cost
> schedule), run them over any stretch of Bitcoin history, and see how they
> compare with just holding.
>
> • Build your own rules or start from a template
> • Dollar-cost averaging with fixed amounts and reinvested profits
> • "Find me rules": the robot tries thousands of ideas, then tests the best
>   on time it has never seen, so you learn about overfitting
> • Watch any robot trade day by day with a replay
> • A plain-English analysis of what it did right and wrong
> • A score against holding: 0 is even, +100 is double the money
> • A notebook that saves every test automatically
> • Live tests: lock the rules, then judge them on real days as they happen
> • Optional alerts when a live robot makes a paper trade
>
> Everything runs on your phone. No account, no real money, no trading.
> Results come from past data and do not predict the future. This app is for
> learning and entertainment and is not financial advice.
>
> From the world of The Orange Robot, a novel by V.J. Alden.

**Keywords (100):** bitcoin,btc,crypto,strategy,backtest,simulator,learn,dca,rsi,trading,robot,education

**What's new (1.0):** First release.

## 3. App Privacy answers

Apple asks what each app collects. Answer honestly; both are very light.

### Game
| Data | Collected? | Linked to you? | Used for tracking? | Purpose |
|---|---|---|---|---|
| Usage / product interaction (anonymous counters such as "prologue played") | Yes | No | No | Analytics |
| Other user content (3-letter initials and score if the player posts to the leaderboard) | Yes | No | No | App functionality |
| Device ID: push notification token (only if the player turns on messages or price alerts) | Yes | No | No | App functionality |
| Location, contacts, purchases, health | No | – | – | – |

- Tracking: **No**. No ads, no third-party SDKs.
- The push token is random, not tied to a name or account. Turning both
  notification switches off deletes it from the server.
- The player can turn the counters off in the Info screen.

### Lab
| Data | Collected? | Linked? | Tracking? | Purpose |
|---|---|---|---|---|
| Usage / product interaction (anonymous "book link tapped" counter) | Yes | No | No | Analytics |
| Everything else | No | – | – | – |

- Rules, reports and live tests stay on the device. Prices are fetched from
  public exchange feeds (Kraken, Coinbase) with no user data sent.

## 4. App Review notes (paste into "Notes")

**Game**
> Orange Robot is a trading simulation game played entirely with virtual money
> on historical Bitcoin prices. There are no accounts, no real-money trading,
> no purchases and nothing can be withdrawn. "Virtual sats" are game points
> with no cash value. The leaderboard accepts 1–3 letter initials. Links open
> the author's own website, theorangerobot.com. The prologue audio is the
> author's own work. No login is required.
>
> Notifications are optional and off by default. The app asks once, after the
> first finished game, whether the player wants occasional messages and price
> alerts. Messages come from the author; price alerts come from public Kraken
> prices. Both can be turned off in the Info screen. The "Coming soon" card at
> the end of a game names the Lab app but has no link.

**Lab**
> Orange Robot Lab is an educational backtesting simulator. It runs simple
> rule sets over historical Bitcoin prices and over live public prices (paper
> trading only). There is no real money, no brokerage, no account and no
> ability to trade. Live tests fetch public daily prices from Kraken and
> Coinbase. Optional local notifications tell the user when a paper robot made
> a hypothetical trade. All data stays on the device. No login is required.

## 5. Privacy policy (draft for theorangerobot.com/privacy.html) 🔸

> **Privacy policy: Orange Robot and Orange Robot Lab**
> Last updated: [date]
>
> We built these apps to collect as little as possible.
>
> **What we do not collect:** your name, email, phone number, location,
> contacts or advertising identifiers. There are no accounts and no ads, and
> we do not use third-party analytics or tracking.
>
> **Notifications (game):** if you turn on game messages or Bitcoin price
> alerts, the game sends our server a random push token for your device, plus
> your choices (messages on or off, alerts on or off, and the alert
> percentage). The token is not linked to your name or any account. Turning
> both switches off deletes it. Messages are sent by us, rarely, and only to
> people who opted in.
>
> **What stays on your device:** your robots, rules, reports, notes, settings
> and live tests.
>
> **Anonymous usage counts:** the apps can send a simple counter, such as
> "the prologue was played" or "the book link was tapped", with no identifier.
> We store only how many times each event happened per day. You can switch
> this off in the app.
>
> **Leaderboard (game):** if you choose to post a score, the initials you type,
> your score and your virtual sats are stored on our server and shown publicly.
>
> **Prices:** the Lab downloads public daily Bitcoin prices from Kraken and
> Coinbase. Those requests do not include any personal information.
>
> **Notifications (Lab):** optional, generated on your device, and not sent to
> our server.
>
> **Children:** the apps are not directed at children and collect no personal
> information.
>
> **Contact:** [your email]
>
> These apps are games and educational simulations. They do not provide
> financial advice. Virtual money and virtual sats have no cash value.

## 6. Screenshots (required)

Apple requires at least one set at 6.9" (1320 × 2868). Capture them on the
**iPhone 18 Pro Max** simulator, which produces exactly that size. Suggested six per app:

Game: start screen with cover · live chart with candles · order form ·
positions & orders · news banner · results with leaderboard.

Lab: home · rule builder · results with BETTER and score · analysis ·
replay · live tests.

I can capture these from the simulator once the layout is final.

## 7. Steps for you (in order)

1. developer.apple.com → Certificates, IDs & Profiles → confirm bundle IDs 🔸
2. App Store Connect → My Apps → **+** → New App (one per app); pick the
   bundle ID, name, SKU (e.g. `orange-robot-1`).
3. Fill the listing from §1/§2; set categories and age rating.
4. App Privacy: use §3.
5. Add the Privacy Policy URL (publish §5 first).
6. In Xcode: Product → Archive → Distribute App → App Store Connect → Upload
   (do the game, then the Lab).
7. Add the build to **TestFlight**, install it on your phone, test.
8. Add screenshots, review notes (§4), then **Submit for Review**.

## 8. Things that can bite

- **Guideline 4.2 (minimum functionality):** both apps are full native
  features, so low risk.
- **Guideline 3.1.5 (crypto):** we never reward or hand out cryptocurrency;
  "sats" are labelled virtual everywhere. Keep it that way.
- **Financial content:** keep "simulator / game / educational / not advice"
  wording visible, as it is today.
- **User-generated content (Lab notes, leaderboard initials):** initials are
  public; Apple may ask about filtering. The Lab's notes never leave the phone.
- **Icons:** the game's icon is a crop of the robot head on a navy background.
  Check it at full size in App Store Connect's preview before submitting.
- **Test features:** the hidden five-tap reset on the start screen (for
  testing the notification question) must be removed before submission.

## 9. Where to click (developer site and App Store Connect)

- **Developer account:** https://developer.apple.com/account → Certificates,
  Identifiers & Profiles. Bundle IDs live under **Identifiers**; the push key
  lives under **Keys**.
- **App Store Connect:** https://appstoreconnect.apple.com → **Apps** → **+** →
  **New App**. Create one record per app.
- **Inside an app record:**
  - **App Information:** name, subtitle, category, age rating (answer the
    questionnaire honestly; it's a trading simulator with no real money, so
    expect 4+). Privacy Policy URL goes here too.
  - **App Privacy:** use §3.
  - **Pricing and Availability:** Free, countries.
  - **App Store tab (iOS app, version 1.0):** promotional text, description,
    keywords, screenshots, review notes (§4).
  - **TestFlight:** the uploaded build appears here. Add yourself as an
    internal tester and install from the TestFlight app on your phone.
  - **Submit for Review** is on the version page once everything is filled in.
- **Upload the build:** Xcode → Product → Archive → Distribute App → App Store
  Connect → Upload.

## 10. Privacy page on theorangerobot.com

A draft is at `privacy.html` in the website folder. It isn't live until the
repo is pushed to GitHub Pages. Fill in the date and contact line before you
publish it.
