// Verse homepage renderer. Same layout maths as the app's ConstellationStyle.swift.
// window.VERSE.load(lyrics) swaps the song; window.VERSE.setClock(fn) lets an
// external player (YouTube) drive time. Without a clock it loops on its own.
(() => {
  const smooth = x => { const u = Math.min(Math.max(x, 0), 1); return u * u * (3 - 2 * u); };
  const lcg = s => () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
  const SANS = '"Inter Tight", -apple-system, "Helvetica Neue", sans-serif';
  let L = null, STARS = [], DURATION = 1, clock = null;

  function layout(lyrics) {
    const rand = lcg(11), groups = [];
    let g = [];
    for (const line of lyrics.lines) {
      if (!line.words.length) { if (g.length) groups.push(g); g = []; continue; }
      if (g.length && g.length + line.words.length > 12) { groups.push(g); g = []; }
      for (const w of line.words) g.push({ w });
    }
    if (g.length) groups.push(g);
    const out = [];
    groups.forEach((group, gi) => {
      group.forEach((n, k) => {
        let best = null, score = -Infinity;
        for (let j = 0; j < 24; j++) {
          const c = { x: 0.04 + rand() * 0.92, y: 0.06 + rand() * 0.88 };
          const crowd = Math.min(1, ...group.slice(0, k).map(m => Math.hypot((m.x - c.x) * 2.2, m.y - c.y)));
          const p = group[k - 1], reach = p ? Math.hypot((p.x - c.x) * 3, p.y - c.y) : 1;
          const s = Math.min(crowd, 0.5) - Math.abs(reach - 0.9) * 0.25 + rand() * 0.05;
          if (s > score) { score = s; best = c; }
        }
        Object.assign(n, best, { k, group });
        if (k) {
          const p = group[k - 1].w.start;
          n.segEnd = n.w.start; n.segStart = Math.max(p + (n.w.start - p) * 0.3, n.w.start - 0.9);
        }
        out.push(n);
      });
      const next = groups[gi + 1];
      const end = group.at(-1).w.end;
      // Clear before the next verse, or a few seconds after the last word if there's a long gap.
      group.forEach(n => { n.clearAt = next ? Math.min(next[0].w.start - 0.35, end + 6) : end + 4; });
    });
    return out;
  }

  function sparkle(c, x, y, r) {
    const k = r * 0.16;
    c.beginPath(); c.moveTo(x, y - r);
    c.quadraticCurveTo(x + k, y - k, x + r, y); c.quadraticCurveTo(x + k, y + k, x, y + r);
    c.quadraticCurveTo(x - k, y + k, x - r, y); c.quadraticCurveTo(x - k, y - k, x, y - r);
    c.fill();
  }

  function constellation(c, W, H, t, pal, o = {}) {
    const unit = Math.min(W, H) * (o.scale ?? 1);
    const band = { x: W * (o.bx ?? 0.12), y: H * (o.by ?? 0.3), w: W * (o.bw ?? 0.76), h: H * (o.bh ?? 0.42) };
    const P = n => [band.x + n.x * band.w, band.y + n.y * band.h];
    const ga = n => t < n.clearAt ? 1 : Math.max(0, 1 - (t - n.clearAt) / 0.35);
    c.lineCap = "round";
    for (const n of STARS) {
      if (!n.k || t < n.segStart || ga(n) <= 0) continue;
      const [ax, ay] = P(n.group[n.k - 1]), [bx, by] = P(n);
      const e = smooth((t - n.segStart) / Math.max(n.segEnd - n.segStart, 0.001));
      c.globalAlpha = ga(n) * 0.7; c.strokeStyle = pal.ink; c.lineWidth = Math.max(1, unit * 0.0022);
      c.beginPath(); c.moveTo(ax, ay); c.lineTo(ax + (bx - ax) * e, ay + (by - ay) * e); c.stroke();
    }
    for (const n of STARS) {
      if (t < n.w.start || ga(n) <= 0) continue;
      const [x, y] = P(n), pop = smooth((t - n.w.start) / 0.25);
      const settle = t < n.w.end ? 1 : smooth(1 - (t - n.w.end) / 1.5);
      const r = unit * (0.009 + 0.013 * settle) * (0.4 + 0.6 * pop);
      c.globalAlpha = ga(n);
      c.fillStyle = settle > 0.05 ? pal.glow : pal.ink;
      c.shadowColor = pal.glow; c.shadowBlur = settle > 0.05 ? r * 1.6 * settle : 0;
      sparkle(c, x, y, r); c.shadowBlur = 0;
      const small = unit * 0.024, big = unit * 0.058, size = small + (big - small) * settle * pop;
      c.font = `${settle > 0.5 ? 800 : 600} ${size}px ${SANS}`;
      c.textAlign = "center"; c.textBaseline = "top";
      c.globalAlpha = ga(n) * (0.7 + 0.3 * settle);
      c.fillText(n.w.text.trim(), x, y + unit * 0.014 + r * 0.4);
    }
    c.globalAlpha = 1;
  }

  // ---------- Runtime ----------
  const PAL = { ink: "#eadcb4", glow: "#fff2cc" };
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const views = [...document.querySelectorAll("canvas[data-style]")].map(el => ({
    el, ctx: el.getContext("2d"), offset: parseFloat(el.dataset.offset || "0"),
    scale: parseFloat(el.dataset.scale || "1"), opts: JSON.parse(el.dataset.opts || "{}"), visible: true,
  }));
  const io = new IntersectionObserver(es => es.forEach(e => {
    const v = views.find(v => v.el === e.target); if (v) v.visible = e.isIntersecting;
  }));
  views.forEach(v => io.observe(v.el));

  let t0 = performance.now();
  const internal = () => {
    const v = views[0], e = (performance.now() - t0) / 1000;
    return reduce ? (v?.offset ?? 0) : ((v?.offset ?? 0) + e) % DURATION;
  };
  window.VERSE = {
    get duration() { return DURATION; },
    time: () => (clock ? clock() : internal()),
    internalTime: internal,
    setClock(fn) { clock = fn; },
    load(lyrics, startAt = 0) {
      L = lyrics; STARS = layout(lyrics); DURATION = lyrics.lines.at(-1).end + 2.5;
      t0 = performance.now() - startAt * 1000; if (views[0]) views[0].offset = 0;
    },
  };

  function frame() {
    if (L) {
      const t = window.VERSE.time();
      for (const v of views) {
        if (!v.visible) continue;
        const dpr = Math.min(devicePixelRatio || 1, 2), W = v.el.clientWidth * dpr, H = v.el.clientHeight * dpr;
        if (v.el.width !== W || v.el.height !== H) { v.el.width = W; v.el.height = H; }
        v.ctx.clearRect(0, 0, W, H);
        constellation(v.ctx, W, H, t, PAL, { ...v.opts, scale: v.scale });
      }
    }
    if (!reduce || !L) requestAnimationFrame(frame);
  }
  if (window.VERSE_DEMO) window.VERSE.load(window.VERSE_DEMO);
  document.fonts.ready.then(() => requestAnimationFrame(frame));
})();
