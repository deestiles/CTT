#!/usr/bin/env python3
"""
save_bridge.py - Local companion server for the Catch the Thief web map builder.

It does two jobs:
  1. Serves the builder's static files (index.html, *.js) so you can open it in a browser.
  2. Provides a tiny JSON API so the builder can save maps directly into BOTH:
        - the repository's  maps/  folder (for git handoff)
        - Godot's           user://maps  folder (so the mobile game sees them instantly)
     and list/load existing maps.

Run it, then open the URL it prints:

    python tools/web_map_builder/save_bridge.py
    # -> http://localhost:8777

Without this bridge the builder still works fully client-side (Export/Import JSON);
the bridge only adds one-click Save/Load straight to disk.

API:
  GET  /api/ping                 -> {"ok": true}
  GET  /api/maps                 -> {"maps": [{name, items, roles, valid, source}]}
  GET  /api/map?name=<name>      -> {"ok": true, "map": {...}}
  POST /api/save  {name, map}    -> {"ok": true, "written": ["repo maps/", "user://maps"]}
"""
import json
import os
import re
import sys
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(TOOL_DIR, "..", ".."))
REPO_MAPS = os.path.join(REPO_ROOT, "maps")

SAFE_NAME = re.compile(r"[^A-Za-z0-9_\-]")


def user_maps_dir():
    """Resolve Godot's user://maps for this project on the current OS."""
    if sys.platform.startswith("win"):
        base = os.environ.get("APPDATA", os.path.expanduser("~"))
        return os.path.join(base, "Godot", "app_userdata", "Catch the Thief", "maps")
    if sys.platform == "darwin":
        return os.path.expanduser("~/Library/Application Support/Godot/app_userdata/Catch the Thief/maps")
    return os.path.expanduser("~/.local/share/godot/app_userdata/Catch the Thief/maps")


def safe_name(name):
    name = SAFE_NAME.sub("_", (name or "").strip())
    return name or "city_map"


def list_maps():
    seen = {}
    for source, folder in (("repo", REPO_MAPS), ("user", user_maps_dir())):
        if not os.path.isdir(folder):
            continue
        for fn in os.listdir(folder):
            if not fn.endswith(".json"):
                continue
            name = fn[:-5]
            if name in seen:
                continue
            info = {"name": name, "items": 0, "roles": None, "valid": None, "source": source}
            try:
                with open(os.path.join(folder, fn), "r", encoding="utf-8") as f:
                    d = json.load(f)
                info["items"] = len(d.get("items", []))
                info["roles"] = d.get("roles")
                info["valid"] = (d.get("validation") or {}).get("valid")
            except Exception:
                pass
            seen[name] = info
    return sorted(seen.values(), key=lambda m: m["name"].lower())


def read_map(name):
    name = safe_name(name)
    for folder in (REPO_MAPS, user_maps_dir()):
        p = os.path.join(folder, name + ".json")
        if os.path.isfile(p):
            with open(p, "r", encoding="utf-8") as f:
                return json.load(f)
    return None


def write_map(name, payload):
    name = safe_name(name)
    written = []
    text = json.dumps(payload, indent="\t")
    for label, folder in (("repo maps/", REPO_MAPS), ("user://maps", user_maps_dir())):
        try:
            os.makedirs(folder, exist_ok=True)
            with open(os.path.join(folder, name + ".json"), "w", encoding="utf-8") as f:
                f.write(text)
            written.append(label)
        except Exception as e:
            print(f"  ! could not write {label}: {e}")
    return written


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, obj=None, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()
        if obj is not None:
            self.wfile.write(json.dumps(obj).encode("utf-8"))

    def _serve_static(self, path):
        if path in ("/", ""):
            path = "/index.html"
        local = os.path.normpath(os.path.join(TOOL_DIR, path.lstrip("/")))
        if not local.startswith(TOOL_DIR) or not os.path.isfile(local):
            self._send(404, {"error": "not found"})
            return
        ext = os.path.splitext(local)[1].lower()
        ctype = {
            ".html": "text/html", ".js": "application/javascript", ".css": "text/css",
            ".json": "application/json", ".png": "image/png", ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg", ".svg": "image/svg+xml",
        }.get(ext, "text/plain")
        with open(local, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_OPTIONS(self):
        self._send(204)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/api/ping":
            self._send(200, {"ok": True})
        elif u.path == "/api/maps":
            self._send(200, {"maps": list_maps()})
        elif u.path == "/api/map":
            name = (parse_qs(u.query).get("name") or [""])[0]
            m = read_map(name)
            self._send(200, {"ok": bool(m), "map": m} if m else {"ok": False, "error": "not found"})
        else:
            self._serve_static(u.path)

    def do_POST(self):
        u = urlparse(self.path)
        if u.path != "/api/save":
            self._send(404, {"error": "unknown endpoint"})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
            name = body.get("name")
            payload = body.get("map")
            if not isinstance(payload, dict) or "items" not in payload:
                self._send(400, {"ok": False, "error": "missing map payload"})
                return
            written = write_map(name, payload)
            print(f"  saved '{safe_name(name)}' -> {', '.join(written) or 'nowhere'}")
            self._send(200, {"ok": bool(written), "written": written})
        except Exception as e:
            self._send(500, {"ok": False, "error": str(e)})

    def log_message(self, *args):
        pass  # keep console quiet except our own prints


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8777)
    ap.add_argument("--host", default="127.0.0.1")
    args = ap.parse_args()
    print("Catch the Thief - map builder save bridge")
    print(f"  repo maps : {REPO_MAPS}")
    print(f"  user maps : {user_maps_dir()}")
    print(f"  serving   : http://{args.host}:{args.port}")
    print("  (Ctrl+C to stop)")
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
