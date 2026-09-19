import Foundation

/// Runs `operation` over `items` with at most `limit` tasks in flight at once,
/// calling `onResult` for each result as it completes.
///
/// This is the single bounded-concurrency shape shared by the scan phases
/// (sliding window: fill up to `limit`, consume a completion, refill).
/// Replaces the hand-rolled `withTaskGroup` + iterator + `pending` count that
/// was duplicated across phases.
///
/// - Parameters:
///   - items: The work items to process. Consumed via `makeIterator()`, so
///     the sequence itself need not be `Sendable` — only its elements do,
///     since they cross into concurrently-executing child tasks.
///   - limit: Maximum number of `operation` calls in flight at once.
///   - operation: Runs on a child task for each item; may run concurrently
///     with other calls, so it must be `@Sendable`.
///   - onResult: Called on the caller's task for each completed result, one
///     at a time (never concurrently), so it may safely mutate local state
///     the caller captures (progress counters, accumulator writes, etc.).
public func forEachBounded<Item: Sendable, Result: Sendable>(
    _ items: some Sequence<Item>,
    limit: Int,
    operation: @escaping @Sendable (Item) async -> Result,
    onResult: (Result) async -> Void
) async {
    guard limit > 0 else { return }
    var iterator = items.makeIterator()

    await withTaskGroup(of: Result.self) { group in
        var scheduled = 0

        while scheduled < limit, let item = iterator.next() {
            guard !Task.isCancelled else { break }
            scheduled += 1
            group.addTask {
                await operation(item)
            }
        }

        while let result = await group.next() {
            guard !Task.isCancelled else {
                group.cancelAll()
                break
            }
            await onResult(result)

            if let next = iterator.next() {
                group.addTask {
                    await operation(next)
                }
            }
        }
    }
}
