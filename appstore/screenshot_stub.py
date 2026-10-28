# Máy chủ giả CHỈ để chụp ảnh App Store trên simulator (simulator không có App Attest nên không đăng ký được với máy chủ thật).
# Nến là GIÁ THẬT lấy từ Yahoo; các mức Vào / SL / TP là số minh hoạ tính đơn giản từ nến thật, không phải kết quả của máy chủ.
import json, os
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
import yfinance as yf

WATCH = []
NAMES = {"NQ=F": "Nasdaq 100", "ES=F": "S&P 500", "BTC-USD": "Bitcoin", "ETH-USD": "Ethereum",
         "AAPL": "Apple", "NVDA": "NVIDIA", "TSLA": "Tesla", "MSFT": "Microsoft"}
PERIOD = {"1h": ("1mo", "1h"), "1d": ("6mo", "1d"), "1w": ("2y", "1wk"), "1wk": ("2y", "1wk")}
CACHE = {}


def candles(sym, iv):
    key = (sym, iv)
    if key not in CACHE:
        per, yi = PERIOD.get(iv, ("6mo", "1d"))
        d = yf.Ticker(sym).history(period=per, interval=yi).dropna()
        CACHE[key] = [{"t": int(i.timestamp()), "o": float(r.Open), "h": float(r.High), "l": float(r.Low), "c": float(r.Close), "v": float(r.Volume)}
                      for i, r in d.iterrows()]
    return CACHE[key]


def decide(cs):
    px = cs[-1]["c"]; sma = sum(c["c"] for c in cs[-20:]) / 20
    prev = sum(c["c"] for c in cs[-25:-5]) / 20
    up = px > sma and sma > prev
    down = px < sma and sma < prev
    recent = cs[-10:]
    if up or not down:
        stop = min(c["l"] for c in recent) * 0.995; side = "long"; r = px - stop
        t1, t2 = px + 1.5 * r, px + 3 * r
    else:
        stop = max(c["h"] for c in recent) * 1.005; side = "short"; r = stop - px
        t1, t2 = px - 1.5 * r, px - 3 * r
    action = "BUY" if up else "SELL" if down else "HOLD"
    return px, side, round(stop, 2), round(t1, 2), round(t2, 2), action


class H(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        b = json.dumps(obj).encode(); self.send_response(code)
        self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)

    def _path(self):
        p = urlparse(self.path).path
        while p.startswith("/api/"): p = p[4:]
        return p

    def log_message(self, *a): print(self.command, self.path, flush=True)

    def do_GET(self):
        u = urlparse(self.path); path = self._path()
        if path == "/ios/challenge": return self._send(200, {"challenge": "stub"})
        if path == "/watchlist": return self._send(200, {"watches": WATCH})
        if path.startswith("/tickers/"):
            m = path.split("/")[-1]
            d = {"us": [("AAPL", "Apple Inc."), ("MSFT", "Microsoft Corp."), ("NVDA", "NVIDIA Corp."), ("TSLA", "Tesla Inc.")],
                 "crypto": [("BTC-USD", "Bitcoin"), ("ETH-USD", "Ethereum")],
                 "futures": [("NQ=F", "E-mini Nasdaq 100"), ("ES=F", "E-mini S&P 500")]}.get(m, [])
            return self._send(200, {"tickers": [{"symbol": s, "name": n} for s, n in d]})
        if path.startswith("/quick-decision/"):
            sym = path.split("/")[-1].replace("%3D", "=")
            q = parse_qs(u.query); iv = q.get("interval", ["1d"])[0]
            cs = candles(sym, iv)
            px, side, stop, t1, t2, action = decide(cs)
            rr = round(abs(t1 - px) / abs(px - stop), 1)
            return self._send(200, {"input": {"ticker": sym, "resolved_ticker": sym, "market": q.get("market", ["us"])[0], "interval": iv},
                "decision": {"action": action, "confidence": {"label": "MEDIUM", "value_0_1": .6}},
                "price_context": {"current_price": px, "trade_side": side, "entry_zone": {"ideal": round(px, 2)},
                                  "stop_loss": stop, "targets": {"tp1": t1, "tp2": t2}, "rr_ratio": rr},
                "candles": cs})
        self._send(404, {"detail": "nf"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0); b = json.loads(self.rfile.read(n) or b"{}"); path = self._path()
        if path in ("/ios/register", "/ios/refresh"):
            return self._send(200, {"access_token": "tok", "refresh_token": "ref", "expires_in": 3600, "user_id": "u1"})
        if path == "/watchlist":
            if any(w["ticker"] == b["ticker"] for w in WATCH): return self._send(200, {"ok": True})
            WATCH.append({"id": str(len(WATCH) + 1), "ticker": b["ticker"], "asset_type": b["asset_type"], "timeframes": b["timeframes"]})
            return self._send(200, {"ok": True})
        self._send(404, {})

    def do_DELETE(self): self._send(200, {"ok": True})


HTTPServer(("127.0.0.1", 8099), H).serve_forever()
