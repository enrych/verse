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

                if let layout = model.layout {
                    TimelineView(.animation(minimumInterval: nil, paused: !player.isPlaying)) { context in
                        ConstellationStyle(
                            time: model.playbackTime(at: context.date),
                            layout: layout,
                            palette: model.palette,
                            scale: settings.textScale
                        )
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
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: model.palette)
    }

    /// Night (textured) or plain black.
    @ViewBuilder private var base: some View {
        if settings.lockBackground == .black { Color.black } else { NightBackground() }
    }

    @ViewBuilder private var background: some View {
        switch surface {
        case .lockScreen where settings.lockBackground != .wallpaper:
            // Night or black, with our own small clock since it covers the system one.
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
        case .stage where settings.starlight:
            base
        case .stage:
            ZStack {
                model.palette.background
                if let art = model.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 80)
                        .opacity(0.45)
                        .clipped()
                }
            }
        }
    }
}
