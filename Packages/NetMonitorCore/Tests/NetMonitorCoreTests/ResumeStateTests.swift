import Testing
@testable import NetMonitorCore

@Suite("ResumeState")
struct ResumeStateTests {

    @Test("hasResumed starts as false")
    func initialState() async {
        let state = ResumeState()
        let hasResumed = await state.hasResumed
        #expect(hasResumed == false)
    }

    @Test("setResumed marks hasResumed true")
    func setResumed() async {
        let state = ResumeState()
        await state.setResumed()
        let hasResumed = await state.hasResumed
        #expect(hasResumed == true)
    }

    @Test("tryResume returns true on first call and sets hasResumed")
    func tryResumeFirstCall() async {
        let state = ResumeState()
        let result = await state.tryResume()
        #expect(result == true)
        let hasResumed = await state.hasResumed
        #expect(hasResumed == true)
    }

    @Test("tryResume returns false on second call")
    func tryResumeSecondCall() async {
        let state = ResumeState()
        let first = await state.tryResume()
        let second = await state.tryResume()
        #expect(first == true)
        #expect(second == false)
    }

    @Test("tryResume returns false on all calls after first")
    func tryResumeMultipleCalls() async {
        let state = ResumeState()
        _ = await state.tryResume()
        for _ in 0..<5 {
            let result = await state.tryResume()
            #expect(result == false)
        }
    }

    @Test("setResumed after tryResume leaves state resumed")
    func setResumedAfterTryResume() async {
        let state = ResumeState()
        _ = await state.tryResume()
        await state.setResumed()  // idempotent
        let hasResumed = await state.hasResumed
        #expect(hasResumed == true)
    }

    @Test("tryResume after setResumed returns false")
    func tryResumeAfterSetResumed() async {
        let state = ResumeState()
        await state.setResumed()
        let result = await state.tryResume()
        #expect(result == false)
    }
}
