#!/usr/bin/env python3
"""Builds OrangeRobotKit's bundled news.json.

Event dates were checked against reference sources (Wikipedia, regulator and
company releases). Price *milestones* (first time above $X, record highs) get
their dates computed from the game's own daily candles so a headline can never
contradict the ticker the player is watching.

Run:  python3 ios/tools/build_news.py
Rules for headlines: describe what has happened *as of that date*. No hindsight
about prices ("top", "bottom", "would go on to").
"""
import json, datetime as dt, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[1] / "OrangeRobotKit" / "Sources" / "OrangeRobotKit" / "Resources"
data = json.loads((ROOT / "btc_daily.json").read_text())
START = dt.date.fromisoformat(data["startDate"])
BARS = [data["ohlc"][i * 4:i * 4 + 4] for i in range(data["days"])]
END = START + dt.timedelta(days=data["days"] - 1)

def day(i): return START + dt.timedelta(days=i)
def high(i): return BARS[i][1]

def first_cross(threshold, since=None):
    s = (dt.date.fromisoformat(since) - START).days if since else 0
    for i in range(max(0, s), len(BARS)):
        if high(i) >= threshold:
            return day(i)
    raise SystemExit(f"no day crosses {threshold}")

def record_day(lo, hi):
    a, b = (dt.date.fromisoformat(lo) - START).days, (dt.date.fromisoformat(hi) - START).days
    i = max(range(a, b + 1), key=high)
    return day(i), high(i)

def bar_of(date_iso):
    return BARS[(dt.date.fromisoformat(date_iso) - START).days]

items = []
def add(date, title, tag, sig=False, detail=None, **extra):
    d = date if isinstance(date, dt.date) else dt.date.fromisoformat(date)
    items.append({"date": d.isoformat(), "title": title, "tag": tag, "significant": sig,
                  **({"detail": detail} if detail else {}), **extra})

# --- Before the data starts: background, shows on the earliest runs ------------
add("2008-10-31", "Satoshi Nakamoto publishes the Bitcoin white paper", "bitcoin",
    detail="A nine-page proposal for a peer-to-peer electronic cash system.")
add("2009-01-03", "The Bitcoin network starts: the first block is mined", "bitcoin")
add("2010-05-22", "10,000 BTC buy two pizzas, the first known purchase with bitcoin", "adoption",
    detail="A programmer pays another forum user for pizza delivery.")

# --- 2010 ---------------------------------------------------------------------
add("2010-07-18", "Mt. Gox opens as a bitcoin exchange", "adoption", sig=True)
add("2010-08-15", "A bug creates 184 billion bitcoins in one transaction; a fix is released", "tech", sig=True,
    detail="The invalid block is wiped out by a patched version of the software.")
add("2010-12-12", "Satoshi Nakamoto makes a final public post on the Bitcoin forum", "bitcoin")

# --- 2011 ---------------------------------------------------------------------
add("2011-02-09", "Bitcoin reaches parity with the US dollar: $1 per BTC", "markets", sig=True)
add("2011-06-01", "Gawker exposes Silk Road, a hidden marketplace that accepts only bitcoin", "bitcoin")
add(first_cross(30), "Bitcoin surges above $30 as interest explodes", "markets", sig=True,
    detail="The price has multiplied several times over in a few weeks.", milestone=30, trigger=30)
add("2011-06-19", "Mt. Gox is hacked: stolen coins flood the market and its price briefly hits one cent", "security", sig=True)
add("2011-08-05", "S&P downgrades the United States' credit rating for the first time", "markets")

# --- 2012 ---------------------------------------------------------------------
add("2012-11-28", "First halving: the reward for each block drops from 50 to 25 bitcoins", "tech", sig=True)

# --- 2013 ---------------------------------------------------------------------
add("2013-03-12", "A software bug splits the blockchain; Mt. Gox halts deposits until miners roll back", "tech")
add("2013-03-16", "Cyprus agrees a bailout that taxes bank deposits; savers panic", "markets", sig=True,
    detail="Bitcoin is discussed as a place to move money outside the banking system.")
add("2013-03-18", "US regulator FinCEN issues guidance: bitcoin exchangers must register as money transmitters", "regulation")
add("2013-04-10", "Bitcoin spikes to about $266, then halves within hours as exchanges buckle under demand", "markets", sig=True)
add("2013-05-15", "US authorities seize Mt. Gox accounts over its registration with FinCEN", "regulation")
add("2013-08-06", "A US federal judge rules bitcoin is \"a currency or form of money\"", "regulation")
add("2013-10-02", "FBI shuts down Silk Road and arrests its alleged founder; about 26,000 BTC are seized", "regulation", sig=True)
add("2013-10-29", "The world's first bitcoin ATM opens in Vancouver", "adoption")
add("2013-11-18", "A US Senate committee holds a hearing on virtual currencies", "regulation")
add(first_cross(1000), "Bitcoin passes $1,000 for the first time", "markets", sig=True, milestone=1000, trigger=1000)
add("2013-12-05", "China's central bank bars financial institutions from handling bitcoin", "regulation", sig=True)

