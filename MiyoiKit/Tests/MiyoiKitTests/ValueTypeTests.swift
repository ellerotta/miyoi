import XCTest
import MiyoiKit

final class ValueTypeTests: XCTestCase {
    func testRGBHexUsesSixUppercaseDigits() {
        XCTAssertEqual(RGB(r: 0, g: 10, b: 255).hex, "000AFF")
        XCTAssertEqual(RGB(r: 171, g: 205, b: 239).hex, "ABCDEF")
    }

    func testDPIStageAndRGBHaveValueSemantics() {
        XCTAssertEqual(DPIStage(x: 800, y: 1_600), DPIStage(x: 800, y: 1_600))
        XCTAssertNotEqual(DPIStage(x: 800, y: 1_600), DPIStage(x: 1_600, y: 800))
        XCTAssertEqual(RGB(r: 1, g: 2, b: 3), RGB(r: 1, g: 2, b: 3))
    }

    func testMiyoiErrorDescriptions() {
        XCTAssertEqual(MiyoiError.deviceNotFound.errorDescription, "Device not found")
        XCTAssertEqual(MiyoiError.noResponse.errorDescription, "Device did not respond")
        XCTAssertEqual(MiyoiError.protocolMismatch.errorDescription, "Unexpected protocol response")
    }
}
