import Foundation

public enum DeviceKind: String, Codable, CaseIterable, Sendable {
    case camera
    case mouse
    case keyboard
    case light
    case unknown

    public var label: String {
        switch self {
        case .camera: return "摄像头"
        case .mouse: return "鼠标"
        case .keyboard: return "键盘"
        case .light: return "灯光"
        case .unknown: return "未知设备"
        }
    }
}

public enum DeviceCapability: String, Codable, CaseIterable, Sendable {
    case brightness
    case contrast
    case saturation
    case sharpness
    case exposure
    case focus
    case whiteBalance
    case buttonRemapping
    case keyboardShortcuts

    public var label: String {
        switch self {
        case .brightness: return "亮度"
        case .contrast: return "对比度"
        case .saturation: return "饱和度"
        case .sharpness: return "清晰度"
        case .exposure: return "曝光"
        case .focus: return "对焦"
        case .whiteBalance: return "白平衡"
        case .buttonRemapping: return "按键映射"
        case .keyboardShortcuts: return "键盘快捷键"
        }
    }
}

public struct CameraControlDescriptor: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let capability: DeviceCapability
    public let displayName: String
    public let minimumValue: Double
    public let maximumValue: Double
    public var currentValue: Double
    public let defaultValue: Double?
    public let supportsAutomaticMode: Bool
    public let isWritable: Bool

    public init(
        id: String,
        capability: DeviceCapability,
        displayName: String,
        minimumValue: Double = 0,
        maximumValue: Double = 1,
        currentValue: Double,
        defaultValue: Double? = nil,
        supportsAutomaticMode: Bool = false,
        isWritable: Bool
    ) {
        self.id = id
        self.capability = capability
        self.displayName = displayName
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.currentValue = currentValue
        self.defaultValue = defaultValue
        self.supportsAutomaticMode = supportsAutomaticMode
        self.isWritable = isWritable
    }
}

public struct ControlValueRange: Equatable, Sendable {
    public let minimum: Double
    public let maximum: Double

    public init(minimum: Double, maximum: Double) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public func normalized(_ rawValue: Double) -> Double {
        guard maximum > minimum else { return 0 }
        return min(max((rawValue - minimum) / (maximum - minimum), 0), 1)
    }

    public func rawValue(fromNormalized normalizedValue: Double) -> Double {
        let clamped = min(max(normalizedValue, 0), 1)
        return minimum + clamped * (maximum - minimum)
    }
}

public struct DeviceDescriptor: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: DeviceKind
    public var isConnected: Bool
    public var capabilities: Set<DeviceCapability>
    public var lastError: String?

    public init(
        id: String,
        name: String,
        kind: DeviceKind,
        isConnected: Bool = false,
        capabilities: Set<DeviceCapability> = [],
        lastError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isConnected = isConnected
        self.capabilities = capabilities
        self.lastError = lastError
    }
}

public struct CameraConfiguration: Codable, Equatable, Sendable {
    public var brightness: Double?
    public var contrast: Double?
    public var saturation: Double?
    public var sharpness: Double?
    public var exposure: Double?
    public var focus: Double?
    public var whiteBalance: Double?
    public var autoExposure: Bool?
    public var autoFocus: Bool?
    public var autoWhiteBalance: Bool?

    public init(
        brightness: Double? = nil,
        contrast: Double? = nil,
        saturation: Double? = nil,
        sharpness: Double? = nil,
        exposure: Double? = nil,
        focus: Double? = nil,
        whiteBalance: Double? = nil,
        autoExposure: Bool? = nil,
        autoFocus: Bool? = nil,
        autoWhiteBalance: Bool? = nil
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.sharpness = sharpness
        self.exposure = exposure
        self.focus = focus
        self.whiteBalance = whiteBalance
        self.autoExposure = autoExposure
        self.autoFocus = autoFocus
        self.autoWhiteBalance = autoWhiteBalance
    }
}

public struct InputMapping: Codable, Equatable, Sendable {
    public var source: String
    public var action: String

    public init(source: String, action: String) {
        self.source = source
        self.action = action
    }
}

public struct Profile: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var bundleIdentifiers: [String]
    public var cameraConfigurations: [String: CameraConfiguration]
    public var inputMappings: [InputMapping]
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifiers: [String] = [],
        cameraConfigurations: [String: CameraConfiguration] = [:],
        inputMappings: [InputMapping] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifiers = bundleIdentifiers
        self.cameraConfigurations = cameraConfigurations
        self.inputMappings = inputMappings
        self.isEnabled = isEnabled
    }
}

public struct LocalDeskConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var profiles: [Profile]
    public var defaultProfileID: UUID?
    public var automaticSwitchingEnabled: Bool

    public init(
        schemaVersion: Int = 1,
        profiles: [Profile] = [Profile(name: "默认桌面")],
        defaultProfileID: UUID? = nil,
        automaticSwitchingEnabled: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.defaultProfileID = defaultProfileID ?? profiles.first?.id
        self.automaticSwitchingEnabled = automaticSwitchingEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profiles
        case defaultProfileID
        case automaticSwitchingEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        profiles = try container.decodeIfPresent([Profile].self, forKey: .profiles) ?? [Profile(name: "默认桌面")]
        defaultProfileID = try container.decodeIfPresent(UUID.self, forKey: .defaultProfileID) ?? profiles.first?.id
        automaticSwitchingEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticSwitchingEnabled) ?? true
    }
}
