import Foundation
import MiyoiKit

private let usage = """
    miyoictl - attack shark mouse control

    Usage:
      miyoictl list [--pid PID]                       list supported config interfaces
      miyoictl info [--pid PID]                       show device information
      miyoictl poll [--pid PID] [HZ]                  get or set polling rate
      miyoictl dpi [--pid PID]                        show DPI stages
      miyoictl dpi-set [--pid PID] X:Y[,X:Y...]       set DPI stages
      miyoictl dpi-active [--pid PID] [STAGE]         get or set active DPI stage
      miyoictl lod [--pid PID] [MM]                   get or set a supported LOD value
      miyoictl battery [--pid PID]                    show battery level
      miyoictl bind [--pid PID] list                  list button bindings
      miyoictl bind [--pid PID] set BUTTON key KEY    bind a key name or usage number
      miyoictl bind [--pid PID] set BUTTON macro ID   bind macro 1, 2, or 3
      miyoictl bind [--pid PID] set BUTTON dpi DPI    bind DPI lock
      miyoictl bind [--pid PID] set BUTTON off        disable a button

    PID and numeric key usages accept decimal or a 0x hexadecimal prefix.
    examples: miyoictl info --pid 0x0046, miyoictl bind set 1 key W
    """

private enum CLIError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message): return message
        }
    }
}

private struct Arguments {
    let command: String
    let operands: [String]
    let pid: Int?

    init(_ rawArguments: [String]) throws {
        let values = Array(rawArguments.dropFirst())
        var positional: [String] = []
        var selectedPID: Int?
        var index = 0
        while index < values.count {
            let value = values[index]
            if value == "--pid" {
                guard selectedPID == nil else {
                    throw CLIError.message("--pid may be specified only once")
                }
                guard index + 1 < values.count else {
                    throw CLIError.message("--pid requires a value")
                }
                selectedPID = try parsePID(values[index + 1])
                index += 2
            } else if value.hasPrefix("--pid=") {
                guard selectedPID == nil else {
                    throw CLIError.message("--pid may be specified only once")
                }
                selectedPID = try parsePID(String(value.dropFirst("--pid=".count)))
                index += 1
            } else if value == "--help" {
                positional.append(value)
                index += 1
            } else if value.hasPrefix("--") {
                throw CLIError.message("unknown option: \(value)")
            } else {
                positional.append(value)
                index += 1
            }
        }

        guard let command = positional.first else {
            throw CLIError.message(usage)
        }
        self.command = command
        operands = Array(positional.dropFirst())
        pid = selectedPID
    }
}

private func parseInteger(_ value: String, name: String) throws -> Int {
    let parsed: Int?
    if value.lowercased().hasPrefix("0x") {
        let digits = value.dropFirst(2)
        parsed = digits.isEmpty ? nil : Int(digits, radix: 16)
    } else {
        parsed = Int(value, radix: 10)
    }
    guard let parsed else {
        throw CLIError.message("invalid \(name): \(value)")
    }
    return parsed
}

private func parsePID(_ value: String) throws -> Int {
    let pid = try parseInteger(value, name: "PID")
    guard (0...0xFFFF).contains(pid) else {
        throw CLIError.message("PID must be between 0 and 65535")
    }
    guard DeviceRegistry.model(forPID: pid) != nil else {
        throw CLIError.message(String(format: "unsupported PID: 0x%04X", pid))
    }
    return pid
}

private func requireArity(_ operands: [String], _ allowed: ClosedRange<Int>, usage commandUsage: String) throws {
    guard allowed.contains(operands.count) else {
        throw CLIError.message("usage: \(commandUsage)")
    }
}

private func requireArity(_ operands: [String], _ count: Int, usage commandUsage: String) throws {
    try requireArity(operands, count...count, usage: commandUsage)
}

