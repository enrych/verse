import AudioToolbox
import CoreAudio
import Foundation
import os

/// Listens to the Mac's system audio output (never the microphone) and turns it
/// into two numbers the glow can use: a smoothed `level` and a `pulse` that
/// jumps on each beat and decays. Uses a Core Audio process tap (macOS 14.2+),
/// which macOS gates behind the "System Audio Recording" permission.
final class AudioBeat: @unchecked Sendable {
    static let shared = AudioBeat()

    private var lock = os_unfair_lock()
    private var _level: Float = 0
    private var _pulse: Float = 0
    private var _lastBeat: TimeInterval = 0
    private var average: Float = 0

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.enrych.verse.audiobeat", qos: .userInteractive)
    private(set) var isRunning = false
    /// Set when the tap couldn't start (unsupported macOS, or permission denied).
    private(set) var problem: String?

    /// Smoothed loudness 0…1 and a beat pulse 0…1 (decays ~0.35 s after each beat).
    func read(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> (level: Float, pulse: Float) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        let decay = Float(exp(-(now - _lastBeat) * 7))
        return (_level, max(0, _pulse * decay))
    }

    func start() {
        guard !isRunning else { return }
        guard #available(macOS 14.2, *) else { problem = "Needs macOS 14.2 or later"; return }
        do {
            try startTap()
            isRunning = true
            problem = nil
        } catch {
            problem = "Allow Verse under System Settings → Privacy & Security → Screen & System Audio Recording"
            stop()
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            if let procID { AudioDeviceDestroyIOProcID(aggregateID, procID) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if #available(macOS 14.2, *), tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        isRunning = false
        os_unfair_lock_lock(&lock); _level = 0; _pulse = 0; os_unfair_lock_unlock(&lock)
    }

    // MARK: Core Audio plumbing

    private struct TapError: Error { let step: String; let status: OSStatus }

    @available(macOS 14.2, *)
    private func startTap() throws {
        // 1. A private tap on all system output, not muting anything.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw TapError(step: "tap", status: status) }

        // 2. An aggregate device around the default output, with the tap attached.
        let outputUID = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Verse Beat",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { throw TapError(step: "aggregate", status: status) }

        // 3. Read buffers as they arrive.
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.process(input)
        }
        guard status == noErr else { throw TapError(step: "ioproc", status: status) }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw TapError(step: "start", status: status) }
    }

    private static func defaultOutputUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw TapError(step: "output device", status: status) }

        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw TapError(step: "output uid", status: status) }
        return uid.takeRetainedValue() as String
    }

    /// Energy follower + simple onset detector: a beat is energy well above the recent average.
    private func process(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        var sum: Float = 0
        var count = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let samples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let floats = data.assumingMemoryBound(to: Float.self)
            for i in 0..<samples { sum += floats[i] * floats[i] }
            count += samples
        }
        guard count > 0 else { return }
        let rms = (sum / Float(count)).squareRoot()
        let energy = min(1, rms * 4)

        let now = ProcessInfo.processInfo.systemUptime
        os_unfair_lock_lock(&lock)
        average = average * 0.96 + energy * 0.04
        _level = _level * 0.8 + energy * 0.2
        if energy > max(0.04, average * 1.45), now - _lastBeat > 0.18 {
            _pulse = min(1, 0.5 + (energy - average) * 3)
            _lastBeat = now
        }
        os_unfair_lock_unlock(&lock)
    }
}
