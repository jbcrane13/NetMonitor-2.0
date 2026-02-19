import XCTest

@MainActor
final class InteractionFlowUITests: IOSUITestCase {
    func testTabSwitchUpdatesSelectedStateAndVisibleScreen() {
        let dashboardTab = requireExists(
            app.tabBars.buttons["Dashboard"],
            message: "Dashboard tab should exist"
        )
        let mapTab = requireExists(
            app.tabBars.buttons["Map"],
            message: "Map tab should exist"
        )
        let toolsTab = requireExists(
            app.tabBars.buttons["Tools"],
            message: "Tools tab should exist"
        )

        mapTab.tap()
        requireExists(
            app.buttons["networkMap_button_scan"],
            message: "Network Map scan button should be visible after tapping Map tab"
        )
        XCTAssertTrue(mapTab.isSelected, "Map tab should be selected")
        XCTAssertFalse(dashboardTab.isSelected, "Dashboard tab should not remain selected")

        toolsTab.tap()
        requireExists(
            quickActionSetTarget(),
            message: "Set Target quick action should be visible after tapping Tools tab"
        )
        XCTAssertTrue(toolsTab.isSelected, "Tools tab should be selected")
        XCTAssertFalse(mapTab.isSelected, "Map tab should not remain selected")
    }

    func testSetTargetPersistsAndDisplaysSelectedTarget() {
        openTools()

        let setTargetQuickAction = requireExists(
            quickActionSetTarget(),
            message: "Set Target quick action should exist"
        )
        setTargetQuickAction.tap()

        let addressField = app.textFields["setTarget_input_address"]
        clearAndTypeText("1.1.1.1", into: addressField)

        let setButton = requireExists(
            app.buttons["setTarget_button_set"],
            message: "Set button should appear when a target is entered"
        )
        setButton.tap()
        XCTAssertTrue(
            waitForDisappearance(addressField, timeout: 3),
            "Set Target sheet should dismiss after saving the target"
        )

        requireExists(
            quickActionSetTarget(),
            message: "Set Target quick action should remain visible after dismissing the sheet"
        )

        setTargetQuickAction.tap()
        requireExists(
            app.buttons["setTarget_saved_1_1_1_1"],
            message: "Saved target row should exist after setting target"
        )
        app.buttons["setTarget_button_cancel"].tap()
        requireExists(
            quickActionSetTarget(),
            message: "Set Target quick action should be visible after cancelling the sheet"
        )
        let quickActionLabel = quickActionSetTarget().label
        XCTAssertTrue(
            quickActionLabel.contains("1.1.1.1"),
            "Set Target quick action should display the selected target"
        )
    }

    func testHighLatencyToggleShowsAndHidesThresholdControl() {
        openSettings()

        let highLatencyToggle = highLatencyToggleElement()
        scrollToElement(highLatencyToggle)
        requireExists(highLatencyToggle, message: "High latency toggle should exist")

        let initiallyOn = switchIsOn(highLatencyToggle)

        XCTAssertTrue(
            toggleHighLatencySwitch(from: initiallyOn),
            "High latency toggle should change state when tapped"
        )
        let toggledOn = switchIsOn(highLatencyToggleElement())

        returnToDashboardFromSettings()
        openSettings()

        let reloadedToggle = requireExists(
            highLatencyToggleElement(),
            message: "High latency toggle should still be present after reloading Settings"
        )
        scrollToElement(reloadedToggle)
        XCTAssertEqual(
            toggledOn,
            switchIsOn(reloadedToggle),
            "High latency toggle state should persist after leaving and re-opening Settings"
        )

        let thresholdControl = highLatencyThresholdControl()
        scrollToElement(reloadedToggle)
        if toggledOn {
            if !thresholdControl.exists {
                let collection = app.collectionViews.firstMatch
                if collection.exists {
                    collection.swipeUp()
                } else {
                    app.swipeUp()
                }
            }
            XCTAssertTrue(
                thresholdControl.waitForExistence(timeout: 2),
                "Threshold control should be visible when High Latency Alerts is enabled"
            )
        } else {
            XCTAssertTrue(
                waitForExistenceState(of: thresholdControl, shouldExist: false),
                "Threshold control should be hidden when High Latency Alerts is disabled"
            )
        }

        XCTAssertTrue(
            toggleHighLatencySwitch(from: toggledOn),
            "High latency toggle should return to original state when tapped again"
        )
        XCTAssertEqual(
            initiallyOn,
            switchIsOn(highLatencyToggleElement()),
            "High latency toggle should return to initial state"
        )

        let restoredStateControl = highLatencyThresholdControl()
        if initiallyOn {
            if !restoredStateControl.exists {
                let collection = app.collectionViews.firstMatch
                if collection.exists {
                    collection.swipeUp()
                } else {
                    app.swipeUp()
                }
            }
            XCTAssertTrue(
                restoredStateControl.waitForExistence(timeout: 2),
                "Threshold control should be visible when restoring enabled High Latency Alerts state"
            )
        } else {
            XCTAssertTrue(
                waitForExistenceState(of: restoredStateControl, shouldExist: false),
                "Threshold control should be hidden when restoring disabled High Latency Alerts state"
            )
        }
    }

