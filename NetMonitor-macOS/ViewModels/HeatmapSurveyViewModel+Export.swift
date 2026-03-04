import AppKit
import NetMonitorCore
import os
import UniformTypeIdentifiers

// MARK: - HeatmapSurveyViewModel + Save / Load / Export

extension HeatmapSurveyViewModel {

    // MARK: - Save

    /// Saves the current project via NSSavePanel, or overwrites the existing path
    /// if the project was previously saved or loaded.
    func saveProject() {
        guard let currentProject = project
        else { return }

        // If we already have a save path, overwrite directly
        if let existingPath = currentSavePath {
            do {
                try SurveyFileManager.save(currentProject, to: existingPath)
                Logger.app.info("Survey project overwritten at \(existingPath.lastPathComponent)")
                return
            } catch {
                // Fall through to NSSavePanel if overwrite fails
                Logger.app.warning("Overwrite failed, showing save panel: \(error.localizedDescription)")
            }
        }

        let panel = NSSavePanel()
        panel.title = "Save Survey Project"
        panel.prompt = "Save"
        panel.nameFieldStringValue = "\(currentProject.name).netmonsurvey"
        panel.allowedContentTypes = [.init(exportedAs: "com.netmonitor.survey")]

        let response = panel.runModal()
        guard response == .OK, let url = panel.url
        else { return }

        do {
            try SurveyFileManager.save(currentProject, to: url)
            currentSavePath = url
            Logger.app.info("Survey project saved to \(url.lastPathComponent)")
        } catch {
            showError("Failed to save project: \(error.localizedDescription)")
        }
    }

    /// Saves the current project to a new location via NSSavePanel (always shows panel).
    func saveProjectAs() {
        guard let currentProject = project
        else { return }

        let panel = NSSavePanel()
        panel.title = "Save Survey Project As"
        panel.prompt = "Save"
        panel.nameFieldStringValue = "\(currentProject.name).netmonsurvey"
        panel.allowedContentTypes = [.init(exportedAs: "com.netmonitor.survey")]

        let response = panel.runModal()
        guard response == .OK, let url = panel.url
        else { return }

        do {
            try SurveyFileManager.save(currentProject, to: url)
            currentSavePath = url
            Logger.app.info("Survey project saved as \(url.lastPathComponent)")
        } catch {
            showError("Failed to save project: \(error.localizedDescription)")
        }
    }

    // MARK: - Load

    /// Loads a project via NSOpenPanel.
    func openProject() {
        let panel = NSOpenPanel()
        panel.title = "Open Survey Project"
        panel.prompt = "Open"
        panel.allowedContentTypes = [.init(exportedAs: "com.netmonitor.survey")]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true

        let response = panel.runModal()
        guard response == .OK, let url = panel.url
        else { return }

        loadProject(from: url)
    }

    /// Loads a project from a bundle URL.
    func loadProject(from url: URL) {
        do {
            let loadedProject = try SurveyFileManager.load(from: url)

            // Restore the floor plan image
            let imageData = loadedProject.floorPlan.imageData
            guard let nsImage = NSImage(data: imageData)
            else {
                showError("Failed to decode floor plan image from project file.")
                return
            }

            floorPlanImage = nsImage
            importResult = FloorPlanImportResult(
                imageData: imageData,
                pixelWidth: loadedProject.floorPlan.pixelWidth,
                pixelHeight: loadedProject.floorPlan.pixelHeight,
                sourceURL: url
            )
            project = loadedProject
            currentSavePath = url

            // Restore calibration state
            if let calibrationPoints = loadedProject.floorPlan.calibrationPoints, calibrationPoints.count >= 2,
               loadedProject.floorPlan.widthMeters > 0 {
                pixelsPerMeter = Double(loadedProject.floorPlan.pixelWidth) / loadedProject.floorPlan.widthMeters
                isCalibrated = true
                computeScaleBar()
            } else {
                isCalibrated = false
                pixelsPerMeter = 0
            }

            // Reset undo/redo stacks
            undoStack.removeAll()
            redoStack.removeAll()

            recalculateStats()
            renderHeatmapOverlay()

            Logger.app.info("Survey project loaded from \(url.lastPathComponent)")
        } catch {
            showError("Failed to open project: \(error.localizedDescription)")
        }
    }

    // MARK: - PDF Export

    /// Exports the current survey project as a 3-page PDF report.
    /// Requires 3+ measurement points. Shows NSSavePanel for destination.
    func exportPDF() {
        guard let currentProject = project, let image = floorPlanImage
        else { return }

        guard canExportPDF
        else {
            showError("At least 3 measurement points are required to export a PDF report.")
            return
        }

        guard let pdfData = HeatmapPDFExporter.generatePDF(
            project: currentProject,
            floorPlanImage: image,
            heatmapOverlay: heatmapOverlayImage,
            visualization: selectedVisualization
        ) else {
            showError("Failed to generate PDF report.")
            return
        }

        let success = HeatmapPDFExporter.saveWithPanel(
            pdfData: pdfData,
            projectName: currentProject.name
        )

        if !success {
            // User cancelled — not an error
            Logger.app.debug("PDF export cancelled by user")
        }
    }

    // MARK: - New Project

    /// Creates a new project with the given name and a blank white canvas as the floor plan.
    func createNewProject(name: String, canvasWidth: Int = 1000, canvasHeight: Int = 800) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: canvasWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            showError("Failed to create canvas for new project")
            return
        }

        // Fill white background
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

        guard let filledImage = context.makeImage()
        else {
            showError("Failed to create canvas image")
            return
        }

        let rep = NSBitmapImageRep(cgImage: filledImage)
        let pngData = rep.representation(using: .png, properties: [:]) ?? Data()

        applyFloorPlanData(
            name: name,
            imageData: pngData,
            pixelWidth: canvasWidth,
            pixelHeight: canvasHeight,
            origin: .drawn
        )
        Logger.app.info("New project created: \(name)")
    }

    /// Opens an NSOpenPanel for a floor plan image and creates a new project with the given name.
    func importFloorPlanForNewProject(name: String) {
        guard let url = FloorPlanImporter.presentOpenPanel()
        else { return }

        do {
            let result = try FloorPlanImporter.importFloorPlan(from: url)
            applyFloorPlanData(
                name: name,
                imageData: result.imageData,
                pixelWidth: result.pixelWidth,
                pixelHeight: result.pixelHeight,
                origin: .imported(result.sourceURL),
                sourceURL: result.sourceURL
            )
            Logger.app.info("New project '\(name)' created with imported floor plan")
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Applies a drawn floor plan image as the base for a new project.
    func applyDrawnFloorPlan(name: String, imageData: Data) {
        guard !imageData.isEmpty,
              let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            showError("Failed to create floor plan from drawing")
            return
        }

        applyFloorPlanData(
            name: name,
            imageData: imageData,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            origin: .drawn
        )
        Logger.app.info("New project '\(name)' created with drawn floor plan")
    }
}
