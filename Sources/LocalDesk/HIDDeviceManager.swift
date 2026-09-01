import Foundation
@preconcurrency import IOKit
@preconcurrency import IOKit.hid
import LocalDeskCore

@MainActor
final class HIDDeviceManager: ObservableObject {
    @Published private(set) var descriptors: [DeviceDescriptor] = []
    var onDevicesChanged: (() -> Void)?

    private let manager: IOHIDManager
    private var isStarted = false

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start() {
        guard !isStarted else {
            rescan()
            return
        }
        isStarted = true

        let matching: [[String: Int]] = [
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse
            ],
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let owner = Unmanaged<HIDDeviceManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in owner.rescan() }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let owner = Unmanaged<HIDDeviceManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in owner.rescan() }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        rescan()
    }

    func rescan() {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            descriptors = []
            return
        }

        descriptors = devices.compactMap(descriptor(for:)).sorted {
            if $0.kind == $1.kind { return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return $0.kind.rawValue < $1.kind.rawValue
        }
        onDevicesChanged?()
    }

    private func descriptor(for device: IOHIDDevice) -> DeviceDescriptor? {
        let usagePage = integerProperty(kIOHIDPrimaryUsagePageKey, device: device)
        let usage = integerProperty(kIOHIDPrimaryUsageKey, device: device)
        guard usagePage == kHIDPage_GenericDesktop else { return nil }

        let kind: DeviceKind
        let capabilities: Set<DeviceCapability>
        switch usage {
        case kHIDUsage_GD_Mouse:
            kind = .mouse
            capabilities = [.buttonRemapping]
        case kHIDUsage_GD_Keyboard:
            kind = .keyboard
            capabilities = [.keyboardShortcuts]
        default:
            return nil
        }

        let product = stringProperty(kIOHIDProductKey, device: device) ?? kind.label
        let manufacturer = stringProperty(kIOHIDManufacturerKey, device: device)
        let name: String
        if let manufacturer, !product.localizedCaseInsensitiveContains(manufacturer) {
            name = manufacturer + " " + product
        } else {
            name = product
        }
        let service = IOHIDDeviceGetService(device)
        var registryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &registryID)

        return DeviceDescriptor(
            id: "hid-\(registryID)",
            name: name,
            kind: kind,
            isConnected: true,
            capabilities: capabilities
        )
    }

    private func integerProperty(_ key: String, device: IOHIDDevice) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    private func stringProperty(_ key: String, device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }
}
