from http.server import BaseHTTPRequestHandler, HTTPServer
import json


class Handler(BaseHTTPRequestHandler):
    updates = 0

    def do_GET(self):
        if self.path == "/version" and self.headers.get("Authorization") == "Bearer test-secret":
            body = json.dumps({"version": "mihomo-test"}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path != "/providers/proxies" or self.headers.get("Authorization") != "Bearer test-secret":
            self.send_response(401)
            self.end_headers()
            return
        body = json.dumps({"providers": {"良心云 一": {}, "provider-two": {}}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_PUT(self):
        if self.headers.get("Authorization") != "Bearer test-secret":
            self.send_response(401)
            self.end_headers()
            return
        Handler.updates += 1
        self.send_response(204)
        self.end_headers()
        if Handler.updates >= 2:
            self.server.should_stop = True

    def log_message(self, _format, *_args):
        pass


server = HTTPServer(("127.0.0.1", 19090), Handler)
server.should_stop = False
while not server.should_stop:
    server.handle_request()
