#!/bin/bash
# Refresh stock data from Yahoo Finance v8 chart API
# Runs on Mac mini, generates static JSON for the PWA
# v2.1: 30-day data, sector ETFs, VIX, news generation
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/quotes.json"

# Core indices + VIX + AI/Tech stocks + Sector ETFs + Broad ETFs
TICKERS="^GSPC ^IXIC ^DJI ^VIX NVDA AMD TSM AVGO MSFT AMZN GOOG META PLTR AI CRM NOW SNOW QQQ SPY BOTZ SMH XLK XLF XLE XLV"

echo '{"updated":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","quotes":{' > "$OUT"
FIRST=1
for T in $TICKERS; do
  # Fetch 30 days of daily data
  DATA=$(curl -s "https://query1.finance.yahoo.com/v8/finance/chart/$T?range=1mo&interval=1d" \
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
    closes_raw = quotes['close']
    highs_raw = quotes.get('high', [])
    lows_raw = quotes.get('low', [])
    volumes_raw = quotes.get('volume', [])

    # Clean None values for closes
    closes = [round(c, 2) for c in closes_raw if c is not None]
    
    # Build full history arrays (timestamp + close) for charting
    history = []
    for i, ts in enumerate(ts_raw):
        if closes_raw[i] is not None:
            history.append([ts, round(closes_raw[i], 2)])

    # Current price data
    prev = m.get('chartPreviousClose', m.get('previousClose', 0))
    price = m['regularMarketPrice']
    chg = price - prev
    pct = (chg / prev * 100) if prev else 0
    name = m.get('longName', m.get('shortName', ''))
    
    # 52-week high/low from the meta or compute from available data
    week52_high = m.get('fiftyTwoWeekHigh', None)
    week52_low = m.get('fiftyTwoWeekLow', None)
    
    # If not in meta, estimate from available highs/lows
    if week52_high is None and highs_raw:
        valid_highs = [h for h in highs_raw if h is not None]
        week52_high = max(valid_highs) if valid_highs else None
    if week52_low is None and lows_raw:
        valid_lows = [l for l in lows_raw if l is not None]
        week52_low = min(valid_lows) if valid_lows else None

    # Volume (latest)
    valid_vols = [v for v in volumes_raw if v is not None]
    vol = valid_vols[-1] if valid_vols else None

    # Build result
    result = {
        'p': round(price, 2),
        'c': round(chg, 2),
        'pct': round(pct, 2),
        'prev': round(prev, 2),
        'name': name,
        'spark': [round(c, 2) for c in closes[-5:]],
        'history': history,
        'currency': m.get('currency', 'USD'),
        'exchange': m.get('exchangeName', ''),
        'type': m.get('instrumentType', m.get('quoteType', '')),
    }

    # Optional extended fields
    if week52_high is not None:
        result['w52h'] = round(week52_high, 2)
    if week52_low is not None:
        result['w52l'] = round(week52_low, 2)
    if vol is not None:
        result['vol'] = vol

    print(json.dumps(result))
except Exception as e:
    sys.exit(1)
" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$QUOTE" ]; then
      if [ $FIRST -eq 0 ]; then echo ',' >> "$OUT"; fi
      echo "\"$T\":$QUOTE" >> "$OUT"
      FIRST=0
    fi
  fi
  sleep 0.3
done
echo '}}' >> "$OUT"
echo "Updated quotes: $(date)"
echo "Tickers fetched: $(echo $TICKERS | wc -w | tr -d ' ')"

# Generate news based on actual price data
bash "$DIR/gen-news.sh"
