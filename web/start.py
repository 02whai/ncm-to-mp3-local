#!/usr/bin/env python3
"""Serve the packaged static page on loopback only. No audio or user data is uploaded."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import errno
import signal
import threading
import webbrowser


class StaticFiles(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        '.js': 'application/javascript',
        '.mjs': 'application/javascript',
        '.wasm': 'application/wasm',
    }

    def log_message(self, *_args):
        pass

    def list_directory(self, _path):
        self.send_error(404)
        return None


def main():
    parser = argparse.ArgumentParser(description='NCM 转 MP3 本地静态网页版')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--no-open', action='store_true')
    arguments = parser.parse_args()
    here = Path(__file__).resolve().parent
    directory = here / 'dist' if (here / 'dist/index.html').is_file() else here
    if not (directory / 'index.html').is_file():
        raise SystemExit('未找到网页文件，请先运行 npm run build。')
    handler = partial(StaticFiles, directory=str(directory))
    try:
        server = ThreadingHTTPServer(('127.0.0.1', arguments.port), handler)
    except OSError as error:
        if error.errno != errno.EADDRINUSE:
            raise
        server = ThreadingHTTPServer(('127.0.0.1', 0), handler)
    server.daemon_threads = True
    url = f'http://127.0.0.1:{server.server_port}/'
    print(f'本地地址：{url}', flush=True)
    print('关闭此窗口或按 Ctrl+C 即可停止。', flush=True)
    if not arguments.no_open:
        webbrowser.open(url)

    def stop(_signal, _frame):
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
