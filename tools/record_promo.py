"""Record the splash frame by frame through a private headless Edge (DevTools protocol on 127.0.0.1, throwaway profile).
usage: python record_promo.py <page_url> <out_dir> [fps] [seconds]
e.g.   python tools/record_promo.py "file:///C:/path/to/claude-desktop-splash/splash.html?mute&record" frames 30 9.6
needs: Python 3 + aiohttp, Microsoft Edge. The page's ?record mode renders frame t on __frame(t); frames -> video with ffmpeg."""
import sys, os, json, time, base64, asyncio, subprocess, tempfile, shutil, urllib.request
import aiohttp

URL, OUT = sys.argv[1], sys.argv[2]
FPS = int(sys.argv[3]) if len(sys.argv) > 3 else 30
SEC = float(sys.argv[4]) if len(sys.argv) > 4 else 9.6
EDGE = next(p for p in [os.path.expandvars(r'%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe'),
                        os.path.expandvars(r'%ProgramFiles%\Microsoft\Edge\Application\msedge.exe')] if os.path.exists(p))
PORT = 9387
os.makedirs(OUT, exist_ok=True)
prof = tempfile.mkdtemp(prefix='rec_edge_')
proc = subprocess.Popen([EDGE, '--headless=new', '--disable-gpu', f'--remote-debugging-port={PORT}', '--remote-debugging-address=127.0.0.1',
                         f'--user-data-dir={prof}', '--hide-scrollbars', '--window-size=1920,1080', '--no-first-run', 'about:blank'])


async def main():
    for _ in range(50):
        try:
            tabs = json.loads(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json').read()); break
        except Exception:
            time.sleep(.3)
    ws_url = next(t['webSocketDebuggerUrl'] for t in tabs if t.get('type') == 'page')
    async with aiohttp.ClientSession() as s:
        async with s.ws_connect(ws_url, max_msg_size=0) as ws:
            n = 0
            async def call(method, **params):
                nonlocal n; n += 1; mid = n
                await ws.send_json({'id': mid, 'method': method, 'params': params})
                while True:
                    m = await ws.receive_json()
                    if m.get('id') == mid:
                        if 'error' in m: raise RuntimeError(m['error'])
                        return m.get('result', {})
            await call('Emulation.setDeviceMetricsOverride', width=1920, height=1080, deviceScaleFactor=1, mobile=False)
            await call('Page.enable')
            await call('Page.navigate', url=URL)
            for _ in range(200):
                r = await call('Runtime.evaluate', expression="document.documentElement.dataset.rec || ''", returnByValue=True)
                if r['result'].get('value') == 'ready': break
                await asyncio.sleep(.1)
            else:
                raise RuntimeError('page never became ready')
            total = int(SEC * FPS)
            for k in range(total):
                await call('Runtime.evaluate', expression=f'__frame({k / FPS:.5f})', returnByValue=True)
                shot = await call('Page.captureScreenshot', format='png', fromSurface=True)
                open(os.path.join(OUT, f'f{k:04d}.png'), 'wb').write(base64.b64decode(shot['data']))
                if k % 30 == 0: print('frame', k, flush=True)
    print('done', total, 'frames', flush=True)

try:
    asyncio.run(main())
finally:
    proc.terminate()
    try: proc.wait(10)
    except Exception: proc.kill()
    time.sleep(1); shutil.rmtree(prof, ignore_errors=True)
