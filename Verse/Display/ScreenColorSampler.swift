import AppKit
import CoreMedia
import ScreenCaptureKit
import SwiftUI

/// Follows what's on screen: samples a tiny (64×40) image of one display a few
/// times a second and turns it into two glow colours (left and right halves).
/// Verse's own windows are excluded so the glow doesn't feed back on itself.
/// Needs the Screen Recording permission.
@MainActor
final class ScreenColorSampler: NSObject, ObservableObject {
    static let shared = ScreenColorSampler()

    /// Primary (left) and secondary (right) colours, smoothed; nil until the first frame.
    @Published private(set) var palette: Palette?
    @Published private(set) var problem: String?

    private var stream: SCStream?
    private var displayID: CGDirectDisplayID?
    private let queue = DispatchQueue(label: "com.enrych.verse.screencolors", qos: .utility)
    private var smoothed: (NSColor, NSColor)?

    func start(displayID: CGDirectDisplayID?) {
        guard stream == nil || self.displayID != displayID else { return }
        stop()
        self.displayID = displayID
        Task { await begin(displayID: displayID) }
    }

    func stop() {
        let old = stream
        stream = nil
        palette = nil
        smoothed = nil
        Task { try? await old?.stopCapture() }
    }

    private func begin(displayID: CGDirectDisplayID?) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let target = displayID ?? CGMainDisplayID()
            guard let display = content.displays.first(where: { $0.displayID == target }) ?? content.displays.first else { return }
            let mine = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = 64
            config.height = 40
            config.minimumFrameInterval = CMTime(value: 1, timescale: 4)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false
            config.queueDepth = 3
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            self.stream = stream
            problem = nil
        } catch {
            problem = "Allow Verse under System Settings → Privacy & Security → Screen & System Audio Recording"
        }
    }

    fileprivate func receive(_ left: NSColor, _ right: NSColor) {
        // Ease toward the new colours so the glow drifts rather than flickers.
        let t: CGFloat = 0.25
        let next: (NSColor, NSColor) = smoothed.map {
            ($0.0.blended(withFraction: t, of: left) ?? left, $0.1.blended(withFraction: t, of: right) ?? right)
        } ?? (left, right)
        smoothed = next
        palette = Palette(lyric: Color(nsColor: next.1), highlight: Color(nsColor: next.0),
                          secondary: Color(nsColor: next.1).opacity(0.4), background: .black)
    }
}

extension ScreenColorSampler: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
        let bytes = base.assumingMemoryBound(to: UInt8.self)

        // Saturation-weighted average per half, so vivid areas win over grey UI.
        var acc = [(r: 0.0, g: 0.0, b: 0.0, w: 0.0), (r: 0.0, g: 0.0, b: 0.0, w: 0.0)]
        for y in 0..<height {
            for x in 0..<width {
                let p = bytes + y * rowBytes + x * 4
                let b = Double(p[0]) / 255, g = Double(p[1]) / 255, r = Double(p[2]) / 255
                let maxC = max(r, g, b), minC = min(r, g, b)
                let weight = 0.05 + (maxC - minC) * 2 + maxC * 0.3
                let side = x < width / 2 ? 0 : 1
                acc[side].r += r * weight; acc[side].g += g * weight; acc[side].b += b * weight; acc[side].w += weight
            }
        }
        func colour(_ a: (r: Double, g: Double, b: Double, w: Double)) -> NSColor {
            let base = NSColor(srgbRed: a.r / a.w, green: a.g / a.w, blue: a.b / a.w, alpha: 1)
            // Lift so dark screens still give a visible glow.
            return NSColor(hue: base.hueComponent,
                           saturation: min(1, base.saturationComponent * 1.3),
                           brightness: max(0.75, base.brightnessComponent), alpha: 1)
        }
        let left = colour(acc[0]), right = colour(acc[1])
        Task { @MainActor in ScreenColorSampler.shared.receive(left, right) }
    }
}
