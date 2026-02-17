#!/bin/bash
# Generate realistic market news from actual price data in quotes.json
# v3.0: Multi-sector coverage, China ADRs, finance, healthcare, crypto
DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTES="$DIR/quotes.json"
NEWS_OUT="$DIR/news.json"

if [ ! -f "$QUOTES" ]; then
  echo "No quotes.json found, skipping news generation"
  exit 1
fi

QUOTES_PATH="$QUOTES" python3 << 'PYEOF'
import json, sys, os, random
from datetime import datetime, timezone

qpath = os.environ.get("QUOTES_PATH", "quotes.json")
with open(qpath) as f:
    data = json.load(f)

quotes = data.get("quotes", {})
updated = data.get("updated", datetime.now(timezone.utc).isoformat())

# ── Sector Definitions ──
INDICES = {"^GSPC": "S&P 500", "^IXIC": "纳斯达克", "^DJI": "道指"}
SECTOR_ETFS = {
    "XLK": "科技", "XLF": "金融", "XLE": "能源",
    "XLV": "医疗", "SOXX": "半导体", "ARKK": "创新"
}
VIX_TICKER = "^VIX"

SEMI_STOCKS = ["NVDA", "AMD", "TSM", "AVGO", "ASML", "INTC", "QCOM", "ARM", "MRVL", "AMAT", "KLAC", "LRCX", "ON"]
AI_STOCKS = ["PLTR", "AI", "SNOW", "DDOG", "MDB", "PATH", "CRWD", "PANW"]
MEGA_STOCKS = ["AAPL", "MSFT", "GOOG", "AMZN", "META", "NVDA", "TSLA", "NFLX"]
CLOUD_STOCKS = ["CRM", "NOW", "ORCL", "NET", "SHOP", "UBER", "ABNB", "SQ"]
CHINA_STOCKS = ["BABA", "PDD", "JD", "BIDU", "NIO", "LI", "XPEV", "TME", "BILI", "FUTU", "TAL"]
FIN_STOCKS = ["JPM", "GS", "MS", "V", "MA", "BRK-B", "BAC", "C", "AXP", "PYPL"]
HEALTH_STOCKS = ["UNH", "LLY", "NVO", "ABBV", "MRK", "PFE", "JNJ", "AMGN", "GILD", "ISRG"]
CONSUMER_STOCKS = ["WMT", "COST", "KO", "PEP", "MCD", "DIS"]
CRYPTO_TICKERS = ["BTC-USD", "ETH-USD"]

ALL_STOCKS = SEMI_STOCKS + AI_STOCKS + MEGA_STOCKS + CLOUD_STOCKS + CHINA_STOCKS + FIN_STOCKS + HEALTH_STOCKS + CONSUMER_STOCKS

news = []
now_str = updated

def make_news(headline, summary, category, sentiment, tickers, priority=0):
    return {"headline": headline, "summary": summary, "category": category,
            "sentiment": sentiment, "tickers": tickers, "time": now_str, "priority": priority}

def avg_pct(tickers):
    vals = [quotes[t].get("pct", 0) for t in tickers if t in quotes]
    return sum(vals) / len(vals) if vals else 0

def count_up(tickers):
    up = sum(1 for t in tickers if t in quotes and quotes[t].get("pct", 0) > 0)
    total = sum(1 for t in tickers if t in quotes)
    return up, total

# ── 1. Market Overview ──
sp500 = quotes.get("^GSPC", {})
nasdaq = quotes.get("^IXIC", {})
dji = quotes.get("^DJI", {})

if sp500:
    sp_pct = sp500.get("pct", 0)
    nas_pct = nasdaq.get("pct", 0) if nasdaq else 0
    dji_pct = dji.get("pct", 0) if dji else 0
    if sp_pct > 1.5: mood, sentiment = "强劲上涨", "bullish"
    elif sp_pct > 0.3: mood, sentiment = "温和走高", "bullish"
    elif sp_pct > -0.3: mood, sentiment = "窄幅震荡", "neutral"
    elif sp_pct > -1.5: mood, sentiment = "承压下行", "bearish"
    else: mood, sentiment = "大幅下跌", "bearish"
    news.append(make_news(
        f"美股三大指数{mood} — S&P {sp_pct:+.1f}% 纳指{nas_pct:+.1f}% 道指{dji_pct:+.1f}%",
        f"标普500报{sp500.get('p', 0):,.0f}点，{'收涨' if sp_pct > 0 else '收跌'}{abs(sp_pct):.1f}%。纳斯达克{nas_pct:+.1f}%，道指{dji_pct:+.1f}%。",
        "market", sentiment, ["^GSPC", "^IXIC", "^DJI"], priority=10))

