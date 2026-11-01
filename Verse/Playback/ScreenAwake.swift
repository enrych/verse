import Foundation
import IOKit.pwr_mgt

/// Keeps the display on while music plays.
///
/// Unlocked: a PreventUserIdleDisplaySleep assertion keeps the display lit but
/// still lets the Mac auto-lock on its normal schedule.
/// Locked: the lock screen runs its own short screen-off timer that ignores that
/// assertion, so Verse also declares user activity every 25 s, only while locked,
/// so the constellation stays lit without ever preventing auto-lock.
final class ScreenAwake {
    private var assertionID: IOPMAssertionID = 0
    private var activityID: IOPMAssertionID = 0
    private var held = false
    private var timer: Timer?

    func set(on: Bool, locked: Bool) {
        if on, !held {
            held = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Verse is showing lyrics" as CFString,
                &assertionID
            ) == kIOReturnSuccess
        } else if !on, held {
            IOPMAssertionRelease(assertionID)
            held = false
        }

        let wantActivity = on && locked
        if wantActivity, timer == nil {
            declareActivity()
            let timer = Timer(timeInterval: 25, repeats: true) { [weak self] _ in self?.declareActivity() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !wantActivity, let timer {
            timer.invalidate()
            self.timer = nil
            if activityID != 0 { IOPMAssertionRelease(activityID); activityID = 0 }
        }
    }

    private func declareActivity() {
        IOPMAssertionDeclareUserActivity("Verse is showing lyrics" as CFString, kIOPMUserActiveLocal, &activityID)
    }

    deinit {
        timer?.invalidate()
        if held { IOPMAssertionRelease(assertionID) }
        if activityID != 0 { IOPMAssertionRelease(activityID) }
    }
}
