import http.server
import socketserver
import os
import sys

# Default port and web directory
PORT = 8888
root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
web_build_dir = os.path.join(root_dir, "build", "web")
web_pkg_dir = os.path.join(root_dir, "web")

DIRECTORY = web_build_dir if os.path.exists(web_build_dir) else web_pkg_dir

class NoCacheHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        # Force browsers not to cache web resources
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0, post-check=0, pre-check=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()

if __name__ == '__main__':
    port = PORT
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            pass

    print(f"Starting No-Cache Web Server on port {port}...")
    print(f"Serving directory: {DIRECTORY}")

    socketserver.TCPServer.allow_reuse_address = True
    try:
        with socketserver.TCPServer(("0.0.0.0", port), NoCacheHTTPRequestHandler) as httpd:
            print(f"Web server is ready at http://localhost:{port}")
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping web server...")
