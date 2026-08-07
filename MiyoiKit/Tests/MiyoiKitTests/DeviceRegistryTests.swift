import XCTest
import MiyoiKit

final class DeviceRegistryTests: XCTestCase {
    func testRegistryContainsExpectedModels() {
        XCTAssertEqual(DeviceRegistry.vendorID, 0x373E)
        XCTAssertEqual(DeviceRegistry.models.map(\.id), ["r6", "r5u", "m5u"])
        XCTAssertEqual(DeviceRegistry.models.map(\.name), ["R6", "R5 Ultra", "M5 Ultra"])
    }

    func testModelIdentifiersAndProductIdentifiersAreUnique() {
        let ids = DeviceRegistry.models.map(\.id)
        let pids = DeviceRegistry.models.flatMap(\.pidList)

        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(pids).count, pids.count)
    }

    func testEveryRegisteredPIDResolvesToItsModel() {
        for model in DeviceRegistry.models {
            XCTAssertEqual(model.pidList, [model.wiredPID, model.wirelessPID])
            XCTAssertEqual(DeviceRegistry.model(forPID: model.wiredPID), model)
            XCTAssertEqual(DeviceRegistry.model(forPID: model.wirelessPID), model)
        }
    }

    func testUnknownPIDDoesNotResolve() {
        XCTAssertNil(DeviceRegistry.model(forPID: 0xFFFF))
    }

    func testPublishedModelCapabilitiesAreInternallyConsistent() {
        for model in DeviceRegistry.models {
            XCTAssertGreaterThan(model.maxDPIX, 0)
            XCTAssertGreaterThan(model.maxDPIY, 0)
            XCTAssertGreaterThan(model.maxStageCount, 0)
            XCTAssertFalse(model.hasLCD)
        }

        XCTAssertTrue(DeviceRegistry.model(forPID: 0x0021)?.supportsRipple == true)
        XCTAssertTrue(DeviceRegistry.model(forPID: 0x003A)?.supportsHyper == false)
        XCTAssertTrue(DeviceRegistry.model(forPID: 0x003A)?.supportsRipple == true)
        XCTAssertEqual(DeviceRegistry.model(forPID: 0x0047)?.lodValues, [0.7, 1, 2])
    }
}
