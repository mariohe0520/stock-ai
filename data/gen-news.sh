#!/bin/bash
# Generate realistic market news from actual price data in quotes.json
# Called automatically by refresh.sh after data fetch
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

# Categorize tickers
INDICES = {"^GSPC": "S&P 500", "^IXIC": "纳斯达克", "^DJI": "道指"}
SECTORS = {
    "XLK": "科技板块", "XLF": "金融板块", 
    "XLE": "能源板块", "XLV": "医疗板块"
}
SECTOR_NAMES_EN = {
    "XLK": "Technology", "XLF": "Financials",
    "XLE": "Energy", "XLV": "Healthcare"
}
VIX_TICKER = "^VIX"
AI_STOCKS = ["NVDA", "AMD", "TSM", "AVGO", "MSFT", "AMZN", "GOOG", "META", "PLTR", "AI", "CRM", "NOW", "SNOW"]

news = []
now_str = updated

def make_news(headline, summary, category, sentiment, tickers, priority=0):
    return {
        "headline": headline,
        "summary": summary,
        "category": category,
        "sentiment": sentiment,
        "tickers": tickers,
        "time": now_str,
        "priority": priority
    }

# 1. Market overview from indices
sp500 = quotes.get("^GSPC", {})
nasdaq = quotes.get("^IXIC", {})
dji = quotes.get("^DJI", {})

if sp500:
    sp_pct = sp500.get("pct", 0)
    nas_pct = nasdaq.get("pct", 0) if nasdaq else 0
    dji_pct = dji.get("pct", 0) if dji else 0
    
    if sp_pct > 1.5:
        mood = "强劲上涨"
        sentiment = "bullish"
    elif sp_pct > 0.3:
        mood = "温和走高"
        sentiment = "bullish"
    elif sp_pct > -0.3:
        mood = "窄幅震荡"
        sentiment = "neutral"
    elif sp_pct > -1.5:
        mood = "承压下行"
        sentiment = "bearish"
    else:
        mood = "大幅下跌"
        sentiment = "bearish"
    
    news.append(make_news(
        f"美股三大指数{mood} — S&P {sp_pct:+.1f}% 纳指{nas_pct:+.1f}% 道指{dji_pct:+.1f}%",
        f"标普500报{sp500.get('p', 0):,.0f}点，{'收涨' if sp_pct > 0 else '收跌'}{abs(sp_pct):.1f}%。"
        f"纳斯达克综合指数{nas_pct:+.1f}%，道琼斯工业指数{dji_pct:+.1f}%。",
        "market",
        sentiment,
        ["^GSPC", "^IXIC", "^DJI"],
        priority=10
    ))

# 2. VIX / Volatility news
vix = quotes.get(VIX_TICKER, {})
if vix:
    vix_val = vix.get("p", 0)
    vix_chg = vix.get("pct", 0)
    
    if vix_val > 30:
        news.append(make_news(
            f"⚠️ 恐慌指数VIX飙升至{vix_val:.1f} 市场恐慌情绪蔓延",
            f"CBOE波动率指数VIX升至{vix_val:.1f}，日内涨幅{vix_chg:+.1f}%，表明投资者对市场前景高度担忧。建议关注避险资产配置。",
            "volatility",
            "bearish",
            ["^VIX"],
            priority=9
        ))
    elif vix_val > 20:
        news.append(make_news(
            f"VIX指数升至{vix_val:.1f} 市场波动加剧需警惕风险",
            f"恐慌指数VIX报{vix_val:.1f}（{vix_chg:+.1f}%），高于20的警戒线。市场不确定性上升，短线操作需注意仓位管理。",
            "volatility",
            "bearish" if vix_chg > 5 else "neutral",
            ["^VIX"],
            priority=7
        ))
    elif vix_val < 15:
        news.append(make_news(
            f"VIX低位运行({vix_val:.1f}) 市场情绪乐观",
            f"波动率指数维持在{vix_val:.1f}低位水平，显示市场风险偏好较高，投资者情绪稳定。",
            "volatility",
            "bullish",
            ["^VIX"],
            priority=4
        ))
    else:
        news.append(make_news(
            f"VIX指数报{vix_val:.1f}（{vix_chg:+.1f}%）市场波动处于正常区间",
            f"恐慌指数维持在{vix_val:.1f}，处于15-20的正常波动区间。",
            "volatility",
            "neutral",
            ["^VIX"],
            priority=3
        ))