# ── 2. VIX ──
vix = quotes.get(VIX_TICKER, {})
if vix:
    vix_val = vix.get("p", 0)
    vix_chg = vix.get("pct", 0)
    if vix_val > 30:
        news.append(make_news(f"⚠️ 恐慌指数VIX飙升至{vix_val:.1f} 市场恐慌蔓延",
            f"VIX升至{vix_val:.1f}（{vix_chg:+.1f}%），投资者高度担忧。建议关注避险资产。",
            "volatility", "bearish", ["^VIX"], priority=9))
    elif vix_val > 20:
        news.append(make_news(f"VIX升至{vix_val:.1f} 市场波动加剧",
            f"恐慌指数报{vix_val:.1f}（{vix_chg:+.1f}%），高于20警戒线。注意仓位管理。",
            "volatility", "bearish" if vix_chg > 5 else "neutral", ["^VIX"], priority=7))
    elif vix_val < 15:
        news.append(make_news(f"VIX低位运行({vix_val:.1f}) 市场情绪乐观",
            f"波动率维持{vix_val:.1f}低位，风险偏好较高。",
            "volatility", "bullish", ["^VIX"], priority=4))
    else:
        news.append(make_news(f"VIX报{vix_val:.1f}（{vix_chg:+.1f}%）波动正常",
            f"恐慌指数处于15-20正常区间。",
            "volatility", "neutral", ["^VIX"], priority=3))

# ── 3. Biggest Movers ──
stock_tickers = [t for t in ALL_STOCKS if t in quotes]
movers = sorted(stock_tickers, key=lambda t: abs(quotes[t].get("pct", 0)), reverse=True)

if movers:
    top = movers[0]
    tq = quotes[top]
    pct = tq.get("pct", 0)
    name = tq.get("name", top)
    price = tq.get("p", 0)
    if abs(pct) > 3:
        direction = "飙升" if pct > 0 else "暴跌"
        reasons_up = ["受财报超预期影响", "受AI需求增长推动", "获机构上调目标价", "受战略合作提振", "受产品发布利好"]
        reasons_dn = ["受财报不及预期拖累", "受监管消息影响", "受分析师下调评级", "受竞争加剧担忧", "受宏观数据影响"]
        reason = random.choice(reasons_up if pct > 0 else reasons_dn)
        news.append(make_news(
            f"{name}({top}){direction}{abs(pct):.1f}% {reason}",
            f"{name}报${price:,.2f}，{'涨' if pct > 0 else '跌'}{abs(pct):.1f}%。成为今日{'最大赢家' if pct > 0 else '跌幅最深个股'}之一。",
            "stock", "bullish" if pct > 0 else "bearish", [top], priority=8))

    gainers = sorted([t for t in stock_tickers if quotes[t].get("pct", 0) > 0], key=lambda t: quotes[t]["pct"], reverse=True)
    losers = sorted([t for t in stock_tickers if quotes[t].get("pct", 0) < 0], key=lambda t: quotes[t]["pct"])
    if gainers:
        top3 = gainers[:3]
        parts = [f"{quotes[t].get('name', t)}({t}) +{quotes[t]['pct']:.1f}%" for t in top3]
        news.append(make_news(f"今日领涨：{'、'.join(top3)}", "涨幅居前：" + "；".join(parts) + "。",
            "movers", "bullish", top3, priority=6))
    if losers:
        bot3 = losers[:3]
        parts = [f"{quotes[t].get('name', t)}({t}) {quotes[t]['pct']:.1f}%" for t in bot3]
        news.append(make_news(f"跌幅居前：{'、'.join(bot3)}", "跌幅居前：" + "；".join(parts) + "。",
            "movers", "bearish", bot3, priority=6))

# ── 4. Sector Analysis ──
sector_data = {}
for etf, name_cn in SECTOR_ETFS.items():
    if etf in quotes:
        sector_data[etf] = {"name": name_cn, "pct": quotes[etf].get("pct", 0)}

