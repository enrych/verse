import AppKit
import SwiftUI

/// Ambient light around the edges of a screen: a soft, slowly rotating
/// two-colour band whose brightness follows the chosen motion.
struct EdgeGlow: View {
    let palette: Palette
    let thickness: Double
    let strength: Double
    let motion: GlowMotion
    /// Current playback time and lyrics, for the Lyrics motion.
    let time: TimeInterval
    let lyrics: Lyrics?
    let isPlaying: Bool
    /// Notch rectangle in this view's coordinates (top-left origin), if any.
    let notch: CGRect?
    /// Wall-clock seconds, for rotation and breathing.
    let clock: TimeInterval

    var body: some View {
        let level = brightness
        let angle = Angle(degrees: (clock * 9).truncatingRemainder(dividingBy: 360))
        let gradient = AngularGradient(
            colors: [palette.highlight, palette.lyric, palette.highlight, palette.lyric, palette.highlight],
            center: .center, angle: angle
        )
        let spread = 6 + strength * 46
        ZStack {
            // Wide, soft spill.
            Rectangle()
                .strokeBorder(gradient, lineWidth: thickness * (1.6 + strength))
                .blur(radius: spread)
                .opacity(0.55 * level)
            // Tighter band at the very edge.
            Rectangle()
                .strokeBorder(gradient, lineWidth: thickness)
                .blur(radius: max(2, thickness * 0.6))
                .opacity(0.9 * level)
        }
        .mask(notchMask)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    /// 0…1 brightness for this frame.
    private var brightness: Double {
        let floor = 0.35 + 0.35 * strength
        switch motion {
        case .still:
            return floor + 0.3
        case .breathe:
            let s = 0.5 + 0.5 * sin(clock * 2 * .pi / 6)   // one breath every 6 s
            return floor + 0.45 * s * s
        case .lyrics:
            guard isPlaying, let lyrics else { return floor * 0.8 }
            // Each word that starts adds a quick flash that decays over ~0.6 s.
            var pulse = 0.0
            for line in lyrics.lines where line.start <= time && line.end + 1 >= time {
                for w in line.words where w.start <= time && time - w.start < 0.8 {
                    pulse = max(pulse, exp(-(time - w.start) * 5.5))
                }
            }
            return min(1, floor * 0.75 + 0.6 * pulse)
        }
    }

    /// Hides the glow where the notch is, so it frames the notch instead of washing over it.
    @ViewBuilder private var notchMask: some View {
        if let notch {
            ZStack(alignment: .topLeading) {
                Color.white
                RoundedRectangle(cornerRadius: 10)
                    .frame(width: notch.width + 20, height: notch.height + thickness * 2)
                    .offset(x: notch.minX - 10, y: -thickness)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        } else {
            Color.white
        }
    }
}

extension NSScreen {
    /// The notch's rectangle in top-left-origin screen-local points, if this screen has one.
    var notchRect: CGRect? {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        let x = left.maxX - frame.minX
        let width = right.minX - left.maxX
        guard width > 0 else { return nil }
        return CGRect(x: x, y: 0, width: width, height: safeAreaInsets.top)
    }
}

/// Click-through window above everything on one screen, used to draw the glow.
final class GlowWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }
}

/// The glow content for one screen, reading live state from the model.
struct GlowOverlay: View {
    let notch: CGRect?
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var player = AppModel.shared.player

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            EdgeGlow(
                palette: model.palette,
                thickness: settings.glowThickness,
                strength: settings.glowStrength,
                motion: settings.glowMotion,
                time: model.playbackTime(at: context.date),
                lyrics: model.lyrics,
                isPlaying: player.isPlaying,
                notch: notch,
                clock: context.date.timeIntervalSinceReferenceDate
            )
        }
        .animation(.easeInOut(duration: 0.8), value: model.palette)
    }
}
