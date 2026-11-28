import Foundation

/// The no-hint settle windows of `NetworkIdentityController` (#645 rounds 5 and 7).
extension NetworkIdentityController {
    /// Notes a read: "no IPv6 router" read without a break since the generation's first such read.
    /// Settled once that's lasted `noHintSettleWindow`; `remaining` until then.
    func noteAbsence(_ hint: RouterHintStatus) -> (isAbsent: Bool, settled: Bool, remaining: TimeInterval) {
        guard hint == .absent else {
            absentSince = nil
            return (false, false, 0)
        }
        let generation = clock.generation.value
        if absentSince?.generation != generation {
            absentSince = (generation, now())
        }
        let elapsed = now().timeIntervalSince(absentSince?.at ?? now())
        return (true, elapsed >= Self.noHintSettleWindow, max(0, Self.noHintSettleWindow - elapsed))
    }

    /// Failed reads counting as no hint: settled once that's lasted the window in this generation.
    func noteConvertedAbsence() -> (settled: Bool, remaining: TimeInterval) {
        let generation = clock.generation.value
        if failedAbsentSince?.generation != generation {
            failedAbsentSince = (generation, now())
        }
        let elapsed = now().timeIntervalSince(failedAbsentSince?.at ?? now())
        return (elapsed >= Self.noHintSettleWindow, max(0, Self.noHintSettleWindow - elapsed))
    }
}
