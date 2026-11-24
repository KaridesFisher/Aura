#!/usr/bin/env python3
"""Local UI QA provider. Only generated demo/demo credentials, bundled CC media.

Run: python3 Scripts/offline-fixture.py
Add an Xtream source at http://127.0.0.1:8777, username/password: demo/demo.
"""
import json
import re
import argparse
import base64
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parents[1] / "Sources/Aura/Resources"
BASE = "http://127.0.0.1:8777"
STATE_FILE = None


class Fixture(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        parsed = urlsplit(self.path)
        query = parse_qs(parsed.query)
        if parsed.path in ("/player_api.php", "/xmltv.php"):
            state = json.loads(STATE_FILE.read_text()) if STATE_FILE and STATE_FILE.exists() else {}
            action = "xmltv" if parsed.path == "/xmltv.php" else query.get("action", ["auth"])[0]
            revision = state.get("revision", 1)
            print(json.dumps({"action": action, "revision": revision, "offline": state.get("offline", False)}), flush=True)
            if state.get("offline"):
                return self.send_error(503)
            if query.get("username") != ["demo"] or query.get("password") != ["demo"]:
                return self.json({"user_info": {"auth": 0}})
            if action == "xmltv":
                now = int(time.time())
                stamp = lambda value: datetime.fromtimestamp(value, timezone.utc).strftime("%Y%m%d%H%M%S +0000")
                xml = f'''<?xml version="1.0" encoding="UTF-8"?><tv>
                <programme channel="aura-test" start="{stamp(now-300)}" stop="{stamp(now+1800)}"><title>Rehber sürüm {revision} · Şimdi</title></programme>
                <programme channel="aura-test" start="{stamp(now+1800)}" stop="{stamp(now+3600)}"><title>Rehber sürüm {revision} · Sıradaki</title></programme></tv>'''
                data = xml.encode()
                self.send_response(200); self.send_header("Content-Type", "application/xml; charset=utf-8")
                self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
                return
            if action == "auth":
                data = {"user_info": {"auth": 1, "status": "Active", "max_connections": "4"}}
            elif action.endswith("_categories"):
                data = [{"category_id": "1", "category_name": "Çevrimdışı test"}]
            elif action == "get_live_streams":
                data = [{"stream_id": "10", "name": "Aura Test TV", "category_id": "1", "epg_channel_id": "aura-test", "stream_icon": BASE + "/art/Sintel.jpg"}]
            elif action == "get_vod_streams":
                data = [{"stream_id": "20", "name": "Sintel · Test filmi", "category_id": "1", "stream_icon": BASE + "/art/Sintel.jpg", "container_extension": "mp4"}]
            elif action == "get_series":
                data = [{"series_id": "30", "name": "Sintel · Test dizisi", "category_id": "1", "cover": BASE + "/art/Sintel.jpg", "plot": "Bölüm ilerlemesi ve kaldığın yerden oynatma için yerel test."}]
            elif action == "get_series_info":
                def episode(stream, number, title):
                    return {"id": str(stream), "episode_num": number, "title": title, "container_extension": "mp4", "info": {"duration_secs": "52", "movie_image": BASE + "/art/Sintel.jpg"}}
                data = {"episodes": {"1": [episode(31, 1, "Yolculuk"), episode(32, 2, "Karşılaşma")], "2": [episode(33, 1, "Yeni bir başlangıç")]}}
            elif action == "get_vod_info":
                data = {"info": {"plot": "Blender Studio’nun açık lisanslı Sintel fragmanı.", "duration_secs": "52"}}
            elif action == "get_simple_data_table":
                now = int(time.time())
                def programme(title, start, end):
                    return {"title": base64.b64encode(title.encode()).decode(), "description": "", "start_timestamp": start, "stop_timestamp": end}
                data = {"epg_listings": [programme(f"Rehber sürüm {revision} · Şimdi", now - 300, now + 1800), programme(f"Rehber sürüm {revision} · Sıradaki", now + 1800, now + 3600)]}
            else:
                data = {}
            return self.json(data)
        if re.fullmatch(r"/(movie|series)/demo/demo/\d+\.mp4", parsed.path):
            return self.file(ROOT / "Video/SintelTrailer.mp4", "video/mp4")
        if parsed.path == "/art/Sintel.jpg":
            return self.file(ROOT / "Artwork/Sintel.jpg", "image/jpeg")
        self.send_error(404)

    def json(self, value):
        data = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def file(self, path, content_type):
        size = path.stat().st_size
        start, end = 0, size - 1
        requested = self.headers.get("Range")
        if requested:
            match = re.fullmatch(r"bytes=(\d+)-(\d*)", requested)
            if not match:
                return self.send_error(416)
            start = int(match[1]); end = min(int(match[2]), end) if match[2] else end
            if start > end or start >= size:
                return self.send_error(416)
        self.send_response(206 if requested else 200)
        self.send_header("Content-Type", content_type)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if requested:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        try:
            with path.open("rb") as media:
                media.seek(start)
                remaining = end - start + 1
                while remaining:
                    chunk = media.read(min(65536, remaining))
                    self.wfile.write(chunk); remaining -= len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-file", type=Path, help='Optional JSON: {"revision": 2, "offline": false}')
    STATE_FILE = parser.parse_args().state_file
    print("Aura offline fixture: http://127.0.0.1:8777 · demo/demo", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 8777), Fixture).serve_forever()
