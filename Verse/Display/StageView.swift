import SwiftUI

/// The root view drawn on the lock-screen layer and the full-screen stage.
struct StageView: View {
    enum Surface { case lockScreen, stage }

    let surface: Surface
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var player = AppModel.shared.player

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background

                if let lyrics = model.lyrics {
                    TimelineView(.animation(minimumInterval: nil, paused: !player.isPlaying)) { context in
                        let t = model.playbackTime(at: context.date)
                        let gap = lyrics.gap(at: t)
                        ZStack {
                            if settings.lockBackground != .black {
                                AmbientSky(amount: gap.amount, time: context.date.timeIntervalSinceReferenceDate)
                            }
                            lyricsView(lyrics, time: t, gap: gap)
                                .opacity(player.isPlaying ? 1 : 0.35)
                        }
                    }
                    if !player.isPlaying, player.track != nil {
                        PausedBadge(color: model.palette.lyric)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, geo.size.height * 0.1)
                            .transition(.opacity)
                    }
                } else if surface == .stage, let track = player.track {
                    VStack(spacing: 8) {
                        Text(track.title).font(.system(size: 44, weight: .bold, design: .rounded))
                        Text(track.artist).font(.title2).opacity(0.6)
                        Text(model.status).font(.callout).opacity(0.4).padding(.top, 12)
                    }
                    .foregroundStyle(model.palette.lyric)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay {
                if surface == .lockScreen && settings.glowEnabled && (player.isPlaying || settings.glowAlways) {
                    GlowOverlay(notch: nil)
                }
            }
            .overlay(alignment: .top) {
                if surface == .lockScreen, settings.nowPlayingCard, let track = player.track {
                    NowPlayingCard(track: track, artwork: model.artwork)
                        .padding(.top, settings.lockBackground == .wallpaper ? geo.size.height * 0.24 : 92)
                        .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: model.palette)
        .animation(.easeInOut(duration: 0.4), value: player.isPlaying)
    }

    @ViewBuilder
    private func lyricsView(_ lyrics: Lyrics, time: TimeInterval, gap: LyricGap) -> some View {
        switch settings.style {
        case .constellation:
            if let layout = model.layout {
                ConstellationStyle(time: time, layout: layout, palette: model.palette, scale: settings.textScale, gap: gap)
            }
        case .focus:
            FocusStyle(time: time, lyrics: lyrics, palette: model.palette, scale: settings.textScale, gap: gap)
        }
    }

    /// Night, Black or Album art (Wallpaper falls back to Night off the lock screen).
    @ViewBuilder private var base: some View {
        switch settings.lockBackground {
        case .black: Color.black
        case .album: AlbumBackground(artwork: model.artwork)
        case .night, .wallpaper: NightBackground()
        }
    }

    @ViewBuilder private var background: some View {
        switch surface {
        case .lockScreen where settings.lockBackground != .wallpaper:
            // Our own small clock, since this covers the system one.
            ZStack(alignment: .top) {
                base
                TimelineView(.everyMinute) { context in
                    Text(context.date, style: .time)
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 36)
                }
            }
        case .lockScreen:
            // Keep the user's wallpaper; just darken it enough to read.
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        case .stage:
            base
        }
    }
}

/// Small, quiet "Paused" label.
private struct PausedBadge: View {
    let color: Color
    var body: some View {
        Label("Paused", systemImage: "pause.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color.opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.white.opacity(0.08), in: Capsule())
    }
}

/// Glass now-playing card on the lock screen: cover, title, artist, progress.
private struct NowPlayingCard: View {
    let track: Track
    let artwork: NSImage?
    @ObservedObject private var player = AppModel.shared.player

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let artwork { Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill) }
                else { Image(systemName: "music.note").font(.title2).foregroundStyle(.white.opacity(0.6)) }
            }
            .frame(width: 46, height: 46)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(track.artist).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let progress = track.duration > 0 ? min(max(player.position(at: context.date) / track.duration, 0), 1) : 0
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.18))
                            Capsule().fill(.white.opacity(0.85)).frame(width: g.size.width * progress)
                        }
                    }
                    .frame(height: 3)
                    .padding(.top, 5)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(width: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .environment(\.colorScheme, .dark)
    }
}
