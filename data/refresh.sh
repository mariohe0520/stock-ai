#!/bin/bash
# Refresh stock data from Yahoo Finance v8 chart API
# Runs on Mac mini, generates static JSON for the PWA
# v3.0: 100+ tickers, OHLC data, sector tagging, batch fetching
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/quotes.json"

# ── Ticker Universe (100+ symbols) ──────────────────────────────
# Indices & Volatility
IDX="^GSPC ^IXIC ^DJI ^VIX"

# Mega-cap Tech
MEGA="AAPL MSFT GOOG AMZN META NVDA TSLA NFLX"

# AI Pure Plays
AI_PLAYS="PLTR AI SNOW DDOG MDB PATH CRWD PANW"

# Semiconductor
SEMI="AVGO TSM ASML AMD INTC QCOM ARM MRVL AMAT KLAC LRCX ON"

# Cloud & SaaS
CLOUD="CRM NOW ORCL NET SHOP UBER ABNB SQ"

# China ADRs
CHINA="BABA PDD JD BIDU NIO LI XPEV TME BILI FUTU TAL"

# Finance
FIN="JPM GS MS V MA BRK-B BAC C AXP PYPL"

# Healthcare
HEALTH="UNH LLY NVO ABBV MRK PFE JNJ AMGN GILD ISRG"

# Consumer
CONSUMER="WMT COST KO PEP MCD DIS"

# Energy
ENERGY="XOM CVX"

# ETFs (broad + sector + thematic)
ETFS="SPY QQQ IWM ARKK SOXX XLF XLE XLV XLK BOTZ SMH TLT GLD"

# Crypto
CRYPTO="BTC-USD ETH-USD"

ALL_TICKERS="$IDX $MEGA $AI_PLAYS $SEMI $CLOUD $CHINA $FIN $HEALTH $CONSUMER $ENERGY $ETFS $CRYPTO"
COUNT=$(echo $ALL_TICKERS | wc -w | tr -d ' ')
echo "Fetching $COUNT tickers..."

echo '{"updated":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","quotes":{' > "$OUT"
FIRST=1
FETCHED=0
FAILED=0

for T in $ALL_TICKERS; do
  DATA=$(curl -s --max-time 10 "https://query1.finance.yahoo.com/v8/finance/chart/$T?range=1mo&interval=1d" \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)")

  if [ $? -eq 0 ]; then
    QUOTE=$(echo "$DATA" | python3 -c "
import sys, json

try:
    d = json.load(sys.stdin)
    r = d['chart']['result'][0]
    m = r['meta']
    ts_raw = r.get('timestamp', [])
    quotes = r['indicators']['quote'][0]
    closes_raw = quotes.get('close', [])
    opens_raw = quotes.get('open', [])
    highs_raw = quotes.get('high', [])
    lows_raw = quotes.get('low', [])
    volumes_raw = quotes.get('volume', [])

    # Clean closes
    closes = [round(c, 2) for c in closes_raw if c is not None]

    # Build OHLCV history for charting (candlestick + volume)
    ohlc = []
    for i, ts in enumerate(ts_raw):
        o = opens_raw[i] if i < len(opens_raw) else None
        h = highs_raw[i] if i < len(highs_raw) else None
        l = lows_raw[i] if i < len(lows_raw) else None
        c = closes_raw[i] if i < len(closes_raw) else None
        v = volumes_raw[i] if i < len(volumes_raw) else None
        if c is not None:
            ohlc.append([
                ts,
                round(o, 2) if o else round(c, 2),
                round(h, 2) if h else round(c, 2),
                round(l, 2) if l else round(c, 2),
                round(c, 2),
                v or 0
            ])

    # Build simple history for line charts
    history = [[ts, round(closes_raw[i], 2)] for i, ts in enumerate(ts_raw) if closes_raw[i] is not None]

    # Current price data
    prev = m.get('chartPreviousClose', m.get('previousClose', 0))
    price = m['regularMarketPrice']
    chg = price - prev
    pct = (chg / prev * 100) if prev else 0
    name = m.get('longName', m.get('shortName', ''))

    # 52-week high/low
    week52_high = m.get('fiftyTwoWeekHigh', None)
    week52_low = m.get('fiftyTwoWeekLow', None)
    if week52_high is None and highs_raw:
        valid = [h for h in highs_raw if h is not None]
        week52_high = max(valid) if valid else None
    if week52_low is None and lows_raw:
        valid = [l for l in lows_raw if l is not None]
        week52_low = min(valid) if valid else None

    # Volume
    valid_vols = [v for v in volumes_raw if v is not None]
    vol = valid_vols[-1] if valid_vols else None
    avg_vol = int(sum(valid_vols) / len(valid_vols)) if valid_vols else None

    result = {
        'p': round(price, 2),
        'c': round(chg, 2),
        'pct': round(pct, 2),
        'prev': round(prev, 2),
        'name': name,
        'spark': [round(c, 2) for c in closes[-5:]],
        'history': history,
        'ohlc': ohlc,
        'currency': m.get('currency', 'USD'),
        'exchange': m.get('exchangeName', ''),
        'type': m.get('instrumentType', m.get('quoteType', '')),
    }
    if week52_high is not None: result['w52h'] = round(week52_high, 2)
    if week52_low is not None: result['w52l'] = round(week52_low, 2)
    if vol is not None: result['vol'] = vol
    if avg_vol is not None: result['avgVol'] = avg_vol

    print(json.dumps(result))
except Exception as e:
    sys.exit(1)
" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$QUOTE" ]; then
      if [ $FIRST -eq 0 ]; then echo ',' >> "$OUT"; fi
      echo "\"$T\":$QUOTE" >> "$OUT"
      FIRST=0
      FETCHED=$((FETCHED + 1))
    else
      FAILED=$((FAILED + 1))
    fi
  else
    FAILED=$((FAILED + 1))
  fi
  sleep 0.3
done
echo '}}' >> "$OUT"
echo "Updated quotes: $(date)"
echo "Fetched: $FETCHED / $COUNT (failed: $FAILED)"

# Generate news based on actual price data
bash "$DIR/gen-news.sh"
