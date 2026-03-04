import NetMonitorCore

// MARK: - HeatmapSurveyViewModel + Undo / Redo

extension HeatmapSurveyViewModel {

    /// Undoes the last action (placement or deletion).
    func undo() {
        guard var currentProject = project, let action = undoStack.popLast()
        else { return }

        switch action {
        case .placement(let point):
            // Undo a placement by removing the point
            currentProject.measurementPoints.removeAll { $0.id == point.id }
            redoStack.append(.placement(point))

        case .deletion(let point, let index):
            // Undo a deletion by re-inserting the point at its original position
            let safeIndex = min(index, currentProject.measurementPoints.count)
            currentProject.measurementPoints.insert(point, at: safeIndex)
            redoStack.append(.deletion(point, index))
        }

        project = currentProject
        recalculateStats()
        renderHeatmapOverlay()
    }

    /// Redoes the last undone action.
    func redo() {
        guard var currentProject = project, let action = redoStack.popLast()
        else { return }

        switch action {
        case .placement(let point):
            // Redo a placement by adding the point back
            currentProject.measurementPoints.append(point)
            undoStack.append(.placement(point))

        case .deletion(let point, let index):
            // Redo a deletion by removing the point again
            currentProject.measurementPoints.removeAll { $0.id == point.id }
            undoStack.append(.deletion(point, index))
        }

        project = currentProject
        recalculateStats()
        renderHeatmapOverlay()
    }
}
