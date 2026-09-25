import Foundation

public struct AudioUnitPreset: Identifiable, Equatable {
    public enum Kind: Equatable {
        case factory(number: Int)
        case user(parameterData: Data)
    }

    public let id: UUID
    public let name: String
    public let kind: Kind

    public var isFactory: Bool { if case .factory = kind { return true }; return false }
    public var isUser: Bool { !isFactory }
    public var factoryNumber: Int? {
        if case .factory(let n) = kind { return n }; return nil
    }

    public init(id: UUID = UUID(), name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public struct AudioUnitPluginSelection: Codable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let manufacturerName: String
    public let componentType: UInt32
    public let componentSubType: UInt32
    public let componentManufacturer: UInt32

    public init(
        id: UUID = UUID(),
        name: String,
        manufacturerName: String,
        componentType: UInt32,
        componentSubType: UInt32,
        componentManufacturer: UInt32
    ) {
        self.id = id
        self.name = name
        self.manufacturerName = manufacturerName
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturer = componentManufacturer
    }
}

public struct AudioUnitChainSlot: Codable, Equatable, Identifiable {
    public static let maxSlots: Int = 4

    public let id: UUID
    public var selection: AudioUnitPluginSelection
    public var isEnabled: Bool
    public var lastUsedPresetName: String?
    /// The slot's live settings, base64-encoded fullState, saved whenever the user
    /// moves a control and restored on next launch — so a chain behaves like the
    /// equaliser rather than resetting to plugin defaults.
    public var savedState: String?

    public init(
        id: UUID = UUID(),
        selection: AudioUnitPluginSelection,
        isEnabled: Bool = true,
        lastUsedPresetName: String? = nil,
        savedState: String? = nil
    ) {
        self.id = id
        self.selection = selection
        self.isEnabled = isEnabled
        self.lastUsedPresetName = lastUsedPresetName
        self.savedState = savedState
    }
}

public struct PluginSlotState: Codable, Equatable {
    public let slotID: UUID
    public let componentSubType: UInt32
    public let auState: String           // base64-encoded binary plist of fullState
    public var isEnabled: Bool

    public init(slotID: UUID, componentSubType: UInt32, auState: String, isEnabled: Bool) {
        self.slotID = slotID
        self.componentSubType = componentSubType
        self.auState = auState
        self.isEnabled = isEnabled
    }
}

public struct PluginChainConfiguration: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var slotStates: [PluginSlotState]

    public init(id: UUID = UUID(), name: String, slotStates: [PluginSlotState]) {
        self.id = id
        self.name = name
        self.slotStates = slotStates
    }
}

public enum AudioUnitPluginStatus: Equatable {
    case disabled
    case noPluginSelected
    case loading(String)
    case active(String)
    case bypassed(String)
    case unavailable(String)
    case failed(String, reason: String)

    public var displayText: String {
        switch self {
        case .disabled:               return "Plugin: Disabled"
        case .noPluginSelected:       return "Plugin: No plugin selected"
        case .loading(let name):      return "Plugin: Loading \(name)…"
        case .active(let name):       return "Plugin: Active — \(name)"
        case .bypassed(let name):     return "Plugin: Bypassed — \(name)"
        case .unavailable(let name):  return "Plugin: Not available — \(name)"
        case .failed(let name, _):    return "Plugin: Failed to load — \(name)"
        }
    }

    public var shortDisplayText: String {
        switch self {
        case .disabled, .noPluginSelected: return ""
        case .loading(let name):      return "AU: Loading \(name)…"
        case .active(let name):       return "AU: \(name)"
        case .bypassed:               return "AU: Bypassed"
        case .unavailable(let name):  return "AU: Not available — \(name)"
        case .failed:                 return "AU: Failed to load"
        }
    }

    public var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    public var isInert: Bool {
        switch self {
        case .disabled, .noPluginSelected: return true
        default: return false
        }
    }
}
