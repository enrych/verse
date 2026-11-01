// The hero's songs: short excerpts of official YouTube uploads, rotating like a
// radio preview. Lyrics are fetched live from LRCLIB; nothing copyrighted is
// stored in this repo. Without YouTube or LRCLIB, the bundled public-domain demo runs.
(() => {
  const PLAYLIST = [
    { title: "Stargazing",       artist: "Myles Smith",  video: "-JsIT9hRi-A" },
    { title: "Too Sweet",        artist: "Hozier",       video: "mfha0a8IXKs" },
    { title: "Beautiful Things", artist: "Benson Boone", video: "HU08BcK5SUY" },
    { title: "Stick Season",     artist: "Noah Kahan",   video: "iWG6apzIWAk" },
    { title: "Lose Control",     artist: "Teddy Swims",  video: "FkOpwodhROI" },
  ];
  const EXCERPT = 35;          // seconds of each song, starting just before the first line
  const $ = s => document.querySelector(s);
  const btn = $("[data-sound]"), bar = $("[data-progress]");

  // --- Lyrics: LRC lines → words with estimated timings (same rule as the app). ---
  const stamp = s => { const [m, sec] = s.split(":"); return +m * 60 + +sec; };
  const tokenize = text => {
    const out = []; let cur = "";
    for (const ch of text.trim()) {
      if (ch === " ") cur += ch; else if (cur.endsWith(" ")) { out.push(cur); cur = ch; } else cur += ch;
    }
    if (cur) out.push(cur); return out;
  };
  function parseLRC(src) {
    const entries = [];
    for (const raw of src.split(/\r?\n/)) {
      let rest = raw; const times = [];
      for (let m; (m = rest.match(/^\[(\d+:\d+(?:\.\d+)?)\]/)); rest = rest.slice(m[0].length)) times.push(stamp(m[1]));
      for (const t of times) entries.push({ t, text: rest.trim() });
    }
    entries.sort((a, b) => a.t - b.t);
    return entries.map((e, i) => {
      const next = entries[i + 1]?.t ?? e.t + 6, toks = tokenize(e.text);
      if (!toks.length) return { start: e.t, end: e.t, words: [] };
      const letters = toks.reduce((a, w) => a + Math.max(w.trim().length, 1), 0);
      const span = Math.min((next - e.t) * 0.92, letters * 0.11 + 0.6);
      let t = e.t;
      const words = toks.map(w => { const d = span * Math.max(w.trim().length, 1) / letters; const o = { text: w, start: t, end: t + d }; t += d; return o; });
      return { start: e.t, end: t, words };
    });
  }
  async function fetchLyrics(song) {
    const q = new URLSearchParams({ track_name: song.title, artist_name: song.artist });
    let rec = await fetch("https://lrclib.net/api/get?" + q).then(r => (r.ok ? r.json() : null)).catch(() => null);
    if (!rec?.syncedLyrics) {
      const list = await fetch("https://lrclib.net/api/search?" + q).then(r => (r.ok ? r.json() : [])).catch(() => []);
      rec = list.find(x => x.syncedLyrics);
    }
    if (!rec?.syncedLyrics) return null;
    const all = parseLRC(rec.syncedLyrics);
    const first = all.find(l => l.words.length);
    if (!first) return null;
    const start = Math.max(0, first.start - 1.5);
    // Keep whole lines that fall inside the excerpt.
    const lines = all.filter(l => l.start >= start && l.end <= start + EXCERPT);
    const end = Math.min(start + EXCERPT, (lines.at(-1)?.end ?? start + EXCERPT) + 1.2);
    return { song, start, end, lyrics: { lines } };
  }

  // --- Clock: YouTube's position when it's playing, otherwise our own. ---
  let player = null, ready = false, sound = false, current = null, index = -1, anchor = null, local = null;
  const ytPlaying = () => ready && player.getPlayerState && player.getPlayerState() === 1;
  function clock() {
    const now = performance.now();
    if (ytPlaying()) {
      const yt = player.getCurrentTime(), pred = anchor ? anchor.pos + (now - anchor.at) / 1000 : yt;
      if (!anchor || Math.abs(pred - yt) > 0.3) anchor = { pos: yt, at: now };
      return anchor.pos + (now - anchor.at) / 1000;
    }
    anchor = null;
    if (!local) local = { pos: current?.start ?? 0, at: now };
    return local.pos + (now - local.at) / 1000;
  }

  const queue = new Map();                        // index → Promise<excerpt|null>
  const prefetch = i => { if (!queue.has(i)) queue.set(i, fetchLyrics(PLAYLIST[i])); return queue.get(i); };

  async function playNext() {
    for (let tries = 0; tries < PLAYLIST.length; tries++) {
      index = (index + 1) % PLAYLIST.length;
      const ex = await prefetch(index);
      if (!ex) continue;
      current = ex; local = null; anchor = null;
      window.VERSE.load(ex.lyrics);
      window.VERSE.setClock(clock);
      $("[data-title]").textContent = ex.song.title;
      $("[data-artist]").textContent = ex.song.artist;
      $(".np .art").style.background = `center / cover url(https://i.ytimg.com/vi/${ex.song.video}/hqdefault.jpg)`;
      btn.hidden = false;
      if (ready) player.loadVideoById({ videoId: ex.song.video, startSeconds: ex.start });
      prefetch((index + 1) % PLAYLIST.length);
      return true;
    }
    return false;                                 // nothing available: keep the demo
  }

  function setSound(on) {
    sound = on;
    btn.setAttribute("aria-pressed", String(on));
    btn.setAttribute("aria-label", on ? "Mute" : "Play with sound");
    if (!ready) return;
    if (on) { player.unMute(); player.setVolume(80); player.playVideo(); } else player.mute();
  }

  async function start() {
    if (!(await playNext())) return;
    window.onYouTubeIframeAPIReady = () => {
      player = new YT.Player("yt", {
        width: 200, height: 113, videoId: current.song.video,
        playerVars: { autoplay: 1, mute: 1, controls: 0, playsinline: 1, disablekb: 1, rel: 0, start: Math.floor(current.start) },
        events: {
          onReady: () => {
            ready = true; player.mute();
            player.seekTo(clock(), true); player.playVideo();
            if (sound) setSound(true);
          },
          onStateChange: e => { if (e.data === 0) playNext(); },
        },
      });
    };
    const s = document.createElement("script"); s.src = "https://www.youtube.com/iframe_api"; document.head.appendChild(s);

    // Browsers only allow sound after a user gesture: the first tap or key on the page turns it on.
    const firstGesture = e => {
      if (e.target.closest && e.target.closest("a, [data-sound]")) return;
      window.removeEventListener("pointerdown", firstGesture); window.removeEventListener("keydown", firstGesture);
      if (!sound) setSound(true);
    };
    window.addEventListener("pointerdown", firstGesture); window.addEventListener("keydown", firstGesture);
  }

  btn.addEventListener("click", () => setSound(!sound));

  const loop = () => {
    if (current) {
      const t = clock();
      if (t >= current.end) playNext();
      else if (bar) bar.style.width = (100 * Math.max(0, t - current.start) / (current.end - current.start)).toFixed(2) + "%";
    }
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
  start();
})();
