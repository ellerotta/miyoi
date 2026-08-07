import Foundation
import MiyoiKit

private struct SelfTestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw SelfTestFailure(description: message) }
}

do {
    try expect(DeviceRegistry.vendorID == 0x373E, "unexpected vendor ID")
    try expect(DeviceRegistry.models.map(\.id) == ["r6", "r5u", "m5u"], "unexpected model registry")

    let modelIDs = DeviceRegistry.models.map(\.id)
    let pids = DeviceRegistry.models.flatMap(\.pidList)
    try expect(Set(modelIDs).count == modelIDs.count, "duplicate model ID")
    try expect(Set(pids).count == pids.count, "duplicate PID")

    for model in DeviceRegistry.models {
        try expect(DeviceRegistry.model(forPID: model.wiredPID) == model, "wired PID lookup failed for \(model.name)")
        try expect(DeviceRegistry.model(forPID: model.wirelessPID) == model, "wireless PID lookup failed for \(model.name)")
        try expect(model.maxDPIX > 0 && model.maxDPIY > 0, "invalid DPI limit for \(model.name)")
        try expect(!model.buttonIndices.isEmpty, "missing button metadata for \(model.name)")
    }

    try expect(KeyCodes.usageName(0x04) == "A", "keyboard usage mapping failed")
    try expect(KeyCodes.mediaName(0xCD) == "Play/Pause", "media usage mapping failed")
    try expect(RGB(r: 0, g: 10, b: 255).hex == "000AFF", "RGB formatting failed")
    try expect(ButtonBinding.mouse(.defaultAction).describe() == "Default Action", "default binding description failed")
    try expect(ButtonBinding.keyboard(modifier: 0x06, usage: 0x04).describe() == "Shift+Ctrl+A", "keyboard binding description failed")
    try expect(ButtonBinding.dpiLock(1_600).describe() == "DPI lock 1600", "DPI binding encoding failed")
    try expect(ButtonBinding.macro(id: 2, runTimes: 4).describe() == "Macro 2 ×4", "macro binding encoding failed")

    print("Miyoi self-tests passed")
} catch {
    FileHandle.standardError.write(Data("Self-test failed: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
