import AppKit

/// Страница-пульт для iPhone (Safari / «На экран Домой»)
enum RemotePage {
    static let manifest = ##"{"name":"NotchDeck","short_name":"Пульт","display":"standalone","background_color":"#000000","theme_color":"#000000"}"##

    /// Иконка пульта для экрана «Домой»: островок с кнопкой Play и эквалайзером на тёмном фоне со свечением
    static let icon: Data = render(180)

    static func render(_ px: Int) -> Data {
        let s = CGFloat(px)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Data() }
        func col(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
        }
        let cyan: UInt32 = 0x3EE6FF, blue: UInt32 = 0x5B7CFF, violet: UInt32 = 0x9B5BFF
        // фон: глубокий ночной градиент (iOS сама скруглит углы)
        c.drawLinearGradient(CGGradient(colorsSpace: cs, colors: [col(0x141A2E), col(0x05070D)] as CFArray, locations: [0, 1])!,
                             start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
        // мягкое свечение под островком
        c.drawRadialGradient(CGGradient(colorsSpace: cs, colors: [col(blue, 0.55), col(blue, 0)] as CFArray, locations: [0, 1])!,
                             startCenter: CGPoint(x: s * 0.5, y: s * 0.42), startRadius: 0,
                             endCenter: CGPoint(x: s * 0.5, y: s * 0.42), endRadius: s * 0.62, options: [])
        c.drawRadialGradient(CGGradient(colorsSpace: cs, colors: [col(cyan, 0.35), col(cyan, 0)] as CFArray, locations: [0, 1])!,
                             startCenter: CGPoint(x: s * 0.3, y: s * 0.58), startRadius: 0,
                             endCenter: CGPoint(x: s * 0.3, y: s * 0.58), endRadius: s * 0.4, options: [])
        // островок
        let w = s * 0.74, h = s * 0.3
        let r = CGRect(x: (s - w) / 2, y: s * 0.5 - h / 2, width: w, height: h)
        let pill = CGPath(roundedRect: r, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.08, color: col(0x000000, 0.7))
        c.addPath(pill); c.setFillColor(col(0x000000)); c.fillPath()
        c.restoreGState()
        c.addPath(pill); c.setStrokeColor(col(0xFFFFFF, 0.14)); c.setLineWidth(max(1, s * 0.008)); c.strokePath()
        // кнопка Play — градиентный круг
        let d = h * 0.7
        let pc = CGRect(x: r.minX + (h - d) / 2, y: r.midY - d / 2, width: d, height: d)
        let grad = CGGradient(colorsSpace: cs, colors: [col(cyan), col(blue), col(violet)] as CFArray, locations: [0, 0.6, 1])!
        c.saveGState()
        c.setShadow(offset: .zero, blur: s * 0.06, color: col(cyan, 0.8))
        c.addEllipse(in: pc); c.setFillColor(col(cyan)); c.fillPath()
        c.restoreGState()
        c.saveGState(); c.addEllipse(in: pc); c.clip()
        c.drawLinearGradient(grad, start: CGPoint(x: pc.minX, y: pc.maxY), end: CGPoint(x: pc.maxX, y: pc.minY), options: [])
        c.restoreGState()
        let t = d * 0.36
        let tri = CGMutablePath()
        tri.move(to: CGPoint(x: pc.midX - t * 0.42, y: pc.midY + t * 0.58))
        tri.addLine(to: CGPoint(x: pc.midX - t * 0.42, y: pc.midY - t * 0.58))
        tri.addLine(to: CGPoint(x: pc.midX + t * 0.62, y: pc.midY))
        tri.closeSubpath()
        c.addPath(tri); c.setFillColor(col(0x000000)); c.setLineJoin(.round); c.setLineWidth(s * 0.012)
        c.setStrokeColor(col(0x000000)); c.drawPath(using: .fillStroke)
        // эквалайзер
        let heights: [CGFloat] = [0.38, 0.72, 0.5, 0.86, 0.44]
        let bw = s * 0.032, gap = s * 0.026
        let total = CGFloat(heights.count) * bw + CGFloat(heights.count - 1) * gap
        var x = r.maxX - h * 0.42 - total
        for k in heights {
            let bh = h * 0.62 * k
            let br = CGRect(x: x, y: r.midY - bh / 2, width: bw, height: bh)
            c.saveGState()
            c.addPath(CGPath(roundedRect: br, cornerWidth: bw / 2, cornerHeight: bw / 2, transform: nil)); c.clip()
            c.drawLinearGradient(grad, start: CGPoint(x: r.minX, y: r.maxY), end: CGPoint(x: r.maxX, y: r.minY), options: [])
            c.restoreGState()
            x += bw + gap
        }
        guard let img = c.makeImage() else { return Data() }
        return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) ?? Data()
    }

    static let html = #"""
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Пульт">
<meta name="theme-color" content="#000000">
<link rel="apple-touch-icon" href="/icon.png">
<title>Пульт · Mac</title>
<style>
@property --a { syntax:'<color>'; inherits:true; initial-value:#3ee6ff; }
@property --b { syntax:'<color>'; inherits:true; initial-value:#5b7cff; }
@property --bg { syntax:'<color>'; inherits:true; initial-value:#1b2a4a; }
:root { --a:#3ee6ff; --b:#5b7cff; --bg:#1b2a4a; --ios:cubic-bezier(.32,.72,0,1);
  transition: --a .9s ease, --b .9s ease, --bg .9s ease; }
* { box-sizing:border-box; -webkit-tap-highlight-color:transparent; -webkit-user-select:none; user-select:none; }
html,body { margin:0; height:100%; background:#000; color:#fff; overflow:hidden;
  font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display",system-ui,sans-serif; }
#bgart { position:fixed; inset:-15%; transform:translateZ(0); }
#bgart div { position:absolute; inset:0; background-size:cover; background-position:center; filter:blur(60px) saturate(1.5);
  opacity:0; transition:opacity .9s ease; }
#bgart div.on { opacity:.55; }
#tint { position:fixed; inset:0; background:linear-gradient(160deg, color-mix(in srgb, var(--bg) 85%, transparent) 0%,
  color-mix(in srgb, var(--bg) 35%, #000) 55%, #000 100%); transition:background 1s; }
main { position:relative; height:100%; display:flex; flex-direction:column; align-items:center;
  padding:calc(env(safe-area-inset-top) + 18px) 26px calc(env(safe-area-inset-bottom) + 22px); gap:0; }
.top { width:100%; display:flex; align-items:center; justify-content:space-between; font-size:12px; font-weight:700;
  letter-spacing:.12em; text-transform:uppercase; color:rgba(255,255,255,.62); }
.chip { display:flex; align-items:center; gap:7px; }
.dot { width:7px; height:7px; border-radius:50%; background:var(--a); box-shadow:0 0 10px var(--a); transition:background 1s; }
.dot.off { background:#ff5a5a; box-shadow:0 0 10px #ff5a5a; }
.cover-wrap { flex:1; width:100%; display:flex; align-items:center; justify-content:center; min-height:0; padding:22px 0; }
.cover { position:relative; width:min(100%, 46vh, 400px); aspect-ratio:1; transition:transform .5s cubic-bezier(.3,1.35,.5,1); }
.cover.paused { transform:scale(.88); }
.art { position:absolute; inset:0; border-radius:14px; background:linear-gradient(135deg,var(--a),var(--b));
  background-size:cover; background-position:center; display:flex; align-items:center; justify-content:center; font-size:64px;
  box-shadow:0 24px 60px rgba(0,0,0,.55), 0 0 80px color-mix(in srgb, var(--a) 30%, transparent);
  transition:transform .6s var(--ios), opacity .5s ease, filter .6s var(--ios); will-change:transform, opacity; }
.meta { transition:transform .38s var(--ios), opacity .3s ease; }
.meta.out { opacity:0; transform:translateY(-10px); transition:transform .18s ease-in, opacity .18s ease-in; }
.meta.in0 { opacity:0; transform:translateY(12px); transition:none; }
.play svg { transition:transform .3s cubic-bezier(.3,1.5,.5,1); }
.play.pop svg { transform:scale(.6); transition:none; }
.meta { width:100%; }
.title { font-size:22px; font-weight:800; line-height:1.2; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.artist { margin-top:4px; font-size:16px; font-weight:500; color:rgba(255,255,255,.62); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.prog { width:100%; margin-top:22px; touch-action:none; padding:10px 0; }
.track { position:relative; height:5px; border-radius:3px; background:rgba(255,255,255,.2); transition:height .15s; }
.prog.drag .track { height:9px; }
.fill { position:absolute; left:0; top:0; bottom:0; border-radius:3px; background:linear-gradient(90deg,#fff,#fff); }
.prog.drag .fill { background:linear-gradient(90deg,var(--a),var(--b)); }
.knob { position:absolute; top:50%; width:15px; height:15px; margin:-7.5px 0 0 -7.5px; border-radius:50%; background:#fff;
  box-shadow:0 2px 8px rgba(0,0,0,.5); transform:scale(0); transition:transform .15s; }
.prog.drag .knob { transform:scale(1.25); }
.times { display:flex; justify-content:space-between; margin-top:7px; font-size:12px; font-weight:600; color:rgba(255,255,255,.55);
  font-variant-numeric:tabular-nums; }
.ctrl { width:100%; display:flex; align-items:center; justify-content:space-between; margin-top:14px; }
button { border:0; background:none; color:#fff; padding:0; display:flex; align-items:center; justify-content:center; cursor:pointer;
  transition:transform .12s, opacity .12s; }
button:active { transform:scale(.88); opacity:.75; }
.sm { width:52px; height:52px; opacity:.85; }
.md { width:62px; height:62px; }
.play { width:78px; height:78px; border-radius:50%; background:linear-gradient(135deg,var(--a),var(--b)); color:#000;
  box-shadow:0 10px 30px color-mix(in srgb, var(--a) 45%, transparent); transition:background 1s, box-shadow 1s, transform .12s; }
svg { width:100%; height:100%; }
.sm svg { width:30px; height:30px; } .md svg { width:38px; height:38px; } .play svg { width:34px; height:34px; }
.vol { width:100%; display:flex; align-items:center; gap:14px; margin-top:20px; color:rgba(255,255,255,.55); }
.vol svg { width:18px; height:18px; flex:none; }
.vbar { flex:1; padding:12px 0; touch-action:none; }
.vbar .track { height:5px; } .vbar.drag .track { height:9px; }
.vbar.drag .fill { background:linear-gradient(90deg,var(--a),var(--b)); }
.lockbtn { width:34px; height:34px; border-radius:50%; background:rgba(255,255,255,.1); color:rgba(255,255,255,.7); }
.lockbtn svg { width:16px; height:16px; }
.lockbtn.on { background:linear-gradient(135deg,var(--a),var(--b)); color:#000; box-shadow:0 0 14px color-mix(in srgb, var(--a) 50%, transparent); }
.hint { position:fixed; left:50%; bottom:calc(env(safe-area-inset-bottom) + 14px); transform:translateX(-50%); padding:9px 14px;
  border-radius:20px; background:rgba(255,255,255,.12); backdrop-filter:blur(20px); -webkit-backdrop-filter:blur(20px);
  font-size:13px; color:rgba(255,255,255,.85); white-space:nowrap; opacity:0; transition:opacity .4s; pointer-events:none; }
.hint.show { opacity:1; }
.empty { position:fixed; inset:0; display:none; flex-direction:column; align-items:center; justify-content:center; gap:10px;
  color:rgba(255,255,255,.6); font-size:16px; text-align:center; padding:30px; }
.empty b { color:#fff; font-size:22px; }
body.idle main { opacity:.15; pointer-events:none; } body.idle .empty { display:flex; }
.lock { position:fixed; inset:0; display:none; align-items:center; justify-content:center; text-align:center; padding:40px;
  font-size:17px; color:rgba(255,255,255,.75); background:#000; }
body.nokey .lock { display:flex; }
/* ——— Горизонтально (телефон боком): обложка слева на всю высоту, управление справа ——— */
@media (orientation: landscape) and (max-height: 560px) {
  main { display:grid; align-items:center;
    grid-template-columns: auto minmax(0, 1fr);
    grid-template-rows: auto 1fr auto auto auto auto 1fr;
    column-gap: clamp(24px, 5vw, 48px);
    padding: calc(env(safe-area-inset-top) + 14px) calc(env(safe-area-inset-right) + 22px)
             calc(env(safe-area-inset-bottom) + 12px) calc(env(safe-area-inset-left) + 22px); }
  .cover-wrap { grid-column:1; grid-row:1 / -1; padding:0; height:100%; }
  .cover { width:auto; height:min(calc(100vh - env(safe-area-inset-top) - env(safe-area-inset-bottom) - 34px), 44vw); }
  .art { border-radius:12px; font-size:48px; box-shadow:0 18px 44px rgba(0,0,0,.55), 0 0 60px color-mix(in srgb, var(--a) 26%, transparent); }
  .top   { grid-column:2; grid-row:1; }
  .meta  { grid-column:2; grid-row:3; }
  .prog  { grid-column:2; grid-row:4; margin-top:12px; padding:8px 0; }
  .ctrl  { grid-column:2; grid-row:5; margin-top:4px; justify-content:center; gap:clamp(6px, 2.5vw, 26px); }
  .vol   { grid-column:2; grid-row:6; margin-top:6px; }
  .title { font-size:20px; }
  .artist { font-size:14px; margin-top:2px; }
  .times { margin-top:5px; font-size:11px; }
  .sm { width:44px; height:44px; } .sm svg { width:26px; height:26px; }
  .md { width:52px; height:52px; } .md svg { width:32px; height:32px; }
  .play { width:62px; height:62px; } .play svg { width:28px; height:28px; }
  .vbar { padding:9px 0; }
  .hint { bottom:calc(env(safe-area-inset-bottom) + 8px); }
}
</style>
</head>
<body class="idle">
<div id="bgart"><div class="on" id="bg0"></div></div><div id="tint"></div>
<main>
  <div class="top"><div class="chip"><span class="dot" id="dot"></span><span id="app">Mac</span></div>
    <div class="chip"><span id="state"></span><button class="lockbtn" id="lockbtn" aria-label="На экран блокировки">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg></button></div></div>
  <div class="cover-wrap"><div class="cover" id="cover"><div class="art" id="art0">♪</div></div></div>
  <div class="meta" id="meta"><div class="title" id="title">—</div><div class="artist" id="artist"></div></div>
  <div class="prog" id="prog"><div class="track"><div class="fill" id="pfill"></div><div class="knob" id="pknob"></div></div>
    <div class="times"><span id="cur">0:00</span><span id="dur">0:00</span></div></div>
  <div class="ctrl">
    <button class="sm" data-c="skip" data-d="-15" aria-label="Назад 15 секунд"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/><text x="12" y="15.5" font-size="7" font-weight="700" text-anchor="middle" fill="currentColor" stroke="none" font-family="-apple-system">15</text></svg></button>
    <button class="md" data-c="prev" aria-label="Предыдущий"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 5h2v14H6zM20 5v14L9 12z"/></svg></button>
    <button class="play" data-c="toggle" id="play" aria-label="Играть"><svg viewBox="0 0 24 24" fill="currentColor" id="picon"><path d="M7 4.5v15l13-7.5z"/></svg></button>
    <button class="md" data-c="next" aria-label="Следующий"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M16 5h2v14h-2zM4 5v14l11-7z"/></svg></button>
    <button class="sm" data-c="skip" data-d="15" aria-label="Вперёд 15 секунд"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-3-6.7"/><path d="M21 4v5h-5"/><text x="12" y="15.5" font-size="7" font-weight="700" text-anchor="middle" fill="currentColor" stroke="none" font-family="-apple-system">15</text></svg></button>
  </div>
  <div class="vol">
    <svg viewBox="0 0 24 24" fill="currentColor"><path d="M4 9h4l5-4v14l-5-4H4z"/></svg>
    <div class="vbar" id="vbar"><div class="track"><div class="fill" id="vfill"></div><div class="knob" id="vknob"></div></div></div>
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 9h4l5-4v14l-5-4H4z" fill="currentColor" stroke="none"/><path d="M16.5 8.5a5 5 0 0 1 0 7M19 6a8.5 8.5 0 0 1 0 12"/></svg>
  </div>
</main>
<div class="empty"><b>Ничего не играет</b>Включите музыку на Mac — здесь появится пульт</div>
<div class="hint" id="hint"></div>
<div class="lock">Откройте пульт по QR-коду из NotchDeck на Mac<br>(меню NotchDeck → «Пульт для iPhone…»)</div>
<script>
const $ = id => document.getElementById(id);
const qs = new URLSearchParams(location.search);
let key = qs.get('k') || localStorage.getItem('ndkey') || '';
if (qs.get('k')) localStorage.setItem('ndkey', key);
if (!key) document.body.classList.add('nokey');

let S = { playing:false, duration:0, position:0, volume:50 }, at = performance.now(), ver = 0, art = '', dragging = null;
const PLAY = '<path d="M7 4.5v15l13-7.5z"/>', PAUSE = '<path d="M6 4h4.2v16H6zM13.8 4H18v16h-4.2z"/>';
const fmt = t => { t = Math.max(0, t|0); const h = t/3600|0, m = (t%3600)/60|0, s = t%60;
  return (h ? h + ':' + String(m).padStart(2,'0') : m) + ':' + String(s).padStart(2,'0'); };
const live = () => S.playing && !dragging ? Math.min(S.duration || 1e9, S.position + (performance.now() - at) / 1000) : S.position;

function apply(s) {
  S = s; at = performance.now();
  document.body.classList.toggle('idle', !s.title && !s.app);
  $('app').textContent = s.app || 'Mac';
  const t = s.title || 'Без названия', ar = s.artist || s.album || '';
  if (t !== $('title').textContent || ar !== $('artist').textContent) swapText(t, ar);
  setPlayIcon(s.playing);
  $('cover').classList.toggle('paused', !s.playing);
  $('state').textContent = s.playing ? '' : 'Пауза';
  const r = document.documentElement.style;
  r.setProperty('--a', s.a); r.setProperty('--b', s.b); r.setProperty('--bg', s.bg);
  if (s.art !== art) { art = s.art; swapArt(art ? `/art?k=${key}&id=${art}` : ''); }
  $('prog').style.visibility = s.duration > 0 ? 'visible' : 'hidden';
  document.querySelectorAll('[data-c=skip]').forEach(b => b.style.visibility = s.duration > 0 ? 'visible' : 'hidden');
  if (dragging !== 'v') setBar('v', s.volume / 100);
  if (typeof syncSession === 'function') syncSession();
}
// ——— Плавная смена трека (как в Apple Music) ———
let dir = 0, dirAt = 0;        // направление: 1 — «вперёд», -1 — «назад», 0 — сменилось само
const curDir = () => (performance.now() - dirAt < 5000 ? dir : 0);
let artTok = 0;
function swapArt(url) {
  const tok = ++artTok, d = curDir();
  const go = () => {
    if (tok !== artTok) return;
    const box = $('cover'), old = [...box.querySelectorAll('.art')], nu = document.createElement('div');
    nu.className = 'art';
    if (url) nu.style.backgroundImage = `url("${url}")`; else nu.textContent = '♪';
    nu.style.opacity = 0;
    nu.style.transform = d ? `translateX(${d * 60}%) scale(.84) rotate(${d * 2}deg)` : 'scale(.9)';
    nu.style.filter = 'blur(6px)';
    box.appendChild(nu);
    nu.getBoundingClientRect();
    requestAnimationFrame(() => {
      nu.style.opacity = 1; nu.style.transform = 'none'; nu.style.filter = 'none';
      old.forEach(o => { o.style.opacity = 0; o.style.filter = 'blur(6px)';
        o.style.transform = d ? `translateX(${-d * 60}%) scale(.84) rotate(${-d * 2}deg)` : 'scale(1.06)';
        setTimeout(() => o.remove(), 650); });
    });
    // фон — мягкая перекрёстная смена
    const bg = $('bgart'), ob = [...bg.children], nb = document.createElement('div');
    if (url) nb.style.backgroundImage = `url("${url}")`;
    bg.appendChild(nb); nb.getBoundingClientRect();
    requestAnimationFrame(() => { nb.classList.add('on'); ob.forEach(o => { o.classList.remove('on'); setTimeout(() => o.remove(), 950); }); });
  };
  if (!url) return go();
  const img = new Image(); let done = false;
  const fire = () => { if (!done) { done = true; go(); } };
  img.onload = fire; img.onerror = fire; setTimeout(fire, 1500); img.src = url;   // ждём загрузки — без пустого мигания
}
function swapText(t, ar) {
  const m = $('meta');
  if (!$('title').textContent || $('title').textContent === '—') { $('title').textContent = t; $('artist').textContent = ar; return; }
  m.classList.add('out');
  setTimeout(() => {
    $('title').textContent = t; $('artist').textContent = ar;
    m.classList.remove('out'); m.classList.add('in0'); m.getBoundingClientRect();
    requestAnimationFrame(() => m.classList.remove('in0'));
  }, 180);
}
let iconPlaying = null;
function setPlayIcon(p) {
  if (p === iconPlaying) return;
  iconPlaying = p; $('picon').innerHTML = p ? PAUSE : PLAY;
  const b = $('play'); b.classList.add('pop'); b.getBoundingClientRect(); requestAnimationFrame(() => b.classList.remove('pop'));
}

function setBar(w, f) {
  f = Math.max(0, Math.min(1, f));
  $(w + 'fill').style.width = (f * 100) + '%'; $(w + 'knob').style.left = (f * 100) + '%';
}
function frame() {
  if (S.duration > 0) {
    const p = dragging === 'p' ? dragPos : live();
    setBar('p', p / S.duration);
    $('cur').textContent = fmt(p); $('dur').textContent = fmt(S.duration);
  }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

async function loop() {
  for (;;) {
    if (document.hidden) { await new Promise(r => document.addEventListener('visibilitychange', r, { once:true })); ver = 0; }
    try {
      const r = await fetch(`/state?k=${key}&v=${ver}`, { cache:'no-store' });
      if (r.status === 403) { document.body.classList.add('nokey'); return; }
      const s = await r.json(); ver = s.v; apply(s); $('dot').classList.remove('off');
    } catch (e) { $('dot').classList.add('off'); await new Promise(r => setTimeout(r, 2000)); }
  }
}
if (key) loop();

function cmd(a, extra = '') { fetch(`/cmd?k=${key}&a=${a}${extra}`, { cache:'no-store' }).catch(() => {}); }
document.querySelectorAll('button[data-c]').forEach(b => b.addEventListener('click', () => {
  const c = b.dataset.c;
  if (c === 'skip') { const d = +b.dataset.d; S.position = Math.max(0, Math.min(S.duration, live() + d)); at = performance.now(); cmd('skip', '&d=' + d); syncPos(); return; }
  press(c);
}));

let dragPos = 0;
function drag(el, w, onMove, onEnd) {
  const f = e => { const r = el.querySelector('.track').getBoundingClientRect(); return Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)); };
  el.addEventListener('pointerdown', e => { dragging = w; el.classList.add('drag'); el.setPointerCapture(e.pointerId); onMove(f(e)); });
  el.addEventListener('pointermove', e => { if (dragging === w) onMove(f(e)); });
  const end = e => { if (dragging !== w) return; el.classList.remove('drag'); onEnd(f(e)); dragging = null; };
  el.addEventListener('pointerup', end); el.addEventListener('pointercancel', end);
}
// ——— Экран блокировки: системный плеер iOS ———
// iOS показывает плеер на заблокированном экране только для страницы, которая проигрывает звук.
// Играем беззвучную дорожку, а в системный плеер отдаём трек, обложку и кнопки с Mac.
const ms = 'mediaSession' in navigator ? navigator.mediaSession : null;
let audio = null, lockOn = false;
function silence() {
  const rate = 8000, secs = 10, n = rate * secs, b = new ArrayBuffer(44 + n * 2), v = new DataView(b);
  const w = (o, t) => [...t].forEach((c, i) => v.setUint8(o + i, c.charCodeAt(0)));
  w(0, 'RIFF'); v.setUint32(4, 36 + n * 2, true); w(8, 'WAVEfmt '); v.setUint32(16, 16, true); v.setUint16(20, 1, true);
  v.setUint16(22, 1, true); v.setUint32(24, rate, true); v.setUint32(28, rate * 2, true); v.setUint16(32, 2, true);
  v.setUint16(34, 16, true); w(36, 'data'); v.setUint32(40, n * 2, true);
  return URL.createObjectURL(new Blob([b], { type: 'audio/wav' }));
}
function hint(t) { const h = $('hint'); h.textContent = t; h.classList.add('show'); clearTimeout(hint.t); hint.t = setTimeout(() => h.classList.remove('show'), 2600); }
function enableLock() {
  if (lockOn || !ms) return;
  audio = new Audio(silence()); audio.loop = true; audio.setAttribute('playsinline', '');
  audio.play().then(() => {
    lockOn = true; $('lockbtn').classList.add('on'); localStorage.setItem('ndlock', '1');
    syncSession(); if (!S.playing) audio.pause();
    hint('Плеер появится на экране блокировки');
  }).catch(() => hint('Нажмите ещё раз, чтобы включить'));
  const h = (a, f) => { try { ms.setActionHandler(a, f); } catch (e) {} };
  h('play', () => { audio && audio.play(); if (!S.playing) press('toggle'); });
  h('pause', () => { audio && audio.pause(); if (S.playing) press('toggle'); });
  h('nexttrack', () => press('next'));
  h('previoustrack', () => press('prev'));
  h('seekto', d => { S.position = d.seekTime; at = performance.now(); cmd('seek', '&t=' + d.seekTime.toFixed(1)); syncPos(); });
}
function disableLock() {
  lockOn = false; localStorage.removeItem('ndlock'); $('lockbtn').classList.remove('on');
  if (audio) { audio.pause(); audio.src = ''; audio = null; }
  if (ms) ms.metadata = null;
  hint('Убрано с экрана блокировки');
}
function syncPos() {
  if (!ms || !lockOn || !(S.duration > 0)) return;
  try { ms.setPositionState({ duration: S.duration, position: Math.min(S.duration, live()), playbackRate: S.playing ? 1 : 1 }); } catch (e) {}
}
let lastMeta = '';
function syncSession() {
  if (!ms || !lockOn) return;
  const key = [S.title, S.artist, S.art].join('|');
  if (key !== lastMeta) {
    lastMeta = key;
    const u = S.art ? location.origin + `/art?k=${key_}&id=${S.art}` : location.origin + '/icon.png';
    ms.metadata = new MediaMetadata({ title: S.title || 'Mac', artist: S.artist || S.app || '', album: S.app ? 'на Mac · ' + S.app : 'на Mac',
      artwork: [{ src: u, sizes: '512x512', type: 'image/jpeg' }] });
  }
  ms.playbackState = S.playing ? 'playing' : 'paused';
  // звук «идёт», пока музыка играет на Mac — так кнопка на экране блокировки показывает верное состояние
  if (audio) { if (S.playing && audio.paused) audio.play().catch(() => {}); if (!S.playing && !audio.paused) audio.pause(); }
  syncPos();
}
const key_ = key;
function press(c) {
  if (c === 'next' || c === 'prev') { dir = c === 'next' ? 1 : -1; dirAt = performance.now(); }
  if (c === 'toggle') { S.position = live(); at = performance.now(); S.playing = !S.playing; setPlayIcon(S.playing);
    $('cover').classList.toggle('paused', !S.playing); syncSession(); }
  cmd(c);
}
$('lockbtn').addEventListener('click', e => { e.stopPropagation(); lockOn ? disableLock() : enableLock(); });
// включаем сами при первом касании, если раньше уже включали (звук на iOS можно запустить только по касанию)
document.addEventListener('pointerdown', () => { if (!lockOn && localStorage.getItem('ndlock')) enableLock(); }, { capture:true });
if (!ms) $('lockbtn').style.display = 'none';
setInterval(() => { if (lockOn && S.playing) syncPos(); }, 5000);

drag($('prog'), 'p', x => { dragPos = x * S.duration; }, x => { S.position = x * S.duration; at = performance.now(); cmd('seek', '&t=' + S.position.toFixed(1)); syncPos(); });
let vt = 0;
drag($('vbar'), 'v', x => { setBar('v', x); const now = Date.now(); if (now - vt > 120) { vt = now; cmd('vol', '&v=' + Math.round(x * 100)); } },
  x => { S.volume = Math.round(x * 100); cmd('vol', '&v=' + S.volume); });
</script>
</body>
</html>
"""#
}