    func testClearHistoryAlertCancelAndConfirmPaths() {
        openSettings()

        let clearHistoryButton = app.buttons["settings_button_clearHistory"]
        scrollToElement(clearHistoryButton)
        requireExists(clearHistoryButton, message: "Clear History button should exist")

        clearHistoryButton.tap()

        let clearHistoryAlert = app.alerts["Clear History"]
        requireExists(clearHistoryAlert, timeout: 3, message: "Clear History alert should appear")
        requireExists(clearHistoryAlert.buttons["Cancel"], message: "Clear History alert should include Cancel")
        requireExists(clearHistoryAlert.buttons["Clear"], message: "Clear History alert should include Clear")
        clearHistoryAlert.buttons["Cancel"].tap()
        XCTAssertTrue(waitForDisappearance(clearHistoryAlert), "Alert should dismiss after tapping Cancel")

        clearHistoryButton.tap()
        requireExists(clearHistoryAlert, timeout: 3, message: "Clear History alert should appear again")
        clearHistoryAlert.buttons["Clear"].tap()
        XCTAssertTrue(waitForDisappearance(clearHistoryAlert), "Alert should dismiss after tapping Clear")
        let stillInSettings = ui("screen_settings").exists || app.navigationBars["Settings"].exists
        let returnedToDashboard = app.buttons["dashboard_button_settings"].exists
        XCTAssertTrue(
            stillInSettings || returnedToDashboard,
            "After clearing history, app should remain in Settings or return to Dashboard"
        )
    }

    func testAcknowledgementsLinkNavigatesAndReturnsToSettings() {
        openSettings()

        let acknowledgementsLink = app.buttons["settings_link_acknowledgements"]
        scrollToElement(acknowledgementsLink)
        requireExists(acknowledgementsLink, message: "Acknowledgements link should exist in settings")
        acknowledgementsLink.tap()

        requireExists(
            ui("screen_acknowledgements"),
            message: "Acknowledgements screen should appear after tapping link"
        )

        let backButton = requireExists(
            app.navigationBars.buttons.firstMatch,
            message: "Back button should be visible from acknowledgements"
        )
        backButton.tap()
        assertSettingsVisible()
    }

    func testMacPairingScreenOpensAndCancelsBackToSettings() {
        openSettings()

        let connectButton = requireExists(
            app.buttons["settings_button_connectMac"],
            message: "Connect to Mac button should be visible when disconnected"
        )
        connectButton.tap()

        requireExists(ui("screen_macPairing"), message: "Mac Pairing screen should appear after tapping Connect to Mac")
        let cancelButton = requireExists(
            app.buttons["pairing_cancel"],
            message: "Pairing cancel button should be visible"
        )
        cancelButton.tap()
        assertSettingsVisible()
    }

