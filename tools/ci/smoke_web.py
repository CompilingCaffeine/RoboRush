"""Loads the exported game in a real browser and waits for it to say it booted.

    python3 tools/ci/smoke_web.py [directory] [--screenshot shot.png]

tools/ci/verify_web.sh checks that the artifact contains what it should. This checks the only
thing that cannot be established by reading files: that a browser given those files actually
starts the game. Between the two sits the entire web platform — a WASM module that has to
instantiate, a pack that has to be fetched and mounted, audio that has to survive being blocked
until a gesture, and a GDScript autoload that has to run. None of that is visible in a directory
listing, and all of it has failed for somebody at some point.

The signal it waits for is the one line the bootstrap prints unconditionally, immediately before
the main menu is shown. That line is emitted after the engine has started, the pack has mounted,
the autoloads have run, the platform has answered or timed out, and the save is readable — so
seeing it means every one of those happened, and seeing nothing means the run can say which of
them it was still waiting for.

The server here deliberately sends no cross-origin isolation headers. The Web preset is
single-threaded precisely so the game does not need them, and a smoke test that supplied them
would be qualifying a build against a host kinder than the real one.
"""

import argparse
import functools
import http.server
import re
import socketserver
import sys
import threading

# The line the bootstrap prints just before handing over to the menu.
READY = re.compile(r"Robo Rush (\S+) ready: (.+)")

# Godot's own console banner, which arrives much earlier. Waited for separately so that a failure
# can distinguish "the engine never started" from "the engine started and the game did not".
BANNER = re.compile(r"Godot Engine v([\d.]+)")

# Types the game is served with. Python's own table is close but not guaranteed to know .wasm or
# .pck, and a WASM module served as text/plain fails to stream-compile in every browser.
CONTENT_TYPES = {
    ".css": "text/css",
    ".html": "text/html",
    ".js": "text/javascript",
    ".json": "application/json",
    ".pck": "application/octet-stream",
    ".png": "image/png",
    ".wasm": "application/wasm",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def guess_type(self, path):
        for suffix, content_type in CONTENT_TYPES.items():
            if path.endswith(suffix):
                return content_type
        return super().guess_type(path)

    def log_message(self, *args):
        pass  # The transcript that matters is the browser's, below.


class Server(socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def serve(directory):
    server = Server(("127.0.0.1", 0), functools.partial(Handler, directory=directory))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, "http://127.0.0.1:%d/index.html" % server.server_address[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", nargs="?", default="build/web")
    parser.add_argument("--screenshot", default="")
    parser.add_argument("--timeout", type=float, default=90.0,
                        help="seconds to wait for the game to report itself ready")
    options = parser.parse_args()

    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        raise SystemExit(
            "smoke_web: playwright is not installed.\n"
            "  python3 -m pip install playwright && python3 -m playwright install chromium"
        )

    server, url = serve(options.directory)
    print("smoke_web: serving %s at %s" % (options.directory, url))

    console = []
    problems = []

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        # A fixed viewport so a screenshot from one run can be compared with the next, and so the
        # canvas resize policy has something definite to resize to.
        page = browser.new_context(viewport={"width": 1280, "height": 720}).new_page()

        page.on("console", lambda message: console.append(message.text))
        # Both of these are failures the page itself would survive silently. An uncaught exception
        # in the engine's JavaScript leaves a canvas that never draws, and a 404 on the pack leaves
        # one that draws a progress bar forever.
        page.on("pageerror", lambda error: problems.append("uncaught JavaScript error: %s" % error))
        page.on("requestfailed", lambda request: problems.append(
            "request failed: %s (%s)" % (request.url, request.failure)))

        def on_response(response):
            if response.status >= 400:
                problems.append("HTTP %d for %s" % (response.status, response.url))

        page.on("response", on_response)

        page.goto(url, wait_until="domcontentloaded")

        ready = None
        deadline = options.timeout
        step = 0.5
        waited = 0.0
        while waited < deadline:
            ready = next((line for line in console if READY.search(line)), None)
            if ready is not None:
                break
            page.wait_for_timeout(step * 1000)
            waited += step

        if options.screenshot:
            # Taken whether or not the boot succeeded — a screenshot of the failure is the most
            # useful thing this can leave behind for somebody reading a CI run afterwards.
            page.screenshot(path=options.screenshot)
            print("smoke_web: screenshot at %s" % options.screenshot)

        canvas = page.evaluate(
            """() => {
                const canvas = document.querySelector('canvas');
                return canvas ? {width: canvas.width, height: canvas.height} : null;
            }"""
        )
        browser.close()

    server.shutdown()

    banner = next((line for line in console if BANNER.search(line)), None)

    print("smoke_web: %d console lines" % len(console))
    for line in console:
        print("    | %s" % line)

    if banner is None:
        problems.append("the engine never printed its banner: the WASM module did not start")
    if ready is None:
        problems.append(
            "the game did not report itself ready within %.0fs. The engine %s."
            % (options.timeout, "started but the boot did not finish" if banner else "never started")
        )
    if canvas is None:
        problems.append("the page has no canvas")
    elif canvas["width"] == 0 or canvas["height"] == 0:
        problems.append("the canvas is %dx%d" % (canvas["width"], canvas["height"]))

    if problems:
        print("\nsmoke_web: FAILED")
        for problem in problems:
            print("  x %s" % problem)
        return 1

    build, persistence = READY.search(ready).groups()
    print("\nsmoke_web: OK")
    print("  . %s" % banner.strip())
    print("  . build %s booted to the menu, %s" % (build, persistence))
    print("  . canvas %dx%d" % (canvas["width"], canvas["height"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
