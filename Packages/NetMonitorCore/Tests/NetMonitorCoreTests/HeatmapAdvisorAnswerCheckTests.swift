import Testing
import Foundation
@testable import NetMonitorCore

/// The check on the model's heatmap advice (#455): only computed places, and the chosen action.
@Suite("HeatmapAdvisorRequest.accepts")
struct HeatmapAdvisorAnswerCheckTests {
    /// A weak north-east corner on one access point: the action is to move it toward the corner,
    /// and signal falls off toward the north-east.
    static let corner = HeatmapAdvisorBuilder.advice(
        for: HeatmapAdvisorBuilderTests.stats(weakRows: 0 ..< 3, weakCols: 4 ..< 10)
    )

    /// The same weak place, labelled Kitchen, on a plan that also has a Garage.
    static let kitchen = HeatmapAdvisorBuilder.advice(
        for: HeatmapAdvisorBuilderTests.stats(
            weakRows: 0 ..< 3, weakCols: 4 ..< 10,
            roomLabels: [RoomLabel(text: "Kitchen", normalizedX: 0.8, normalizedY: 0.1),
                         RoomLabel(text: "Garage", normalizedX: 0.2, normalizedY: 0.9)]
        ),
        planRooms: ["Kitchen", "Garage"]
    )

    @Test func anAnswerAboutTheComputedPlaceAndActionPasses() {
        #expect(Self.corner.accepts("The north-east corner is weak, so try moving the access point toward it."))
        #expect(Self.corner.accepts("Signal fades toward the northeast; moving the access point that way should help."))
    }

    @Test func anAnswerNamingAnotherPlaceIsDropped() {
        #expect(!Self.corner.accepts("The south-west corner is weak, so try moving the access point toward it."))
        #expect(!Self.corner.accepts("The north-east corner and the centre are weak, so move the access point."))
    }

    @Test func anAnswerWithAnotherActionIsDropped() {
        #expect(!Self.corner.accepts("The north-east corner is weak, so add a mesh node there."))
        #expect(!Self.corner.accepts("The north-east corner is weak."))
    }

    @Test func anAnswerNamingAnUncomputedRoomIsDropped() {
        #expect(Self.kitchen.accepts("The Kitchen is weak, so try moving the access point toward it."))
        #expect(!Self.kitchen.accepts("The Garage is weak, so try moving the access point toward it."))
    }

    @Test func aNoChangeAnswerMayWordItsOwnWay() {
        let none = HeatmapAdvisorBuilder.advice(for: HeatmapAdvisorBuilderTests.stats(weakRows: 0 ..< 2, weakCols: 8 ..< 10))

        #expect(none.accepts("Do not make any changes because little of the surveyed area is weak."))
        #expect(none.accepts("No change is needed: little of the area is weak."))
        #expect(!none.accepts("Little of the surveyed area is weak."))
    }

    @Test func compassWordsAreReadInTheAppsSpelling() {
        #expect(HeatmapAdvisorRequest.compassWords(in: "the center, the north east and the south-west")
            == ["centre", "north-east", "south-west"])
        #expect(HeatmapAdvisorRequest.compassWords(in: "the least signal in the western rooms").isEmpty)
    }

    @Test func actionWordsCountOnlyAsWholeWords() {
        let add = HeatmapAdvisorBuilder.advice(for: HeatmapAdvisorBuilderTests.stats(weakRows: 0 ..< 3, weakCols: 0 ..< 10))

        #expect(add.accepts("The north side is weak, so add an access point there."))
        #expect(!add.accepts("The north side is weak; check the address of the access point."))
    }
}
