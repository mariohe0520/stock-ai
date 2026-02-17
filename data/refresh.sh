#!/bin/bash
# Refresh stock data from Yahoo Finance v8 chart API
# Runs on Mac mini, generates static JSON for the PWA
# v3.0: 100+ tickers, parallel batch fetching, sector-based

DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/quotes.json"
TMP="$DIR/.tmp-quotes"
mkdir -p "$TMP"

# === ALL TICKERS (101 unique, organized by sector) ===
TICKERS=(
  # Indices (4)
  "^GSPC" "^IXIC" "^DJI" "^VIX"

  # AI/Tech Giants (14)
  AAPL MSFT GOOGL AMZN META NVDA TSLA AMD INTC AVGO ORCL CRM ADBE IBM

  # AI Pure Play (9)
  PLTR AI SNOW DDOG NET PATH CFLT MDB SMCI

  # Semiconductors (11)
  TSM ASML QCOM TXN MU LRCX KLAC MRVL ON AMAT ARM

  # Chinese Tech (10)
  BABA JD PDD BIDU NIO XPEV LI TME BILI TCOM

  # Gaming/Entertainment (12)
  RBLX EA TTWO NFLX DIS SPOT SE DKNG ROKU UBER ABNB DASH

  # Fintech (10)
  SQ V MA PYPL COIN AFRM SOFI MELI NU UPST

  # Cloud/SaaS (12)
  NOW TEAM ZS CRWD PANW OKTA FTNT INTU WDAY HUBS SHOP S

  # EV/Clean Energy (4)
  RIVN LCID ENPH FSLR

  # Healthcare AI (3)
  ISRG DXCM VEEV

  # ETFs (12)
  SPY QQQ ARKK SOXX SMH BOTZ XLK XLF XLE XLV KWEB VGT
)

TOTAL=${#TICKERS[@]}
echo "Fetching $TOTAL tickers in parallel batches..."

# Clean temp dir
rm -f "$TMP"/*.json

# Python parser (shared across all fetches)
PARSER='
import sys, json
try:
    d = json.load(sys.stdin)
    r = d["chart"]["result"][0]
    m = r["meta"]
    ts_raw = r.get("timestamp", [])
    quotes = r["indicators"]["quote"][0]
    closes_raw = quotes["close"]
    highs_raw = quotes.get("high", [])
    lows_raw = quotes.get("low", [])
    volumes_raw = quotes.get("volume", [])
    closes = [round(c, 2) for c in closes_raw if c is not None]
    history = []
    for i, ts in enumerate(ts_raw):
        if closes_raw[i] is not None:
            history.append([ts, round(closes_raw[i], 2)])
    prev = m.get("chartPreviousClose", m.get("previousClose", 0))
    price = m["regularMarketPrice"]
    chg = price - prev
    pct = (chg / prev * 100) if prev else 0
    name = m.get("longName", m.get("shortName", ""))
    week52_high = m.get("fiftyTwoWeekHigh", None)
    week52_low = m.get("fiftyTwoWeekLow", None)
    if week52_high is None and highs_raw:
        valid_highs = [h for h in highs_raw if h is not None]
        week52_high = max(valid_highs) if valid_highs else None
    if week52_low is None and lows_raw:
        valid_lows = [l for l in lows_raw if l is not None]
        week52_low = min(valid_lows) if valid_lows else None
    valid_vols = [v for v in volumes_raw if v is not None]
    vol = valid_vols[-1] if valid_vols else None
    result = {
        "p": round(price, 2),
        "c": round(chg, 2),
        "pct": round(pct, 2),
        "prev": round(prev, 2),
        "name": name,
        "spark": [round(c, 2) for c in closes[-5:]],
        "history": history,
        "currency": m.get("currency", "USD"),
        "exchange": m.get("exchangeName", ""),
        "type": m.get("instrumentType", m.get("quoteType", "")),
    }
    if week52_high is not None:
        result["w52h"] = round(week52_high, 2)
    if week52_low is not None:
        result["w52l"] = round(week52_low, 2)
    if vol is not None:
        result["vol"] = vol
    print(json.dumps(result))
except Exception as e:
    sys.exit(1)
'

# Fetch a single ticker and save result to temp file
fetch_ticker() {
  local T="$1"
  local SAFE=$(echo "$T" | tr '^' '_')
  local DATA
  DATA=$(curl -s --max-time 10 \
    "https://query1.finance.yahoo.com/v8/finance/chart/$T?range=1mo&interval=1d" \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)")

  if [ $? -eq 0 ] && [ -n "$DATA" ]; then
    local QUOTE
    QUOTE=$(echo "$DATA" | python3 -c "$PARSER" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$QUOTE" ]; then
      echo "$QUOTE" > "$TMP/$SAFE.json"
    fi
  fi
}

# Batch fetch with parallelism (20 concurrent)
BATCH_SIZE=20
COUNT=0
BATCH_NUM=0

for T in "${TICKERS[@]}"; do
  fetch_ticker "$T" &
  COUNT=$((COUNT + 1))
  if [ $((COUNT % BATCH_SIZE)) -eq 0 ]; then
    BATCH_NUM=$((BATCH_NUM + 1))
    wait
    echo "  Batch $BATCH_NUM done ($COUNT/$TOTAL)..."
  fi
done
# Wait for any remaining
wait
echo "All fetches complete."

# Count successes
SUCCESS=$(find "$TMP" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')

# Merge results into quotes.json
echo '{"updated":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","quotes":{' > "$OUT"
FIRST=1
for T in "${TICKERS[@]}"; do
  SAFE=$(echo "$T" | tr '^' '_')
  if [ -f "$TMP/$SAFE.json" ]; then
    if [ $FIRST -eq 0 ]; then echo ',' >> "$OUT"; fi
    echo "\"$T\":$(cat "$TMP/$SAFE.json")" >> "$OUT"
    FIRST=0
  fi
done
echo '}}' >> "$OUT"

# Cleanup temp
rm -rf "$TMP"

echo "Updated quotes: $(date)"
echo "Tickers fetched: $SUCCESS / $TOTAL"

# Generate news based on actual price data
bash "$DIR/gen-news.sh"