    private func openTools() {
        let toolsTab = requireExists(app.tabBars.buttons["Tools"], message: "Tools tab should exist")
        toolsTab.tap()
        requireExists(
            quickActionSetTarget(),
            message: "Tools quick action section should be visible"
        )
    }

    private func openSettings() {
        let settingsButton = app.buttons["dashboard_button_settings"]
        requireExists(settingsButton, message: "Dashboard settings button should exist")
        settingsButton.tap()

        // Retry once if the first navigation tap doesn't transition.
        if !ui("screen_settings").exists && !app.navigationBars["Settings"].exists && settingsButton.exists {
            settingsButton.tap()
        }
        assertSettingsVisible()
    }

    private func returnToDashboardFromSettings() {
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.exists {
            backButton.tap()
        }
        requireExists(
            app.buttons["dashboard_button_settings"],
            message: "Dashboard should be visible after leaving Settings"
        )
    }

    private func assertSettingsVisible() {
        let settingsRoot = ui("screen_settings")
        let settingsNavBar = app.navigationBars["Settings"]
        let visible = settingsRoot.waitForExistence(timeout: 5) || settingsNavBar.waitForExistence(timeout: 5)
        XCTAssertTrue(visible, "Settings screen should be visible")
    }

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func quickActionSetTarget() -> XCUIElement {
        let button = app.buttons["quickAction_set_target"]
        if button.exists {
            return button
        }
        let labeledButton = app.buttons["Set Target"]
        if labeledButton.exists {
            return labeledButton
        }
        let legacyIdentifier = app.buttons.matching(
            NSPredicate(format: "identifier == 'tools_section_quickActions' AND label == 'Set Target'")
        ).firstMatch
        if legacyIdentifier.exists {
            return legacyIdentifier
        }
        return ui("quickAction_set_target")
    }

    private func switchIsOn(_ toggle: XCUIElement) -> Bool {
        if let number = toggle.value as? NSNumber {
            return number.boolValue
        }

        let normalized = String(describing: toggle.value as Any)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.contains("not selected")
            || normalized.contains("false")
            || normalized.contains("off")
            || normalized == "0"
            || normalized.contains("optional(0)") {
            return false
        }

        return normalized.contains("selected")
            || normalized.contains("true")
            || normalized.contains("on")
            || normalized == "1"
            || normalized.contains("optional(1)")
    }

    private func toggleHighLatencySwitch(from previousState: Bool, timeout: TimeInterval = 2) -> Bool {
        for attempt in 0..<3 {
            let toggle = highLatencyToggleElement()
            scrollToElement(toggle)
            if toggle.isHittable {
                toggle.tap()
            } else {
                tapTrailingEdge(of: toggle)
            }
            if waitForHighLatencySwitchStateChange(from: previousState, timeout: timeout) {
                return true
            }
            if attempt == 0 {
                let retryTarget = highLatencyToggleElement()
                if retryTarget.exists {
                    tapTrailingEdge(of: retryTarget)
                    if waitForHighLatencySwitchStateChange(from: previousState, timeout: timeout) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func waitForHighLatencySwitchStateChange(from previousState: Bool, timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let toggle = highLatencyToggleElement()
            if toggle.exists && switchIsOn(toggle) != previousState {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func highLatencyToggleElement() -> XCUIElement {
        let query = app.switches.matching(identifier: "settings_toggle_highLatencyAlert")
        let count = query.count
        if count > 0 {
            for index in 0..<count {
                let candidate = query.element(boundBy: index)
                if candidate.exists && candidate.isHittable {
                    return candidate
                }
            }
        }
        return query.firstMatch
    }

    private func highLatencyThresholdControl() -> XCUIElement {
        let control = app.steppers["settings_stepper_highLatencyThresholdControl"]
        if control.exists {
            return control
        }
        let anyControl = ui("settings_stepper_highLatencyThresholdControl")
        if anyControl.exists {
            return anyControl
        }
        return ui("settings_stepper_highLatencyThreshold")
    }

    private func waitForExistenceState(
        of element: XCUIElement,
        shouldExist: Bool,
        timeout: TimeInterval = 2
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == %@", NSNumber(value: shouldExist))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
}
