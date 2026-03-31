#!/bin/bash
# =============================================================================
# h4kscape-client — Build script
# Produces a self-contained static site in dist/
# =============================================================================
set -e

cd "$(dirname "$0")"

# ── Configuration (override with env vars) ───────────────────
SERVER_URL="${SERVER_URL:-https://scape.t3ks.com}"
OAUTH_ENABLED="${OAUTH_ENABLED:-true}"
OAUTH_LOGTO_ENDPOINT="${OAUTH_LOGTO_ENDPOINT:-https://auth.h4ks.com}"
OAUTH_APP_ID="${OAUTH_APP_ID:-bc40c9vfeg5i43m9j8bws}"
OAUTH_CALLBACK_URL="${OAUTH_CALLBACK_URL:-https://scape.h4ks.com/auth-callback.html}"
NODE_ID="${NODE_ID:-10}"
LOWMEM="${LOWMEM:-0}"
MEMBERS="${MEMBERS:-true}"

# Compute portoff: the client calculates WS port as (43594 + portoff + N),
# where N=1 for ws:// and N=2 for wss://. We need it to equal the server port.
# For HTTPS (443): portoff = 443 - 43594 - 2 = -43153
# For HTTP  (80):  portoff =  80 - 43594 - 1 = -43515
if echo "$SERVER_URL" | grep -q '^https'; then
    PORTOFF=$(( 443 - 43594 - 2 ))
else
    PORTOFF=$(( 80 - 43594 - 1 ))
fi

echo "Building h4kscape-client..."
echo "  SERVER_URL=$SERVER_URL"
echo "  OAUTH_ENABLED=$OAUTH_ENABLED"

# ── Prepare output directory ─────────────────────────────────
rm -rf dist
mkdir -p dist

# ── 1. Build client.js (esbuild) ────────────────────────────
cp src/js/game.ts src/js/game.ts.bak

# Modify game.ts: strip auto-run code, add constructor + export
python3 -c "
import sys
with open('src/js/game.ts', 'r') as f:
    content = f.read()

lines = content.rstrip().split('\n')
cut = len(lines)
for i in range(len(lines)-1, -1, -1):
    s = lines[i].strip()
    if s.startswith('console.log') or s.startswith('setupManifest') or s.startswith('await setup') or s.startswith('new Game'):
        cut = i
    elif s == '' and cut == i + 1:
        cut = i
    elif cut < len(lines):
        break

class_end = cut - 1
while class_end > 0 and lines[class_end].strip() != '}':
    class_end -= 1

constructor = '''
    // Constructor for standalone client
    constructor(nodeId?: number, lowMem?: boolean, members?: boolean) {
        super();
        if (typeof nodeId === 'undefined' || typeof lowMem === 'undefined' || typeof members === 'undefined') {
            return;
        }
        Client.nodeId = nodeId;
        Client.members = members;
        if (lowMem) {
            Client.setLowMemory();
        } else {
            Client.setHighMemory();
        }
        // Server address comes from the page config (injected at build or runtime)
        const cfg = (window as any).__serverConfig || {};
        Client.serverAddress = cfg.serverAddress || window.location.protocol + \"//\" + window.location.hostname;
        Client.httpAddress = cfg.httpAddress || Client.serverAddress;
        Client.portOffset = cfg.portoff ?? 0;
        this.run();
    }
'''

result = '\n'.join(lines[:class_end]) + constructor + '}\n\nexport { Game as Client };\n'
with open('src/js/game.ts', 'w') as f:
    f.write(result)
"

echo "  Bundling client.js with esbuild..."

node --input-type=module <<'EOFJS'
import * as esbuild from "esbuild";

const depsPlugin = {
    name: "deps-external",
    setup(build) {
        build.onResolve({ filter: /\/vendor\/midi(\.js)?$/ }, () => ({
            path: "midi-stub", namespace: "deps-stub"
        }));
        build.onResolve({ filter: /\/util\/AudioUtil(\.js)?$/ }, () => ({
            path: "audio-util", namespace: "deps-stub"
        }));
        build.onResolve({ filter: /\/vendor\/bzip(\.ts)?$/ }, () => ({
            path: "bzip", namespace: "deps-stub"
        }));
        build.onLoad({ filter: /^midi-stub$/, namespace: "deps-stub" }, () => ({
            contents: "/* midi side-effects handled by deps.js */",
            loader: "js"
        }));
        build.onLoad({ filter: /^audio-util$/, namespace: "deps-stub" }, () => ({
            contents: 'export { playWave, setWaveVolume, playMidi, stopMidi, setMidiVolume } from "./deps.js";',
            loader: "js"
        }));
        build.onLoad({ filter: /^bzip$/, namespace: "deps-stub" }, () => ({
            contents: `
import { BZip2 } from "./deps.js";
class Bzip {
    static load = async (bytes) => {};
    static read = (length, stream, avail_in, next_in) => {
        const compressed = new Uint8Array(avail_in);
        for (let i = 0; i < avail_in; i++) compressed[i] = stream[next_in + i] & 0xFF;
        const result = BZip2.decompress(compressed, length, true, false);
        return new Int8Array(result.buffer, result.byteOffset, result.byteLength);
    };
}
export default Bzip;
`,
            loader: "js"
        }));
    }
};

