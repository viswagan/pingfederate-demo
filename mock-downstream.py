#!/usr/bin/env python3
"""
Tiny mock "downstream service" for Flow 3 (M2M).

The Spring app calls GET http://localhost:8081/api/data with the
client-credentials Bearer token. With nothing listening on 8081 the app
falls back to a canned "mocked — downstream unavailable" response. Run this
and /api/m2m returns this LIVE payload instead.

Usage (in its own terminal):
    python3 mock-downstream.py
    # Ctrl-C to stop

Then, in another terminal:
    curl -s http://localhost:8080/api/m2m | jq .data.downstream_call
"""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

PORT = 8081


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        # Echo whether the app sent the Bearer token, just to prove it's wired up.
        has_token = self.headers.get("Authorization", "").startswith("Bearer ")
        body = json.dumps({
            "result": "LIVE downstream data",
            "records": 7,
            "source": "mock-downstream.py on :8081",
            "received_bearer_token": has_token,
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):  # keep the console quiet
        pass


if __name__ == "__main__":
    print(f"Mock downstream listening on http://localhost:{PORT}  (Ctrl-C to stop)")
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
