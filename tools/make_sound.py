"""开屏动画的音效 (原创合成, 不用任何素材): 和 splash.html 的时间轴对齐, 输出立体声 wav.
两个预设:
  video   (默认, 新图 + 睁眼视频): 视频 4.5 秒开始播放, 约 7.0 秒睁眼, 7.6 秒出字, 9.3~10.0 秒淡出; 头发飘动时有一层轻柔的风声
  classic (原图): 6.0 秒睁眼, 6.9 秒出字, 9.3 秒结束
  0.0  空气感的噪声慢慢升起 + 低音 D 的垫音
  0.7  流光划过: 滤波噪声从左扫到右
  1.9-3.7  勾线: 稀疏的小闪光 (D 大调五声音阶的短铃音)
  3.4  眼睑亮起: 一声很轻的铃
  4.0  彩图浮现: 温暖的 Dadd9 和弦铺底
  睁眼: 上行的琶音闪光;  出字: 主铃声 (长尾音);  最后整体淡出
usage: python make_sound.py out.wav [--preset video|classic]          # 只生成 wav
       python make_sound.py out.wav [--preset ...] --js               # 再用 ffmpeg 转成 Ogg/Opus, 写进 assets/sound.js (classic: assets/classic/sound.js)"""
import sys, os, numpy as np, wave

PRESET = sys.argv[sys.argv.index('--preset') + 1] if '--preset' in sys.argv else 'video'
P = {'video':   dict(open=6.95, arp=.12, text=7.6, end=10.0, dur=10.3, wind=(4.4, 9.9)),
     'classic': dict(open=5.95, arp=.14, text=6.9, end=9.3, dur=9.6, wind=None)}[PRESET]
SR = 44100; DUR = P['dur']
t = np.arange(int(SR * DUR)) / SR
L = np.zeros_like(t); R = np.zeros_like(t)
rng = np.random.default_rng(7)


def hz(n): return 440.0 * 2 ** ((n - 69) / 12)          # MIDI -> Hz


def env(t0, a, d):
    """attack a 秒, 然后指数衰减 (时间常数 d)"""
    x = t - t0; e = np.zeros_like(t); on = x >= 0
    e[on] = np.where(x[on] < a, (x[on] / a) ** 2, np.exp(-(x[on] - a) / d))
    return e


def add(sig, pan=0.0, g=1.0):
    global L, R
    L += sig * g * np.cos((pan + 1) * np.pi / 4); R += sig * g * np.sin((pan + 1) * np.pi / 4)


def bell(t0, f, g, decay=1.6, pan=0.0):
    # 柔和的铃: 基音 + 几个略不和谐的泛音, 高泛音衰减更快
    s = np.zeros_like(t)
    for ratio, amp, dk in [(1, 1, 1), (2.0, .35, .6), (2.76, .18, .45), (4.07, .08, .3)]:
        s += amp * np.sin(2 * np.pi * f * ratio * (t - t0)) * env(t0, .004, decay * dk)
    add(s, pan, g)


def onepole(x, a):                                       # 一阶低通 (a 可以是随时间变化的数组)
    y = np.zeros_like(x); a = np.broadcast_to(a, x.shape); acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc); y[i] = acc
    return y


END = P['end']
# 0.0 空气感噪声升起 (高通后的噪声, 慢起慢收)
n = rng.standard_normal(len(t))
air = n - onepole(n, 0.25); air = onepole(air, 0.5)
shape = np.clip(t / 1.4, 0, 1) ** 2 * np.exp(-np.clip(t - 1.4, 0, None) / 1.2)
add(air * shape, -.3, .05); add(np.roll(air, 1234) * shape, .3, .05)

# 低音 D 垫音 (D2 + A2), 和后面的和弦接上
for m, g in [(38, .16), (45, .09)]:
    f = hz(m); s = np.sin(2 * np.pi * f * t) + .25 * np.sin(2 * np.pi * 2 * f * t)
    e = np.clip(t / 2.0, 0, 1) * np.clip((END - .1 - t) / 1.2, 0, 1)
    add(s * e, 0, g)

# 0.7 流光: 截止频率先升后降的滤波噪声, 从左扫到右
x = t - 0.7; w = np.exp(-((x - 0.55) / 0.42) ** 2) * (x > -0.2)
cut = 0.02 + 0.35 * np.exp(-((x - 0.55) / 0.5) ** 2)
sw = onepole(rng.standard_normal(len(t)) * w, cut)
pan = np.clip((x - 0.1) / 1.0, 0, 1) * 1.6 - .8
L += sw * .55 * np.cos((pan + 1) * np.pi / 4); R += sw * .55 * np.sin((pan + 1) * np.pi / 4)