# --- 2014 ---------------------------------------------------------------------
add("2014-02-07", "Mt. Gox halts bitcoin withdrawals, citing a technical problem", "security")
add("2014-02-24", "Mt. Gox stops trading and its website goes offline", "security", sig=True)
add("2014-02-28", "Mt. Gox files for bankruptcy protection in Tokyo, reporting hundreds of thousands of bitcoins missing", "security", sig=True)
add("2014-03-25", "The IRS rules that bitcoin is property, not currency, for US tax purposes", "regulation")
add("2014-06-27", "US Marshals auction nearly 30,000 bitcoins seized from Silk Road", "markets")
add("2014-07-17", "New York proposes the \"BitLicense\" for bitcoin businesses", "regulation")
add("2014-12-11", "Microsoft begins accepting bitcoin for Xbox and Windows purchases", "adoption")

# --- 2015 ---------------------------------------------------------------------
add("2015-01-05", "Bitstamp suspends trading after about 19,000 BTC are stolen", "security")
add("2015-01-20", "Coinbase raises $75 million, the biggest funding round yet for a bitcoin company", "adoption")
add("2015-02-04", "Silk Road founder Ross Ulbricht is found guilty on all seven counts", "regulation")
add("2015-06-03", "New York finalizes its BitLicense rules", "regulation")
add("2015-09-17", "The CFTC declares bitcoin a commodity", "regulation")

# --- 2016 ---------------------------------------------------------------------
add("2016-01-14", "Developer Mike Hearn quits, declaring the bitcoin experiment a failure as the block-size fight boils over", "tech")
add("2016-06-17", "Ethereum's \"DAO\" investment fund is drained of roughly $50 million in a hack", "security")
add("2016-06-24", "Britain votes to leave the European Union; markets lurch", "markets")
add("2016-07-09", "Second halving: the block reward drops to 12.5 bitcoins", "tech", sig=True)
add("2016-08-02", "Bitfinex is hacked: almost 120,000 BTC are stolen", "security", sig=True)
add("2016-11-08", "India withdraws its two largest banknotes overnight", "markets")
add("2016-11-09", "Donald Trump wins the US presidential election", "markets")

# --- 2017 ---------------------------------------------------------------------
add(first_cross(1000, since="2016-01-01"), "Bitcoin tops $1,000 again, for the first time in three years", "markets", sig=True,
    milestone=1000, since="2016-01-01", trigger=1000)
add("2017-03-10", "The SEC rejects the Winklevoss bitcoin ETF proposal", "regulation")
add("2017-04-01", "Japan's law recognizing bitcoin as a legal payment method takes effect", "regulation")
add(first_cross(2000), "Bitcoin crosses $2,000 for the first time", "markets", milestone=2000, trigger=2000)
add("2017-08-01", "Bitcoin splits: Bitcoin Cash forks off with larger blocks", "tech", sig=True)
add("2017-08-24", "SegWit activates on the Bitcoin network", "tech")
add("2017-09-04", "China bans initial coin offerings", "regulation")
add(first_cross(5000), "Bitcoin breaks $5,000 for the first time", "markets", sig=True, milestone=5000, trigger=5000)
add("2017-09-12", "JPMorgan chief Jamie Dimon calls bitcoin \"a fraud\"", "markets")
add("2017-11-08", "The planned SegWit2x hard fork is cancelled", "tech")
add(first_cross(10000), "Bitcoin passes $10,000 for the first time", "markets", sig=True, milestone=10000, trigger=10000)
add("2017-12-10", "Cboe launches bitcoin futures: the first on a regulated US exchange", "markets", sig=True)
rd, rh = record_day("2017-12-01", "2017-12-31")
add(rd, "Bitcoin sets a new all-time record near $%s as CME launches its own futures" % f"{round(rh, -2):,.0f}",
    "markets", sig=True, record=True, trigger=round(rh * 0.998, 2))