if sector_data:
    best = max(sector_data.items(), key=lambda x: x[1]["pct"])
    worst = min(sector_data.items(), key=lambda x: x[1]["pct"])
    summary = "、".join([f"{v['name']}{v['pct']:+.1f}%" for k, v in sorted(sector_data.items(), key=lambda x: x[1]["pct"], reverse=True)])
    all_up = all(v["pct"] > 0 for v in sector_data.values())
    all_dn = all(v["pct"] < 0 for v in sector_data.values())
    news.append(make_news(
        f"板块轮动：{best[1]['name']}领涨({best[1]['pct']:+.1f}%) {worst[1]['name']}垫底({worst[1]['pct']:+.1f}%)",
        f"今日板块：{summary}。{'普涨' if all_up else '普跌' if all_dn else '分化明显'}。",
        "sector", "bullish" if best[1]["pct"] > 0 and worst[1]["pct"] > -1 else "neutral", list(sector_data.keys()), priority=7))

# ── 5. Semiconductor ──
semi_in = [t for t in SEMI_STOCKS if t in quotes]
if semi_in:
    ap = avg_pct(semi_in)
    nvda = quotes.get("NVDA", {})
    if abs(ap) > 1.5:
        d = "集体走强" if ap > 0 else "集体承压"
        news.append(make_news(
            f"半导体板块{d} NVDA{'涨' if nvda.get('pct',0)>0 else '跌'}{abs(nvda.get('pct',0)):.1f}%",
            f"芯片股{d}，板块均{'涨' if ap>0 else '跌'}{abs(ap):.1f}%。英伟达${nvda.get('p',0):,.2f}。AI算力需求持续为焦点。",
            "theme", "bullish" if ap > 0 else "bearish", semi_in[:5], priority=7))

# ── 6. China ADRs ──
china_in = [t for t in CHINA_STOCKS if t in quotes]
if china_in:
    ap = avg_pct(china_in)
    up_c, total_c = count_up(china_in)
    if abs(ap) > 1.5:
        d = "反弹" if ap > 0 else "下挫"
        baba = quotes.get("BABA", {})
        pdd = quotes.get("PDD", {})
        news.append(make_news(
            f"中概股{d} 板块均{ap:+.1f}% — {up_c}/{total_c}只上涨",
            f"阿里{baba.get('pct',0):+.1f}%，拼多多{pdd.get('pct',0):+.1f}%。{'政策利好预期推动反弹' if ap > 0 else '海外监管不确定性持续'}。",
            "theme", "bullish" if ap > 0 else "bearish", china_in[:5], priority=7))
    elif total_c > 0:
        news.append(make_news(
            f"中概股{'小幅走高' if ap > 0 else '微幅调整'} 板块均{ap:+.1f}%",
            f"中概板块{up_c}/{total_c}只上涨，整体走势{'偏暖' if ap > 0 else '偏弱'}。",
            "theme", "neutral", china_in[:3], priority=4))

# ── 7. Finance ──
fin_in = [t for t in FIN_STOCKS if t in quotes]
if fin_in:
    ap = avg_pct(fin_in)
    if abs(ap) > 1:
        jpm = quotes.get("JPM", {})
        news.append(make_news(
            f"金融板块{'走强' if ap > 0 else '走弱'} 均{ap:+.1f}% 摩根大通{jpm.get('pct',0):+.1f}%",
            f"金融股{'受加息预期和经济数据提振' if ap > 0 else '受利率下行和信贷担忧拖累'}。",
            "theme", "bullish" if ap > 0 else "bearish", fin_in[:4], priority=6))

# ── 8. Healthcare ──
health_in = [t for t in HEALTH_STOCKS if t in quotes]
if health_in:
    ap = avg_pct(health_in)
    if abs(ap) > 1:
        lly = quotes.get("LLY", {})
        unh = quotes.get("UNH", {})
        news.append(make_news(
            f"医疗板块{'领涨' if ap > 0 else '承压'} 礼来{lly.get('pct',0):+.1f}% 联合健康{unh.get('pct',0):+.1f}%",
            f"医疗健康板块均{ap:+.1f}%。{'GLP-1药物热潮和防御属性受追捧' if ap > 0 else '药品定价压力和监管不确定性'}。",
            "theme", "bullish" if ap > 0 else "bearish", health_in[:4], priority=6))