# 3. Biggest movers (top gainers & losers)
stock_tickers = [t for t in AI_STOCKS if t in quotes]
movers = sorted(stock_tickers, key=lambda t: abs(quotes[t].get("pct", 0)), reverse=True)

if movers:
    # Top gainer
    top = movers[0]
    tq = quotes[top]
    pct = tq.get("pct", 0)
    name = tq.get("name", top)
    price = tq.get("p", 0)
    
    if abs(pct) > 3:
        direction = "飙升" if pct > 0 else "暴跌"
        reason_pool_up = [
            "受财报超预期影响",
            "受AI需求增长预期推动",
            "获多家机构上调目标价",
            "受战略合作消息提振",
            "受产品发布利好刺激"
        ]
        reason_pool_down = [
            "受财报不及预期拖累",
            "受行业监管消息影响",
            "受分析师下调评级打压",
            "受竞争加剧担忧影响",
            "受宏观经济数据影响"
        ]
        reasons = reason_pool_up if pct > 0 else reason_pool_down
        reason = random.choice(reasons)
        
        news.append(make_news(
            f"{name}({top}){direction}{abs(pct):.1f}% {reason}",
            f"{name}报${price:,.2f}，{'涨' if pct > 0 else '跌'}{abs(pct):.1f}%。{reason}，成为今日{'最大赢家' if pct > 0 else '跌幅最深个股'}之一。",
            "stock",
            "bullish" if pct > 0 else "bearish",
            [top],
            priority=8
        ))

    # Find biggest gainer and loser separately
    gainers = [t for t in stock_tickers if quotes[t].get("pct", 0) > 0]
    losers = [t for t in stock_tickers if quotes[t].get("pct", 0) < 0]
    
    if gainers:
        gainers.sort(key=lambda t: quotes[t].get("pct", 0), reverse=True)
        top3 = gainers[:3]
        parts = [f"{quotes[t].get('name', t)}({t}) +{quotes[t]['pct']:.1f}%" for t in top3]
        news.append(make_news(
            f"今日领涨：{'、'.join([t for t in top3])} AI板块{'走强' if len(gainers) > len(losers) else '分化'}",
            "涨幅居前：" + "；".join(parts) + "。",
            "movers",
            "bullish",
            top3,
            priority=6
        ))
    
    if losers:
        losers.sort(key=lambda t: quotes[t].get("pct", 0))
        bot3 = losers[:3]
        parts = [f"{quotes[t].get('name', t)}({t}) {quotes[t]['pct']:.1f}%" for t in bot3]
        news.append(make_news(
            f"跌幅居前：{'、'.join([t for t in bot3])} 承受抛压",
            "跌幅居前：" + "；".join(parts) + "。",
            "movers",
            "bearish",
            bot3,
            priority=6
        ))

# 4. Sector analysis from ETFs
sector_data = {}
for etf, name_cn in SECTORS.items():
    if etf in quotes:
        sector_data[etf] = {
            "name": name_cn,
            "pct": quotes[etf].get("pct", 0),
            "price": quotes[etf].get("p", 0)
        }

if sector_data:
    best_sector = max(sector_data.items(), key=lambda x: x[1]["pct"])
    worst_sector = min(sector_data.items(), key=lambda x: x[1]["pct"])
    
    sector_summary = "、".join([
        f"{v['name']}{v['pct']:+.1f}%" for k, v in sorted(sector_data.items(), key=lambda x: x[1]["pct"], reverse=True)
    ])
    
    news.append(make_news(
        f"板块轮动：{best_sector[1]['name']}领涨({best_sector[1]['pct']:+.1f}%) {worst_sector[1]['name']}垫底({worst_sector[1]['pct']:+.1f}%)",
        f"今日板块表现：{sector_summary}。{'板块普涨' if all(v['pct'] > 0 for v in sector_data.values()) else '板块普跌' if all(v['pct'] < 0 for v in sector_data.values()) else '板块分化明显'}。",
        "sector",
        "bullish" if best_sector[1]["pct"] > 0 and worst_sector[1]["pct"] > -1 else "bearish" if worst_sector[1]["pct"] < -1 else "neutral",
        list(sector_data.keys()),
        priority=7
    ))

