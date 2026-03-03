import Foundation

/// Manages a shared target address that pre-fills tool input fields.
/// Persists saved targets to UserDefaults; the active selection is in-memory only (resets on launch).
@MainActor
@Observable
final class TargetManager {
    static let shared = TargetManager()

    // MARK: - State

    /// The currently selected target (in-memory only — resets on app launch)
    var currentTarget: String?

    /// Persistently saved targets (max 10)
    private(set) var savedTargets: [String] = []

    // MARK: - Constants

    private static let savedTargetsKey = "targetManager_savedTargets"
    private static let maxTargets = 10

    // MARK: - Init

    private init() {
        loadSavedTargets()
    }

    // MARK: - Actions

    /// Sets the current target and saves it if not already in the list.
    func setTarget(_ target: String) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentTarget = trimmed
        addToSaved(trimmed)
    }

    /// Adds a target to the saved list without selecting it.
    func addToSaved(_ target: String) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Remove duplicate if exists
        savedTargets.removeAll { $0 == trimmed }
        // Insert at front
        savedTargets.insert(trimmed, at: 0)
        // Cap at max
        if savedTargets.count > Self.maxTargets {
            savedTargets = Array(savedTargets.prefix(Self.maxTargets))
        }
        persist()
    }

    /// Removes a target from the saved list.
    func removeFromSaved(_ target: String) {
        savedTargets.removeAll { $0 == target }
        if currentTarget == target {
            currentTarget = nil
        }
        persist()
    }

    /// Removes a target at the given index.
    func removeFromSaved(at offsets: IndexSet) {
        let removing = offsets.map { savedTargets[$0] }
        savedTargets.remove(atOffsets: offsets)
        if let current = currentTarget, removing.contains(current) {
            currentTarget = nil
        }
        persist()
    }

    /// Clears the current selection without removing saved targets.
    func clearSelection() {
        currentTarget = nil
    }

    // MARK: - Persistence

    private func loadSavedTargets() {
        if let data = UserDefaults.standard.data(forKey: Self.savedTargetsKey),
           let targets = try? JSONDecoder().decode([String].self, from: data) {
            savedTargets = targets
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(savedTargets) {
            UserDefaults.standard.set(data, forKey: Self.savedTargetsKey)
        }
    }
}