# ── 9. Crypto ──
btc = quotes.get("BTC-USD", {})
eth = quotes.get("ETH-USD", {})
if btc:
    bp = btc.get("pct", 0)
    ep = eth.get("pct", 0) if eth else 0
    if abs(bp) > 3:
        news.append(make_news(
            f"比特币{'暴涨' if bp > 0 else '暴跌'}{abs(bp):.1f}% 报${btc.get('p',0):,.0f}",
            f"BTC {bp:+.1f}%，ETH {ep:+.1f}%。{'机构资金持续流入，市场情绪乐观' if bp > 0 else '获利回吐压力加大，短期波动加剧'}。",
            "crypto", "bullish" if bp > 0 else "bearish", ["BTC-USD", "ETH-USD"], priority=7))
    elif btc.get("p", 0) > 0:
        news.append(make_news(
            f"比特币${btc.get('p',0):,.0f}（{bp:+.1f}%） 以太坊${eth.get('p',0):,.0f}（{ep:+.1f}%）",
            f"加密市场波动温和。",
            "crypto", "neutral", ["BTC-USD", "ETH-USD"], priority=3))

# ── 10. Mega-cap ──
mega_in = [t for t in MEGA_STOCKS if t in quotes]
if mega_in:
    ap = avg_pct(mega_in)
    if abs(ap) > 1.5:
        news.append(make_news(
            f"科技巨头{'齐涨' if ap > 0 else '齐跌'} 平均{ap:+.1f}%",
            "、".join([f"{quotes[t].get('name',t)}({t}) {quotes[t].get('pct',0):+.1f}%" for t in mega_in if t in quotes]) + "。",
            "theme", "bullish" if ap > 0 else "bearish", mega_in[:6], priority=6))

# ── 11. 30-day Trend ──
if sp500:
    hist = sp500.get("history", [])
    if isinstance(hist, list) and len(hist) >= 10:
        recent_5 = [h[1] for h in hist[-5:]]
        prev_5 = [h[1] for h in hist[-10:-5]]
        avg_r = sum(recent_5) / len(recent_5)
        avg_p = sum(prev_5) / len(prev_5)
        tp = (avg_r - avg_p) / avg_p * 100 if avg_p else 0
        if tp > 2: desc, outlook = "上升趋势明显", "短期均线呈多头排列"
        elif tp > 0: desc, outlook = "温和上行", "维持上行但力度有限"
        elif tp > -2: desc, outlook = "高位整理", "多空博弈加剧"
        else: desc, outlook = "回调压力加大", "短期均线走弱"
        news.append(make_news(
            f"30日趋势：标普500{desc} 近5日{'高于' if tp > 0 else '低于'}前5日{abs(tp):.1f}%",
            f"{outlook}。近5日均价{avg_r:,.0f}，前5日均价{avg_p:,.0f}。",
            "analysis", "bullish" if tp > 1 else "bearish" if tp < -1 else "neutral", ["^GSPC"], priority=5))

# ── 12. Sector Rotation Signal ──
if len(sector_data) >= 3:
    sorted_sectors = sorted(sector_data.items(), key=lambda x: x[1]["pct"], reverse=True)
    top_s = sorted_sectors[0]
    bot_s = sorted_sectors[-1]
    spread = top_s[1]["pct"] - bot_s[1]["pct"]
    if spread > 3:
        news.append(make_news(
            f"📊 板块轮动信号：资金从{bot_s[1]['name']}流向{top_s[1]['name']} 价差{spread:.1f}%",
            f"{top_s[1]['name']}板块领涨{top_s[1]['pct']:+.1f}%，{bot_s[1]['name']}板块垫底{bot_s[1]['pct']:+.1f}%。板块间价差达{spread:.1f}%，轮动信号明显。",
            "rotation", "neutral", [top_s[0], bot_s[0]], priority=8))

# Sort by priority
news.sort(key=lambda x: x["priority"], reverse=True)

output = {"updated": now_str, "count": len(news), "news": news}
news_path = os.path.join(os.path.dirname(qpath), "news.json")
with open(news_path, "w") as f:
    json.dump(output, f, ensure_ascii=False, indent=2)

print(f"Generated {len(news)} news items -> {news_path}")
PYEOF

echo "News generation complete: $(date)"
