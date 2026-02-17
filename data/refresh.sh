#!/bin/bash
# Refresh stock data from Yahoo Finance v8 chart API
# Runs on Mac mini, generates static JSON for the PWA
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/quotes.json"

TICKERS="^GSPC ^IXIC ^DJI ^VIX NVDA AMD TSM AVGO MSFT AMZN GOOG META PLTR AI CRM NOW SNOW QQQ SPY BOTZ SMH"

echo '{"updated":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","quotes":{' > "$OUT"
FIRST=1
for T in $TICKERS; do
  DATA=$(curl -s "https://query1.finance.yahoo.com/v8/finance/chart/$T?range=1mo&interval=1d" -H "User-Agent: Mozilla/5.0")
  if [ $? -eq 0 ] && echo "$DATA" | python3 -c "
import sys,json
d=json.load(sys.stdin)
r=d['chart']['result'][0]
m=r['meta']
closes=r['indicators']['quote'][0]['close']
closes=[c for c in closes if c is not None]
prev=m.get('chartPreviousClose',m.get('previousClose',0))
price=m['regularMarketPrice']
chg=price-prev
pct=(chg/prev*100) if prev else 0
name=m.get('longName',m.get('shortName',''))
print(json.dumps({'p':round(price,2),'c':round(chg,2),'pct':round(pct,2),'prev':round(prev,2),'name':name,'spark':closes[-5:]}))" 2>/dev/null; then
    QUOTE=$(echo "$DATA" | python3 -c "
import sys,json
d=json.load(sys.stdin)
r=d['chart']['result'][0]
m=r['meta']
closes=r['indicators']['quote'][0]['close']
closes=[c for c in closes if c is not None]
prev=m.get('chartPreviousClose',m.get('previousClose',0))
price=m['regularMarketPrice']
chg=price-prev
pct=(chg/prev*100) if prev else 0
name=m.get('longName',m.get('shortName',''))
print(json.dumps({'p':round(price,2),'c':round(chg,2),'pct':round(pct,2),'prev':round(prev,2),'name':name,'spark':[round(c,2) for c in closes[-5:]]}))")
    if [ $FIRST -eq 0 ]; then echo ',' >> "$OUT"; fi
    echo "\"$T\":$QUOTE" >> "$OUT"
    FIRST=0
  fi
  sleep 0.3
done
echo '}}' >> "$OUT"
echo "Updated: $(date)"
