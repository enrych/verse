import SwiftUI

struct MenuView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var player = AppModel.shared.player

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()

            Toggle("Show on lock screen", isOn: $settings.lockScreenEnabled)
            Picker("Background", selection: $settings.lockBackground) {
                ForEach(LockBackground.allCases) { Text($0.title).tag($0) }
            }

            Picker("Full-screen stage", selection: $settings.stageDisplayID) {
                Text("Off").tag(CGDirectDisplayID?.none)
                ForEach(NSScreen.screens, id: \.displayID) { screen in
                    Text(screen.localizedName).tag(CGDirectDisplayID?.some(screen.displayID))
                }
            }

            Divider()

            Toggle("Starlight colours", isOn: $settings.starlight)
            if !settings.starlight {
                Toggle("Colours from album art", isOn: $settings.autoColors)
                if !settings.autoColors {
                    ColorPicker("Stars and lines", selection: $settings.lyricColor)
                    ColorPicker("Current word", selection: $settings.highlightColor)
                }
            }

            LabeledContent("Text size") {
                Slider(value: $settings.textScale, in: 0.6...1.8)
            }
            LabeledContent("Sync offset") {
                Stepper("\(Int(settings.syncOffsetMs)) ms", value: $settings.syncOffsetMs, in: -2000...2000, step: 50)
            }
            Toggle("Keep display awake while playing", isOn: $settings.keepAwake)

            Divider()

            HStack {
                Spacer()
                Button("Quit Verse") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 10) {
            Group {
                if let art = model.artwork {
                    Image(nsImage: art).resizable()
                } else {
                    Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(player.track?.title ?? "Nothing playing").font(.headline).lineLimit(1)
                if let track = player.track {
                    Text("\(track.artist) · \(track.player.displayName)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(model.status).font(.caption).foregroundStyle(.tertiary)
            }
        }
        if let denied = player.permissionDenied {
            Text("Allow Verse to control \(denied.displayName) in System Settings → Privacy & Security → Automation.")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
