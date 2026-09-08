import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Application motion policy")
struct AppMotionTests {
    @Test("Equalizer resumes from its paused phase after scene deactivation")
    func equalizerPauseContinuity() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var clock = EqualizerAnimationClock()
        clock.setRunning(true, at: start)
        clock.setRunning(false, at: start.addingTimeInterval(2))
        #expect(clock.elapsed(at: start.addingTimeInterval(100)) == 2)
        clock.setRunning(false, at: start.addingTimeInterval(100))
        clock.setRunning(true, at: start.addingTimeInterval(102))
        #expect(clock.elapsed(at: start.addingTimeInterval(102)) == 2)
        clock.setRunning(true, at: start.addingTimeInterval(103))
        #expect(clock.elapsed(at: start.addingTimeInterval(105)) == 5)
        clock.setRunning(false, at: start.addingTimeInterval(105))
        #expect(clock.elapsed(at: start.addingTimeInterval(200)) == 5)
    }

    @Test("Reduce Motion follows the system setting only when enabled in-app")
    func reducedMotionPreference() {
        #expect(AppMotion.reduceMotion(systemReduceMotion: true, respectPreference: true))
        #expect(!AppMotion.reduceMotion(systemReduceMotion: true, respectPreference: false))
        #expect(!AppMotion.reduceMotion(systemReduceMotion: false, respectPreference: true))
    }

    @Test("Decorative effects pause for accessibility or Low Power Mode")
    func decorativeEffectsPolicy() {
        #expect(AppMotion.reduceDecorativeEffects(reduceMotion: true, lowPowerModeEnabled: false))
        #expect(AppMotion.reduceDecorativeEffects(reduceMotion: false, lowPowerModeEnabled: true))
        #expect(!AppMotion.reduceDecorativeEffects(reduceMotion: false, lowPowerModeEnabled: false))
    }
}