private func resolveDevice(pid: Int?) throws -> MiyoiDevice {
    if let pid {
        guard let model = DeviceRegistry.model(forPID: pid) else {
            throw CLIError.message(String(format: "unsupported PID: 0x%04X", pid))
        }
        let isConnected = DeviceDiscovery.allHIDDevices().contains {
            $0.info.vid == DeviceRegistry.vendorID &&
                $0.info.pid == pid &&
                $0.info.usagePage == 0xFFFF
        }
        guard isConnected else {
            throw CLIError.message(String(format: "device 0x%04X is not connected", pid))
        }
        return try MiyoiDevice.open(model: model, pid: pid)
    }

    for model in DeviceRegistry.models {
        do {
            return try MiyoiDevice.open(model: model)
        } catch HIDTransportError.deviceNotFound {
            continue
        }
    }
    throw CLIError.message("no supported attack shark device is connected")
}

private func parseDPIStages(_ value: String) throws -> [DPIStage] {
    let stageValues = value.split(separator: ",", omittingEmptySubsequences: false)
    return try stageValues.enumerated().map { offset, stageValue in
        let pair = stageValue.split(separator: ":", omittingEmptySubsequences: false)
        guard pair.count == 2 else {
            throw CLIError.message("DPI stage \(offset) must use X:Y format")
        }
        let x = try parseInteger(String(pair[0]), name: "DPI X")
        let y = try parseInteger(String(pair[1]), name: "DPI Y")
        guard (1...0xFFFF).contains(x) else {
            throw CLIError.message("DPI X must be between 1 and 65535")
        }
        guard (1...0xFFFF).contains(y) else {
            throw CLIError.message("DPI Y must be between 1 and 65535")
        }
        return DPIStage(x: x, y: y)
    }
}

private func validateDPIStages(_ stages: [DPIStage], model: DeviceModel) throws {
    guard (1...model.maxStageCount).contains(stages.count) else {
        throw CLIError.message("DPI stage count must be between 1 and \(model.maxStageCount)")
    }
    guard stages.allSatisfy({ $0.x <= model.maxDPIX }) else {
        throw CLIError.message("DPI X must be between 1 and \(model.maxDPIX)")
    }
    guard stages.allSatisfy({ $0.y <= model.maxDPIY }) else {
        throw CLIError.message("DPI Y must be between 1 and \(model.maxDPIY)")
    }
}

private func parseKeyUsage(_ value: String) throws -> UInt8 {
    if value.first?.isNumber == true || value.lowercased().hasPrefix("0x") {
        let usage = try parseInteger(value, name: "key usage")
        guard let byte = UInt8(exactly: usage) else {
            throw CLIError.message("key usage must be between 0 and 255")
        }
        return byte
    }

    let normalized = value.lowercased()
    for usage in UInt8.min...UInt8.max {
        let name = KeyCodes.usageName(usage)
        if !name.hasPrefix("0x") && name.lowercased() == normalized {
            return usage
        }
    }
    throw CLIError.message("unknown key name: \(value)")
}

private func makeBinding(_ operands: [String], model: DeviceModel) throws -> (UInt8, ButtonBinding) {
    guard operands.count >= 3, operands[0] == "set" else {
        throw CLIError.message("usage: miyoictl bind [--pid PID] set BUTTON {key KEY|macro ID|dpi DPI|off}")
    }
    let button = try parseInteger(operands[1], name: "button")
    guard let buttonIndex = UInt8(exactly: button), model.buttonIndices.contains(buttonIndex) else {
        let values = model.buttonIndices.sorted().map(String.init).joined(separator: ", ")
        throw CLIError.message("button must be one of: \(values)")
    }

    switch operands[2].lowercased() {
    case "key":
        try requireArity(operands, 4, usage: "miyoictl bind [--pid PID] set BUTTON key KEY")
        return (buttonIndex, .keyboard(usage: try parseKeyUsage(operands[3])))
    case "macro":
        try requireArity(operands, 4, usage: "miyoictl bind [--pid PID] set BUTTON macro ID")
        let macroID = try parseInteger(operands[3], name: "macro ID")
        guard (1...3).contains(macroID) else {
            throw CLIError.message("macro ID must be between 1 and 3")
        }
        return (buttonIndex, .macro(id: macroID))
    case "dpi":
        try requireArity(operands, 4, usage: "miyoictl bind [--pid PID] set BUTTON dpi DPI")
        let dpi = try parseInteger(operands[3], name: "DPI")
        guard (1...min(model.maxDPIX, model.maxDPIY)).contains(dpi) else {
            throw CLIError.message("DPI must be between 1 and \(min(model.maxDPIX, model.maxDPIY))")
        }
        return (buttonIndex, .dpiLock(dpi))
    case "off":
        try requireArity(operands, 3, usage: "miyoictl bind [--pid PID] set BUTTON off")
        return (buttonIndex, .disabled)
    default:
        throw CLIError.message("unknown binding type: \(operands[2])")
    }
}