# 1.9-3.7 勾线的小闪光
penta = [74, 76, 78, 81, 83, 86, 88, 90, 93]             # D 大调五声 (D5 起)
for k in range(14):
    t0 = 1.9 + 1.8 * k / 14 + rng.uniform(-.04, .04)
    bell(t0, hz(int(rng.choice(penta))), .045 + .02 * rng.random(), decay=.35, pan=rng.uniform(-.8, .8))

# 3.4 眼睑亮起
bell(3.4, hz(86), .07, decay=1.2, pan=-.15)

# 4.0 彩图浮现: Dadd9 和弦铺底 (D3 A3 D4 F#4 E5), 带一点颤音和左右展开
for m, g, p in [(50, .10, -.3), (57, .08, .3), (62, .07, -.2), (66, .06, .25), (76, .035, 0)]:
    f = hz(m); vib = 1 + .0025 * np.sin(2 * np.pi * 4.8 * t + m)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    s = np.sin(ph) + .3 * np.sin(2 * ph) + .12 * np.sin(3 * ph)
    e = np.clip((t - 4.0) / 1.3, 0, 1) ** 1.5 * np.clip((END - t) / 1.0, 0, 1)
    add(s * e, p, g)

# 头发飘动时的风声 (只在视频版): 带通噪声 + 缓慢的阵风包络, 左右各一路, 很轻
if P['wind']:
    w0, w1 = P['wind']
    gust = lambda ph: (.55 + .45 * np.sin(2 * np.pi * .42 * t + ph)) * (.7 + .3 * np.sin(2 * np.pi * .17 * t + 2 * ph))
    span = np.clip((t - w0) / 1.2, 0, 1) ** 2 * np.clip((w1 - t) / 1.0, 0, 1)
    for side, ph in ((-.6, 0.0), (.6, 1.9)):
        nz = rng.standard_normal(len(t))
        band = onepole(nz, .09) - onepole(nz, .012)                       # 约 90 Hz ~ 700 Hz 的柔和风声
        rustle = nz - onepole(nz, .45); rustle = onepole(rustle, .7)       # 很轻的高频 "沙沙" (发丝)
        add((band * 1.0 + rustle * .18) * gust(ph) * span, side, .09)

# 睁眼: 上行琶音
O = P['open']
for k, m in enumerate([74, 78, 81, 86, 90, 93]):
    bell(O + k * P['arp'], hz(m), .06 + k * .006, decay=.8, pan=-.5 + k * .2)

# 出字: 主铃 (D6 + A6 + F#7 轻), 长尾
X = P['text']
bell(X, hz(86), .16, decay=2.6, pan=0)
bell(X + .02, hz(93), .08, decay=2.2, pan=.2)
bell(X + .05, hz(102), .03, decay=1.6, pan=-.2)


# 简单的混响 (几条衰减延迟线), 让声音更柔
def reverb(x, mix=.28):
    y = x.copy()
    for d, g in [(0.029, .5), (0.037, .45), (0.041, .42), (0.053, .38), (0.071, .3), (0.089, .25)]:
        k = int(d * SR); z = np.zeros_like(x)
        for rep in range(1, 9):
            if k * rep >= len(x): break
            z[k * rep:] += x[:-k * rep] * g ** rep
        y += z * mix / 3
    return y


L, R = reverb(L), reverb(np.roll(R, 37))
# 总体淡入淡出 + 归一化 (峰值 -6 dBFS, 音量不大)
fade = np.clip(t / .05, 0, 1) * np.clip((DUR - t) / .6, 0, 1)
L *= fade; R *= fade
peak = max(np.abs(L).max(), np.abs(R).max()); L *= .5 / peak; R *= .5 / peak
data = (np.stack([L, R], 1) * 32767).astype('<i2')
with wave.open(sys.argv[1], 'wb') as f:
    f.setnchannels(2); f.setsampwidth(2); f.setframerate(SR); f.writeframes(data.tobytes())
print('wav', sys.argv[1], PRESET, DUR, 's')

if '--js' in sys.argv:
    import subprocess, base64
    ogg = sys.argv[1].rsplit('.', 1)[0] + '.ogg'
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', sys.argv[1], '-c:a', 'libopus', '-b:a', '96k', '-map_metadata', '-1', ogg], check=True)
    sub = ('classic',) if PRESET == 'classic' else ()
    js = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', *sub, 'sound.js')
    open(js, 'w', encoding='utf-8').write('window.SPLASH_SOUND="data:audio/ogg;base64,' + base64.b64encode(open(ogg, 'rb').read()).decode() + '";')
    print('wrote', os.path.normpath(js))
