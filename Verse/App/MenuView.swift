import SwiftUI

struct MenuView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var player = AppModel.shared.player
    @ObservedObject private var updates = AppModel.shared.updates
    @ObservedObject private var login = AppModel.shared.launchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let version = updates.available { updateBanner(version) }
            header
            Divider()

            Picker("Style", selection: $settings.style) {
                ForEach(LyricStyle.allCases) { Text($0.title).tag($0) }
            }
            Picker("Background", selection: $settings.lockBackground) {
                ForEach(LockBackground.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Show on lock screen", isOn: $settings.lockScreenEnabled)
            VStack(alignment: .leading, spacing: 4) {
                Picker("Full-screen stage", selection: $settings.stageDisplayID) {
                    Text("Off").tag(CGDirectDisplayID?.none)
                    ForEach(NSScreen.screens, id: \.displayID) { screen in
                        Text(screen.localizedName).tag(CGDirectDisplayID?.some(screen.displayID))
                    }
                }
                Text("⌃⌥⌘L toggles it on the display under the pointer.")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Divider()

            Picker("Colours", selection: $settings.colourSource) {
                ForEach(ColourSource.allCases) { Text($0.title).tag($0) }
            }
            if settings.colourSource == .custom {
                ColorPicker("Lyrics", selection: $settings.lyricColor)
                ColorPicker("Current word", selection: $settings.highlightColor)
            }
            LabeledContent("Text size") {
                Slider(value: $settings.textScale, in: 0.6...1.8)
            }

            Divider()

            LabeledContent("Sync, all songs") {
                Stepper("\(Int(settings.syncOffsetMs)) ms", value: $settings.syncOffsetMs, in: -2000...2000, step: 50)
            }
            if player.track != nil {
                LabeledContent("Sync, this song") {
                    Stepper(songOffsetLabel, value: songOffset, in: -3000...3000, step: 100)
                }
            }

            Divider()

            Toggle("Keep display awake while playing", isOn: $settings.keepAwake)
            Toggle("Open at login", isOn: Binding(get: { login.enabled }, set: { login.set($0) }))
            if let error = login.error {
                Text(error).font(.caption).foregroundStyle(.orange)
            }

            Divider()

            HStack {
                Text("Verse \(updates.current)").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit Verse") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 330)
    }

    private var songOffset: Binding<Double> {
        Binding(get: { model.songOffsetMs }, set: { model.songOffsetMs = $0 })
    }

    private var songOffsetLabel: String {
        let ms = Int(model.songOffsetMs)
        return ms == 0 ? "0 ms" : String(format: "%+d ms", ms)
    }

    private func updateBanner(_ version: String) -> some View {
        Button { updates.openDownload() } label: {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                Text("Verse \(version) is available")
                Spacer()
                Text("Download").fontWeight(.semibold)
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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
