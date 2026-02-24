import Testing

/// Shared tag for integration tests that require real network access or hardware.
/// These tests are correct by design but may be skipped in offline CI.
/// Run selectively with: swift test --filter "integration"
extension Tag {
    @Tag static var integration: Self
}
