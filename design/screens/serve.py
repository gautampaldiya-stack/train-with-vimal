# Chhota local server canvas boards ke liye. Chalao: py serve.py  (phir browser: http://localhost:8080/Main.dc.html)
import http.server, os

PORT = 8080

class H(http.server.SimpleHTTPRequestHandler):
    def guess_type(self, path):
        if os.sep + '_blob' + os.sep in path or '/_blob/' in path:
            return 'image/svg+xml'
        return super().guess_type(path)

os.chdir(os.path.dirname(os.path.abspath(__file__)))
print('Boards yahan khulenge: http://localhost:%d/Main.dc.html  (band karne ke liye Ctrl+C)' % PORT)
http.server.ThreadingHTTPServer.allow_reuse_address = True
with http.server.ThreadingHTTPServer(('127.0.0.1', PORT), H) as httpd:
    httpd.serve_forever()
