#!/usr/bin/env python3
"""Extends OrangeRobotKit's bundled btc_daily.json with finished UTC days from
Coinbase's public daily candles (no key). Safe to re-run: it only appends.

Safety checks before appending:
  * the last 40 bundled days must match Coinbase within 0.5% (a bad seam
    would corrupt every indicator and the price-milestone news),
  * the appended days must be continuous, and today's unfinished candle is dropped.

Run:  python3 ios/tools/extend_history.py
After running: python3 ios/tools/build_news.py   (milestone headlines are computed from the data)
"""
import json, urllib.request, datetime as dt, pathlib, statistics, sys

PATH = pathlib.Path(__file__).resolve().parents[1] / "OrangeRobotKit/Sources/OrangeRobotKit/Resources/btc_daily.json"
d = json.loads(PATH.read_text())
start = dt.date.fromisoformat(d["startDate"])
n = d["days"]
last = start + dt.timedelta(days=n - 1)
today = dt.datetime.now(dt.timezone.utc).date()
through = today - dt.timedelta(days=1)          # last finished UTC day

def fetch(a, b):
    url = ("https://api.exchange.coinbase.com/products/BTC-USD/candles?granularity=86400"
           f"&start={a}T00:00:00Z&end={b}T00:00:00Z")
    req = urllib.request.Request(url, headers={"User-Agent": "orange-robot-data"})
    return json.load(urllib.request.urlopen(req, timeout=30))

# 1) seam check on the last 40 days we already have
rows = fetch(last - dt.timedelta(days=39), last)
diffs = []
for t, low, high, op, close, vol in rows:
    i = (dt.datetime.fromtimestamp(t, dt.timezone.utc).date() - start).days
    if 0 <= i < n:
        c = d["ohlc"][i * 4 + 3]
        diffs.append(abs(close - c) / c)
if len(diffs) < 20 or max(diffs) > 0.005:
    sys.exit(f"seam check failed: {len(diffs)} days compared, max diff {max(diffs, default=1):.3%}")
print(f"seam OK: {len(diffs)} days, median diff {statistics.median(diffs):.3%}, max {max(diffs):.3%}")

if last >= through:
    sys.exit(f"already up to date ({last})")

# 2) fetch the missing days in windows of < 300 candles
new = {}
cur = last + dt.timedelta(days=1)
while cur <= through:
    end = min(cur + dt.timedelta(days=250), through)
    for t, low, high, op, close, vol in fetch(cur, end + dt.timedelta(days=1)):
        day = dt.datetime.fromtimestamp(t, dt.timezone.utc).date()
        if last < day <= through:
            new[day] = (op, high, low, close)
    cur = end + dt.timedelta(days=1)

# 3) must be continuous
day = last + dt.timedelta(days=1)
added = 0
while day <= through:
    if day not in new:
        sys.exit(f"gap: no candle for {day}; not writing anything")
    o, h, l, c = new[day]
    assert l <= min(o, c) + 1e-6 and h >= max(o, c) - 1e-6, f"bad candle {day}"
    d["ohlc"].extend([o, h, l, c])
    added += 1
    day += dt.timedelta(days=1)

d["days"] = n + added
PATH.write_text(json.dumps(d))
print(f"added {added} days: {last + dt.timedelta(days=1)} -> {through}; total {d['days']}")