await esbuild.build({
    entryPoints: ["src/js/game.ts"],
    bundle: true,
    format: "esm",
    minify: true,
    target: "es2022",
    platform: "browser",
    outfile: "dist/client.js",
    external: ["./deps.js", "path", "module", "fs"],
    plugins: [depsPlugin],
    logLevel: "info",
});

console.log("  client.js built");
EOFJS

# Restore original game.ts
cp src/js/game.ts.bak src/js/game.ts
rm src/js/game.ts.bak

# ── 2. Copy static assets from the pre-built public/ dir ────
# deps.js, .wasm files, favicon, etc.
for f in public/deps.js public/*.wasm public/favicon.ico public/SCC1_Florestan.sf2; do
    [ -f "$f" ] && cp "$f" dist/
done

# ── 3. Generate index.html ──────────────────────────────────
cat > dist/index.html <<EOHTML
<!DOCTYPE html>
<html>
<head>
    <title>h4kscape</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=0.7">
    <style>
        html { touch-action: manipulation; }
        body, td, p { font-family: Arial, Helvetica, sans-serif; font-size: 12px; color: white; }
        body { margin: 0; overflow: auto; background-color: black; }
        #game { padding: 0; margin: 0 auto; display: block; }
        canvas {
            width: 789px; height: 532px; display: block;
            -webkit-touch-callout: none; -webkit-user-select: none;
            -moz-user-select: none; -ms-user-select: none; user-select: none;
            outline: none; -webkit-tap-highlight-color: rgba(255,255,255,0); z-index: -1;
        }
        html:-webkit-full-screen { background-color: black !important; }
        .centered { text-align: center; }
        .green { text-decoration: none; color: #04A800; }
        #controls { margin-top: 3px; margin-bottom: 10px; }
        #controls > a, #controls select { font-family: Arial, Helvetica, sans-serif; font-size: 12px; }
        select { background-color: black; color: #04A800; border: none; }
    </style>
    <script>
        function toggleFullscreen() {
            const el = document.getElementById('canvas');
            if (document.fullscreenElement) { document.exitFullscreen(); }
            else { el.requestFullscreen(); }
        }
        function saveScreenshot() {
            const a = document.getElementById('screenshot');
            a.download = 'screenshot-' + Math.floor(Date.now()/1000) + '.png';
            a.href = document.getElementById('canvas').toDataURL('image/png');
        }
        function setSize(size) {
            const c = document.getElementById('canvas');
            if (!size) size = document.getElementById('size').value;
            if (size === 'auto') {
                c.style.width = '100%'; c.style.height = 'auto';
                c.style.maxWidth = ((window.innerHeight-120)/532)*789 + 'px';
            } else {
                c.style.width = (789*parseInt(size)) + 'px';
                c.style.height = (532*parseInt(size)) + 'px';
                c.style.maxWidth = 'none';
            }
            document.getElementById('size').value = size;
            localStorage.setItem('canvasSize', size);
        }
        function setFilter(type) {
            const c = document.getElementById('canvas');
            let v = type === 'dropdown' ? document.getElementById('filtering').value : type;
            c.style.imageRendering = v;
            document.getElementById('filtering').value = v;
            localStorage.setItem('filtering', v === 'pixelated');
        }
        function loadSettings() {
            setFilter(localStorage.getItem('filtering')==='true' ? 'pixelated' : 'auto');
            const s = localStorage.getItem('canvasSize'); if (s) setSize(s);
        }
    </script>
</head>
<body>
    <center>
        <div id="game">
            <canvas id="canvas" width="789" height="532">
                Your browser cannot run this client.
            </canvas>
        </div>
        <div class="centered" id="controls">
            <select id="size" onchange="setSize();">
                <option value="1">1x Size</option>
                <option value="2">2x Size</option>
                <option value="3">3x Size</option>
                <option value="auto">Auto Sizing</option>
            </select> |
            <select id="filtering" onchange="setFilter('dropdown');">
                <option value="auto">Auto Scaling</option>
                <option value="pixelated">Pixel Scaling</option>
            </select> |
            <a class="green" href="#" onclick="toggleFullscreen();">Fullscreen</a> |
            <a class="green" href="#" id="screenshot" onclick="saveScreenshot();">Screenshot</a>
        </div>
    </center>

    <script>
        const canvas = document.getElementById('canvas');
        if (canvas) {
            const ctx = canvas.getContext('2d');
            ctx.fillStyle = 'black'; ctx.fillRect(0, 0, canvas.width, canvas.height);
            ctx.fillStyle = 'white'; ctx.font = 'bold 20px Arial'; ctx.textAlign = 'center';
            ctx.fillText('Loading...', canvas.width/2, canvas.height/2);
        }
    </script>

    <script type="module">
        import { Client } from './client.js';

        window.__serverConfig = {
            serverAddress: '${SERVER_URL}',
            httpAddress: '${SERVER_URL}',
            portoff: ${PORTOFF}
        };

        window.__oauthConfig = {
            enabled: ${OAUTH_ENABLED},
            logtoEndpoint: '${OAUTH_LOGTO_ENDPOINT}',
            appId: '${OAUTH_APP_ID}',
            callbackUrl: '${OAUTH_CALLBACK_URL}'
        };

        (() => { new Client(${NODE_ID}, ${LOWMEM}, ${MEMBERS}); })();
        loadSettings();
    </script>
</body>
</html>
EOHTML

# ── 4. Generate auth-callback.html ──────────────────────────
cat > dist/auth-callback.html <<EOCB
<!DOCTYPE html>
<html>
<head>
    <title>Logging in...</title>
    <style>
        body { background:#000; color:#fff; font-family:Arial,sans-serif;
               display:flex; align-items:center; justify-content:center; height:100vh; margin:0; }
        .status { text-align:center; font-size:14px; }
        .error { color:#ff4444; }
    </style>
</head>
<body>
    <div class="status" id="status">Completing login...</div>
    <script>
        (async () => {
            const LOGTO_ENDPOINT = '${OAUTH_LOGTO_ENDPOINT}';
            const APP_ID = '${OAUTH_APP_ID}';
            const CALLBACK_URL = '${OAUTH_CALLBACK_URL}';
            const SERVER_URL = '${SERVER_URL}';

            const status = document.getElementById('status');
            try {
                const params = new URLSearchParams(window.location.search);
                const code = params.get('code');
                const codeVerifier = localStorage.getItem('oauth_code_verifier');
                if (!code) throw new Error('No authorization code received.');
                if (!codeVerifier) throw new Error('Missing PKCE code verifier.');

                status.textContent = 'Exchanging authorization code...';
                const tokenRes = await fetch(LOGTO_ENDPOINT + '/oidc/token', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    body: new URLSearchParams({
                        grant_type: 'authorization_code',
                        code: code,
                        redirect_uri: CALLBACK_URL,
                        client_id: APP_ID,
                        code_verifier: codeVerifier
                    })
                });
                if (!tokenRes.ok) throw new Error('Token exchange failed: ' + await tokenRes.text());
                const tokens = await tokenRes.json();
                localStorage.removeItem('oauth_code_verifier');

                status.textContent = 'Verifying identity...';
                const exchangeRes = await fetch(SERVER_URL + '/auth/exchange', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ access_token: tokens.access_token })
                });
                if (!exchangeRes.ok) throw new Error('Session exchange failed: ' + await exchangeRes.text());
                const session = await exchangeRes.json();

                if (window.opener) {
                    window.opener.postMessage({
                        type: 'oauth_callback',
                        username: session.username,
                        sessionToken: session.sessionToken
                    }, window.location.origin);
                    status.textContent = 'Login successful! Closing...';
                    setTimeout(() => window.close(), 500);
                } else {
                    localStorage.setItem('oauth_session', JSON.stringify(session));
                    window.location.href = '/';
                }
            } catch (err) {
                localStorage.removeItem('oauth_code_verifier');
                status.className = 'status error';
                status.textContent = 'Login failed: ' + err.message;
            }
        })();
    </script>
</body>
</html>
EOCB

echo ""
echo "Build complete! Output in dist/"
echo "  dist/index.html          — Game page"
echo "  dist/auth-callback.html  — OAuth callback"
echo "  dist/client.js           — Game client bundle"
echo "  dist/deps.js             — WASM vendor deps"
ls -la dist/