# 5. AI / Semiconductor theme news
semi_tickers = ["NVDA", "AMD", "TSM", "AVGO", "SMH"]
semi_in_data = [t for t in semi_tickers if t in quotes]
if semi_in_data:
    avg_pct = sum(quotes[t].get("pct", 0) for t in semi_in_data) / len(semi_in_data)
    nvda = quotes.get("NVDA", {})
    
    if abs(avg_pct) > 2:
        direction = "集体走强" if avg_pct > 0 else "集体承压"
        news.append(make_news(
            f"半导体板块{direction} NVDA{'涨' if nvda.get('pct',0) > 0 else '跌'}{abs(nvda.get('pct',0)):.1f}%",
            f"芯片股今日{direction}，板块平均{'涨' if avg_pct > 0 else '跌'}{abs(avg_pct):.1f}%。英伟达报${nvda.get('p',0):,.2f}，AMD报${quotes.get('AMD',{}).get('p',0):,.2f}。AI算力需求持续成为市场焦点。",
            "theme",
            "bullish" if avg_pct > 0 else "bearish",
            semi_in_data,
            priority=7
        ))

# 6. FAANG+ / Mega cap analysis
mega = ["MSFT", "AMZN", "GOOG", "META"]
mega_in = [t for t in mega if t in quotes]
if mega_in:
    avg_mega = sum(quotes[t].get("pct", 0) for t in mega_in) / len(mega_in)
    if abs(avg_mega) > 1.5:
        news.append(make_news(
            f"科技巨头{'齐涨' if avg_mega > 0 else '齐跌'} 平均{avg_mega:+.1f}%",
            "、".join([f"{quotes[t].get('name',t)}({t}) {quotes[t].get('pct',0):+.1f}%" for t in mega_in]) + "。",
            "theme",
            "bullish" if avg_mega > 0 else "bearish",
            mega_in,
            priority=6
        ))

# 7. Market condition / trend analysis from 30-day data
if sp500 and "history" in sp500:
    hist = sp500["history"]
    if len(hist) >= 10:
        recent_5 = [h[1] for h in hist[-5:]]
        prev_5 = [h[1] for h in hist[-10:-5]]
        avg_recent = sum(recent_5) / len(recent_5)
        avg_prev = sum(prev_5) / len(prev_5)
        trend_pct = (avg_recent - avg_prev) / avg_prev * 100
        
        if trend_pct > 2:
            trend_desc = "上升趋势明显"
            outlook = "短期均线呈多头排列，市场动能偏强"
        elif trend_pct > 0:
            trend_desc = "温和上行"
            outlook = "市场维持上行态势但力度有限"
        elif trend_pct > -2:
            trend_desc = "高位整理"
            outlook = "近期走势趋平，多空博弈加剧"
        else:
            trend_desc = "回调压力加大"
            outlook = "短期均线走弱，需关注支撑位"
        
        news.append(make_news(
            f"30日趋势：标普500{trend_desc} 近5日均价{'高于' if trend_pct > 0 else '低于'}前5日{abs(trend_pct):.1f}%",
            f"{outlook}。标普500近5日均价{avg_recent:,.0f}，前5日均价{avg_prev:,.0f}。",
            "analysis",
            "bullish" if trend_pct > 1 else "bearish" if trend_pct < -1 else "neutral",
            ["^GSPC"],
            priority=5
        ))

# Sort by priority
news.sort(key=lambda x: x["priority"], reverse=True)

output = {
    "updated": now_str,
    "count": len(news),
    "news": news
}

news_path = os.path.join(os.path.dirname(qpath), "news.json")
with open(news_path, "w") as f:
    json.dump(output, f, ensure_ascii=False, indent=2)

print(f"Generated {len(news)} news items -> {news_path}")
PYEOF

echo "News generation complete: $(date)"
