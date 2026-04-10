import Testing
@testable import NetworkScanKit

struct ResumeStateTests {

    @Test("starts with hasResumed false")
    func initialState() async {
        let state = ResumeState()
        #expect(await state.hasResumed == false)
    }

    @Test("setResumed marks hasResumed true")
    func setResumedWorks() async {
        let state = ResumeState()
        await state.setResumed()
        #expect(await state.hasResumed == true)
    }

    @Test("tryResume returns true on first call")
    func tryResumeFirstCall() async {
        let state = ResumeState()
        let result = await state.tryResume()
        #expect(result == true)
        #expect(await state.hasResumed == true)
    }

    @Test("tryResume returns false on second call")
    func tryResumeSecondCall() async {
        let state = ResumeState()
        let first = await state.tryResume()
        let second = await state.tryResume()
        #expect(first == true)
        #expect(second == false)
    }

    @Test("tryResume returns false after setResumed")
    func tryResumeAfterSetResumed() async {
        let state = ResumeState()
        await state.setResumed()
        let result = await state.tryResume()
        #expect(result == false)
    }

    @Test("multiple tryResume calls all return false after first")
    func multipleCallsAfterFirst() async {
        let state = ResumeState()
        _ = await state.tryResume()
        for _ in 0..<5 {
            let result = await state.tryResume()
            #expect(result == false)
        }
    }
}
