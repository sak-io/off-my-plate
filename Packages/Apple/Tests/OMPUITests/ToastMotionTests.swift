import Testing

@testable import OMPUI

@Suite("Toast motion and Reduce Motion (AC-15.4)")
struct ToastMotionTests {
    @Test("Reduce Motion on: the toast only fades and nothing is animated")
    func reduceMotionFadesWithoutAnimation() {
        let motion = ToastMotion(reduceMotion: true)
        #expect(motion == .fadeOnly)
        #expect(motion.animation == nil)
    }

    @Test("Reduce Motion off: the toast slides in and is animated")
    func normalMotionSlides() {
        let motion = ToastMotion(reduceMotion: false)
        #expect(motion == .slideAndFade)
        #expect(motion.animation != nil)
    }
}