# --- 2018 ---------------------------------------------------------------------
add("2018-01-26", "Japan's Coincheck loses about $530 million of NEM tokens in a hack", "security")
add("2018-01-30", "Facebook bans cryptocurrency advertising", "markets")
add("2018-02-05", "Bitcoin sinks below $7,000, down by half in 16 days", "markets", sig=True, trigger=7000, direction="below")
add("2018-12-15", "Bitcoin slides to roughly $3,200, more than 80% below its record", "markets", sig=True, trigger=3300, direction="below")

# --- 2019 ---------------------------------------------------------------------
add("2019-05-07", "Binance is hacked: about 7,000 BTC are stolen", "security")
add("2019-06-18", "Facebook unveils Libra, a global digital currency project", "adoption")

# --- 2020 ---------------------------------------------------------------------
add("2020-03-12", "\"Black Thursday\": bitcoin plunges about 40% in a day as COVID-19 panic grips global markets", "markets", sig=True,
    trigger=round(bar_of("2020-03-12")[0] * 0.85, 2), direction="below")
add("2020-03-15", "The Federal Reserve cuts rates to near zero in an emergency move", "markets")
add("2020-05-11", "Third halving: the block reward drops to 6.25 bitcoins", "tech", sig=True)
add("2020-08-11", "MicroStrategy buys $250 million of bitcoin as a treasury reserve", "adoption")
add("2020-10-21", "PayPal will let US users buy, hold and sell bitcoin", "adoption", sig=True)
add(first_cross(20000), "Bitcoin passes $20,000 for the first time, a new record", "markets", sig=True, milestone=20000, trigger=20000)

# --- 2021 ---------------------------------------------------------------------
add(first_cross(40000), "Bitcoin tops $40,000 as institutional buying gathers pace", "markets", milestone=40000, trigger=40000)
add("2021-02-08", "Tesla discloses a $1.5 billion bitcoin purchase", "adoption", sig=True)
add("2021-02-19", "Bitcoin's total value tops $1 trillion for the first time", "markets")
add(first_cross(50000), "Bitcoin crosses $50,000", "markets", milestone=50000, trigger=50000)
rd, rh = record_day("2021-04-01", "2021-04-30")
add(rd, "Coinbase goes public as bitcoin sets a record near $%s" % f"{round(rh, -2):,.0f}", "markets", sig=True, record=True,
    trigger=round(rh * 0.998, 2))
add("2021-05-12", "Tesla stops accepting bitcoin, citing the energy used to mine it", "adoption", sig=True)
add("2021-05-19", "Bitcoin plunges as much as 30% in a day on a China crackdown and forced liquidations", "markets", sig=True,
    trigger=round(bar_of("2021-05-19")[0] * 0.85, 2), direction="below")
add("2021-06-09", "El Salvador's congress passes a law making bitcoin legal tender", "regulation", sig=True)
add("2021-09-07", "El Salvador becomes the first country to adopt bitcoin as legal tender", "adoption")
add("2021-09-24", "China's central bank declares all cryptocurrency transactions illegal", "regulation", sig=True)
add("2021-10-19", "The first US bitcoin futures ETF, ProShares BITO, begins trading", "markets", sig=True)
rd, rh = record_day("2021-11-01", "2021-11-30")
add(rd, "Bitcoin sets a new all-time record near $%s" % f"{round(rh, -2):,.0f}", "markets", sig=True, record=True,
    trigger=round(rh * 0.998, 2))
add("2021-11-14", "The Taproot upgrade activates on the Bitcoin network", "tech")

# --- 2022 ---------------------------------------------------------------------
add("2022-02-24", "Russia invades Ukraine; global markets tumble", "markets")
add("2022-03-16", "The Federal Reserve raises interest rates for the first time since 2018", "markets")
add("2022-05-09", "TerraUSD, a leading stablecoin, slips below its $1 peg", "markets")
add("2022-05-12", "Terra's LUNA collapses and the crypto market is rocked", "markets", sig=True)
add("2022-06-12", "Celsius Network freezes customer withdrawals", "markets", sig=True)
add("2022-06-18", "Bitcoin falls below $18,000, under its 2017 record for the first time since 2020", "markets", sig=True, trigger=18000, direction="below")
add("2022-06-27", "Crypto hedge fund Three Arrows Capital is ordered into liquidation", "markets")
add("2022-09-15", "Ethereum completes \"the Merge\", switching to proof of stake", "tech")
add("2022-11-02", "A CoinDesk report raises questions about the balance sheet of FTX-linked Alameda Research", "markets")
add("2022-11-08", "Binance agrees to buy rival exchange FTX amid a run on withdrawals", "markets")
add("2022-11-09", "Binance walks away from the FTX deal", "markets")
add("2022-11-11", "FTX files for bankruptcy", "markets", sig=True)

