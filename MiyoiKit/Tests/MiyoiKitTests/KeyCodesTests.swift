import XCTest
import MiyoiKit

final class KeyCodesTests: XCTestCase {
    func testModifierNamesUsesStableDisplayOrder() {
        XCTAssertEqual(KeyCodes.modifierNames(0), [])
        XCTAssertEqual(KeyCodes.modifierNames(0x1E), ["Shift", "Ctrl", "Alt", "Win"])
    }

    func testModifierNamesIgnoresUnrecognizedBits() {
        XCTAssertEqual(KeyCodes.modifierNames(0xE1), [])
        XCTAssertEqual(KeyCodes.modifierNames(0xE3), ["Shift"])
    }

    func testUsageNamesCoverLettersDigitsAndControls() {
        XCTAssertEqual(KeyCodes.usageName(0x00), "None")
        XCTAssertEqual(KeyCodes.usageName(0x04), "A")
        XCTAssertEqual(KeyCodes.usageName(0x1D), "Z")
        XCTAssertEqual(KeyCodes.usageName(0x1E), "1")
        XCTAssertEqual(KeyCodes.usageName(0x27), "0")
        XCTAssertEqual(KeyCodes.usageName(0x28), "Enter")
        XCTAssertEqual(KeyCodes.usageName(0x45), "F12")
        XCTAssertEqual(KeyCodes.usageName(0xE0), "Ctrl")
    }

    func testUnknownUsageUsesUppercaseHexFallback() {
        XCTAssertEqual(KeyCodes.usageName(0x03), "0x03")
        XCTAssertEqual(KeyCodes.usageName(0xFF), "0xFF")
    }

    func testMediaUsageNamesAndUnknownUsage() {
        XCTAssertEqual(KeyCodes.mediaName(0xE9), "Volume Up")
        XCTAssertEqual(KeyCodes.mediaName(0xCD), "Play/Pause")
        XCTAssertEqual(KeyCodes.mediaName(0x97), "Mail")
        XCTAssertNil(KeyCodes.mediaName(0xFFFF))
    }
}