private func validateBindingArity(_ operands: [String]) throws {
    guard operands.count >= 3, operands[0] == "set" else {
        throw CLIError.message("usage: miyoictl bind [--pid PID] {list|set BUTTON {key KEY|macro ID|dpi DPI|off}}")
    }
    let expectedCount = operands[2].lowercased() == "off" ? 3 : 4
    try requireArity(
        operands,
        expectedCount,
        usage: "miyoictl bind [--pid PID] set BUTTON {key KEY|macro ID|dpi DPI|off}"
    )
}

private func run(_ arguments: Arguments) throws {
    switch arguments.command {
    case "help", "--help", "-h":
        try requireArity(arguments.operands, 0, usage: "miyoictl help")
        guard arguments.pid == nil else {
            throw CLIError.message("--pid is not valid with help")
        }
        print(usage)

    case "list":
        try requireArity(arguments.operands, 0, usage: "miyoictl list [--pid PID]")
        var seen: Set<String> = []
        let found = DeviceDiscovery.allHIDDevices().filter { entry in
            entry.info.vid == DeviceRegistry.vendorID &&
                entry.info.usagePage == 0xFFFF &&
                DeviceRegistry.model(forPID: entry.info.pid) != nil &&
                (arguments.pid == nil || entry.info.pid == arguments.pid)
        }
        for entry in found {
            let info = entry.info
            let identity = "\(info.id):\(info.pid):\(info.usagePage):\(info.usage)"
            guard seen.insert(identity).inserted else { continue }
            guard let model = DeviceRegistry.model(forPID: info.pid) else { continue }
            let product = info.product.isEmpty ? model.name : info.product
            print(String(format: "0x%04X %@ - %@", info.pid, model.name, product))
        }
        if seen.isEmpty {
            print("no supported attack shark config interfaces found")
        }

    case "info":
        try requireArity(arguments.operands, 0, usage: "miyoictl info [--pid PID]")
        let device = try resolveDevice(pid: arguments.pid)
        let battery = try device.batteryPercent()
        let polling = try device.pollingRateHz()
        let activeStage = try device.activeDPIStage()
        let stages = try device.dpiStages()
        let maximumDPI = try device.dpiMax()
        let lod = try device.lod()
        let sleep = try device.sleepSeconds()
        let motionSync = try device.motionSync()
        let angleSnap = try device.angleSnap()
        print("Model:       \(device.model.name)")
        print("Firmware:    \(device.firmwareVersion)")
        print("HID index:   \(device.hidIndex)")
        print("Battery:     \(battery)%")
        print("Polling:     \(polling) Hz")
        print("Active DPI:  stage \(activeStage)")
        print("DPI stages:  \(stages.map { "\($0.x)x\($0.y)" }.joined(separator: ", "))")
        print("DPI max:     \(maximumDPI)")
        print("LOD:         \(lod) mm")
        print("Sleep:       \(sleep) s")
        print("Motion sync: \(motionSync)")
        print("Angle snap:  \(angleSnap)")

    case "poll":
        try requireArity(arguments.operands, 0...1, usage: "miyoictl poll [--pid PID] [HZ]")
        if let value = arguments.operands.first {
            let hz = try parseInteger(value, name: "polling rate")
            let supportedRates = [125, 250, 500, 1_000, 2_000, 4_000, 8_000]
            guard supportedRates.contains(hz) else {
                throw CLIError.message("polling rate must be one of: \(supportedRates.map(String.init).joined(separator: ", "))")
            }
            let device = try resolveDevice(pid: arguments.pid)
            try device.setPollingRateHz(hz)
            guard try device.pollingRateHz() == hz else {
                throw CLIError.message("polling rate write could not be verified")
            }
            print("ok")
        } else {
            let device = try resolveDevice(pid: arguments.pid)
            print("\(try device.pollingRateHz()) Hz")
        }

    case "dpi":
        try requireArity(arguments.operands, 0, usage: "miyoictl dpi [--pid PID]")
        let stages = try resolveDevice(pid: arguments.pid).dpiStages()
        for (index, stage) in stages.enumerated() {
            print("\(index): \(stage.x)x\(stage.y)")
        }

    case "dpi-set":
        try requireArity(arguments.operands, 1, usage: "miyoictl dpi-set [--pid PID] X:Y[,X:Y...]")
        let stages = try parseDPIStages(arguments.operands[0])
        let device = try resolveDevice(pid: arguments.pid)
        try validateDPIStages(stages, model: device.model)
        try device.setDPIStages(stages)
        guard try device.dpiStages() == stages else {
            throw CLIError.message("DPI stage write could not be verified")
        }
        print("ok")

    case "dpi-active":
        try requireArity(arguments.operands, 0...1, usage: "miyoictl dpi-active [--pid PID] [STAGE]")
        if let value = arguments.operands.first {
            let stage = try parseInteger(value, name: "DPI stage")
            guard stage >= 0 else {
                throw CLIError.message("DPI stage must not be negative")
            }
            let device = try resolveDevice(pid: arguments.pid)
            let configuredStages = try device.dpiStages().count
            guard (0..<configuredStages).contains(stage) else {
                throw CLIError.message("DPI stage must be between 0 and \(max(0, configuredStages - 1))")
            }
            try device.setActiveDPIStage(stage)
            guard try device.activeDPIStage() == stage else {
                throw CLIError.message("active DPI stage write could not be verified")
            }
            print("ok")
        } else {
            let device = try resolveDevice(pid: arguments.pid)
            print("active stage: \(try device.activeDPIStage())")
        }

    case "lod":
        try requireArity(arguments.operands, 0...1, usage: "miyoictl lod [--pid PID] [MM]")
        if let value = arguments.operands.first {
            let device = try resolveDevice(pid: arguments.pid)
            guard let millimeters = Double(value), device.model.lodValues.contains(millimeters) else {
                let values = device.model.lodValues.map { $0.formatted() }.joined(separator: ", ")
                throw CLIError.message("LOD must be one of: \(values)")
            }
            try device.setLOD(millimeters)
            guard abs(try device.lod() - millimeters) < 0.001 else {
                throw CLIError.message("LOD write could not be verified")
            }
            print("ok")
        } else {
            let device = try resolveDevice(pid: arguments.pid)
            print("LOD: \(try device.lod()) mm")
        }

    case "battery":
        try requireArity(arguments.operands, 0, usage: "miyoictl battery [--pid PID]")
        print("\(try resolveDevice(pid: arguments.pid).batteryPercent())%")

    case "bind":
        guard arguments.operands != ["list"] else {
            let device = try resolveDevice(pid: arguments.pid)
            for index in device.model.buttonIndices.sorted() {
                print("\(index): \(try device.button(index).describe())")
            }
            return
        }
        try validateBindingArity(arguments.operands)
        let device = try resolveDevice(pid: arguments.pid)
        let (button, binding) = try makeBinding(arguments.operands, model: device.model)
        try device.setButton(button, binding)
        guard try device.button(button) == binding else {
            throw CLIError.message("button binding write could not be verified")
        }
        print("ok")

    default:
        throw CLIError.message("unknown command: \(arguments.command)\n\n\(usage)")
    }
}

do {
    try run(Arguments(CommandLine.arguments))
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(EXIT_FAILURE)
}
