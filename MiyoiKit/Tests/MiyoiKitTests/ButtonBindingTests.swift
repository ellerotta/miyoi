import XCTest
import MiyoiKit

final class ButtonBindingTests: XCTestCase {
    func testBasicBindingFactories() {
        XCTAssertEqual(ButtonBinding.disabled, ButtonBinding(actionType: 0, data: []))
        XCTAssertEqual(.mouse(.defaultAction), ButtonBinding(actionType: 1, data: [0]))
        XCTAssertEqual(.mouse(.forward), ButtonBinding(actionType: 1, data: [5]))
        XCTAssertEqual(.xclick(), ButtonBinding(actionType: 2, data: [1, 1, 2, 0, 100]))
        XCTAssertEqual(.keyboard(modifier: 0x06, usage: 0x04), ButtonBinding(actionType: 4, data: [0x06, 0x04]))
        XCTAssertEqual(.media(0x1234), ButtonBinding(actionType: 5, data: [0x12, 0x34]))
    }

    func testDPIBindingFactoriesUseBigEndianValues() {
        XCTAssertEqual(.dpiCycle(), ButtonBinding(actionType: 7, data: [6]))
        XCTAssertEqual(.dpiLock(26_000), ButtonBinding(actionType: 7, data: [5, 0x65, 0x90, 0x65, 0x90]))
    }

    func testLoopBindingFactories() {
        XCTAssertEqual(.profileLoop(), ButtonBinding(actionType: 8, data: [3]))
        XCTAssertEqual(.pollingLoop(), ButtonBinding(actionType: 13, data: [3]))
        XCTAssertEqual(.lodLoop(), ButtonBinding(actionType: 14, data: [3]))
    }

    func testMacroFactoryEncodesIdentifierAndRunCount() {
        XCTAssertEqual(.macro(id: 1), ButtonBinding(actionType: 16, data: [0, 1, 0]))
        XCTAssertEqual(.macro(id: 3, runTimes: 7), ButtonBinding(actionType: 18, data: [0, 3, 7]))
    }

    func testDescriptionsForKnownBindings() {
        XCTAssertEqual(ButtonBinding.disabled.describe(), "—")
        XCTAssertEqual(ButtonBinding.mouse(.defaultAction).describe(), "Default Action")
        XCTAssertEqual(ButtonBinding.mouse(.right).describe(), "Right Click")
        XCTAssertEqual(ButtonBinding.xclick().describe(), "Double Click")
        XCTAssertEqual(ButtonBinding.keyboard(modifier: 0x06, usage: 0x04).describe(), "Shift+Ctrl+A")
        XCTAssertEqual(ButtonBinding.media(0x00E9).describe(), "Volume Up")
        XCTAssertEqual(ButtonBinding.dpiLock(1_600).describe(), "DPI lock 1600")
        XCTAssertEqual(ButtonBinding.macro(id: 2, runTimes: 4).describe(), "Macro 2 ×4")
    }

    func testDescriptionsGracefullyHandleUnknownOrMissingData() {
        XCTAssertEqual(ButtonBinding(actionType: 1, data: [0xFF]).describe(), "Button 255")
        XCTAssertEqual(ButtonBinding(actionType: 4, data: []).describe(), "None")
        XCTAssertEqual(ButtonBinding(actionType: 5, data: []).describe(), "Media")
        XCTAssertEqual(ButtonBinding(actionType: 99, data: []).describe(), "Action 99")
    }

    func testPublicEnumIdentifiersAndLabels() {
        XCTAssertEqual(MouseButton.button8.id, 8)
        XCTAssertEqual(MouseButton.button8.label, "Button 5")
        XCTAssertEqual(MouseButton.lodLoopDown.label, "LOD Cycle Down")
        XCTAssertEqual(ButtonActionType.keyboard.id, 4)
        XCTAssertEqual(ButtonActionType.keyboard.label, "Key")
        XCTAssertEqual(ButtonActionType.macro3.label, "Macro 3")
    }
}
