# Verse

**Your Lyrics, Your Way.**

The song you're playing, word by word, on your Mac's lock screen or any display.
Free and open source.

Lock screen lyrics · Spotify and Apple Music · macOS 14+ · Apple silicon and Intel

**[Download the latest release](https://verse-6gy.pages.dev/download)**

## Install

1. Open `Verse.dmg` and drag Verse into Applications.
2. Verse is ad-hoc signed but not notarised, so the first time **right-click → Open**
   (or run `xattr -dr com.apple.quarantine /Applications/Verse.app`).
3. Play something in Spotify or Apple Music, allow Verse to read it when macOS
   asks, then lock your Mac, or pick a display for the full-screen stage.

## Build from source

```bash
./scripts/setup.sh
open Verse.xcodeproj
```

Run the `Verse` scheme (⌘R). `setup.sh` installs XcodeGen, generates the project
from `project.yml`, and enables git hooks that regenerate it after `git pull` or
a branch switch. Edit `project.yml`, not the `.xcodeproj`.

## Releasing

GitHub Actions builds a universal, ad-hoc signed `Verse.dmg` and publishes it as a
release. Either run **Actions → Release → Run workflow** with a version (e.g.
`0.2.0`), or push a tag:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

Leave the version empty to build a test DMG without publishing (it's attached to
the run). The site's download links always point at the latest release.

## Website

`site/` is a static homepage (no build step), deployed on Cloudflare Pages with
output directory `site`. `functions/download.js` serves `/download`: the latest
release's DMG, fetched from GitHub once per version and then served from
Cloudflare (Workers KV binding `DOWNLOADS`).

## How it works

```
Verse/
  App/        Menu bar app, AppModel (wires everything), menu UI
  Playback/   AppleScript polling of Spotify/Music, smooth playback clock,
              lock state, keep-display-awake
  Lyrics/     Model, YRC/LRC parsers, providers, disk cache
  Display/    Lock-screen layer, full-screen stage window, root StageView
  Styles/     Display styles (v0.1: ConstellationStyle)
  Support/    Settings, palettes, album-art colour extraction
```

- **Now playing:** polls the player every 0.5 s via AppleScript and interpolates
  between samples so stars land on the beat.
- **Lyrics:** NetEase Cloud Music first (per-word timings), then LRCLIB (line
  timings; words are estimated). Cached in `~/Library/Caches/com.enrych.verse`.
- **Styles:** v0.1 ships Constellation: words gather into verse-sized groups placed
  as points in a wide band, joined in sung order; each group clears before the next.
- **Lock screen:** [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow)
  (MIT, © Lakr Aream) places a window in a private SkyLight space above the lock
  screen.

## Caveats

- The NetEase API is unofficial and may change or be rate-limited.
- The lock-screen layer uses private macOS APIs; a macOS update can break it.
  The full-screen stage keeps working either way.

## Inspiration

I saw a reel of [Verci](https://www.verci.xyz), lyrics drifting across a Mac's
lock screen, and loved it. It was paid, and I'm a developer, so I made my own,
from scratch. If you want the polished version, buy Verci. It's lovely.

## License

MIT. See [LICENSE](LICENSE).