# --- 2023 ---------------------------------------------------------------------
add("2023-03-10", "Silicon Valley Bank collapses, the largest US bank failure since 2008", "markets", sig=True)
add("2023-03-12", "Signature Bank is closed; regulators guarantee depositors", "markets")
add("2023-06-05", "The SEC sues Binance", "regulation")
add("2023-06-06", "The SEC sues Coinbase", "regulation")
add("2023-06-15", "BlackRock files for a spot bitcoin ETF", "markets", sig=True)
add("2023-08-29", "A US appeals court rules for Grayscale against the SEC over a bitcoin ETF", "regulation")
add("2023-11-21", "Binance founder Changpeng Zhao pleads guilty; Binance agrees to a $4.3 billion settlement", "regulation")

# --- 2024 ---------------------------------------------------------------------
add("2024-01-10", "The SEC approves spot bitcoin ETFs", "regulation", sig=True)
add(first_cross(70000), "Bitcoin tops $70,000 for the first time", "markets", milestone=70000, trigger=70000)
rd, rh = record_day("2024-03-01", "2024-03-31")
add(rd, "Bitcoin sets a new all-time record near $%s as ETFs draw record inflows" % f"{round(rh, -2):,.0f}",
    "markets", sig=True, record=True, trigger=round(rh * 0.998, 2))
add("2024-04-20", "Fourth halving: the block reward drops to 3.125 bitcoins", "tech", sig=True)
add("2024-05-23", "The SEC approves spot Ether ETFs", "regulation")
add("2024-08-05", "A global market rout drags bitcoin below $50,000", "markets", sig=True, trigger=50000, direction="below")


# --- Sep 2024 onward (dates verified against dated sources; prices computed from the data) ---
add("2024-09-20", "The SEC approves options on spot bitcoin ETFs, starting with BlackRock's IBIT", "regulation")
add("2024-11-05", "Donald Trump wins the US presidential election; crypto markets surge", "markets", sig=True)
add(first_cross(80000), "Bitcoin passes $80,000 for the first time", "markets", milestone=80000, trigger=80000)
add(first_cross(100000), "Bitcoin passes $100,000 for the first time", "markets", sig=True, milestone=100000, trigger=100000)
rd, rh = record_day("2024-12-01", "2024-12-31")
add(rd, "Bitcoin sets a new all-time record near $%s" % f"{round(rh, -2):,.0f}", "markets", sig=True, record=True,
    trigger=round(rh * 0.998, 2))
rd, rh = record_day("2025-01-01", "2025-01-31")
add(rd, "Bitcoin sets a new all-time record near $%s as a new US administration takes office" % f"{round(rh, -2):,.0f}",
    "markets", sig=True, record=True, trigger=round(rh * 0.998, 2))
add("2025-02-21", "Bybit loses about $1.5 billion in the largest crypto theft on record", "security", sig=True)
add("2025-03-06", "The US president signs an order creating a Strategic Bitcoin Reserve", "regulation", sig=True,
    detail="The reserve is to be funded with bitcoin the government already holds from forfeitures.")
add(first_cross(120000), "Bitcoin passes $120,000 for the first time", "markets", sig=True, milestone=120000, trigger=120000)
rd, rh = record_day("2025-10-01", "2025-10-31")
add(rd, "Bitcoin sets a new all-time record near $%s" % f"{round(rh, -2):,.0f}", "markets", sig=True, record=True,
    trigger=round(rh * 0.998, 2))
add("2025-10-10", "Roughly $19 billion of leveraged crypto positions are liquidated in a day, the most on record, after new US-China tariff threats",
    "markets", sig=True, detail="Figures vary by data provider.")
add("2025-11-18", "Bitcoin falls below $90,000 for the first time in seven months", "markets", sig=True,
    trigger=90000, direction="below")

for it in items:
    if "trigger" in it:
        o, h, l, c = bar_of(it["date"])
        if it.get("direction") == "below":
            assert l <= it["trigger"], ("unreachable", it["title"], l, it["trigger"])
        else:
            assert h >= it["trigger"], ("unreachable", it["title"], h, it["trigger"])

items.sort(key=lambda x: (x["date"], x["title"]))
for it in items:
    assert it["date"] <= END.isoformat(), it
out = {"version": 1, "generatedFrom": "btc_daily.json", "items": items}
(ROOT / "news.json").write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n")
print(f"{len(items)} items, {sum(i['significant'] for i in items)} significant, data ends {END}")
for it in items:
    if it.get("milestone") or it.get("record"):
        print("  computed:", it["date"], "|", it["title"])
