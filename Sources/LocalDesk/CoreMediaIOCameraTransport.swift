import Foundation
import CoreMediaIO
import CoreAudio
import LocalDeskCore

enum CoreMediaIOError: LocalizedError {
    case deviceNotFound
    case controlNotFound
    case propertyUnavailable(String)
    case readFailed(OSStatus)
    case writeFailed(OSStatus)
    case readOnly

    var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "CoreMediaIO 找不到这台摄像头。"
        case .controlNotFound: return "找不到这个摄像头控制项。"
        case .propertyUnavailable(let property): return "摄像头没有提供可用的\(property)属性。"
        case .readFailed(let status): return "读取摄像头参数失败（OSStatus \(status)）。"
        case .writeFailed(let status): return "写入摄像头参数失败（OSStatus \(status)）。"
        case .readOnly: return "这个摄像头参数是只读的。"
        }
    }
}

final class CoreMediaIOCameraTransport: CameraControlTransport {
    private struct ControlRecord {
        let objectID: CMIOObjectID
        let valueSelector: CMIOObjectPropertySelector
        let rawRange: ControlValueRange
        let isWritable: Bool
    }

    private var records: [String: ControlRecord] = [:]

    func controls(for deviceID: String) throws -> [CameraControlDescriptor] {
        guard let cmioDeviceID = try matchingDeviceID(for: deviceID) else {
            throw CoreMediaIOError.deviceNotFound
        }

        let objectIDs = try ownedObjects(of: cmioDeviceID, qualifierClassID: CMIOClassID(kCMIOControlClassID))
        var descriptors: [CameraControlDescriptor] = []

        for objectID in objectIDs {
            guard let capability = capability(for: try classID(of: objectID)),
                  let valueProperty = try valueProperty(for: objectID) else {
                continue
            }

            let currentRawValue = try floatValue(objectID: objectID, selector: valueProperty.valueSelector)
            let rawRange = try rangeValue(objectID: objectID, selector: valueProperty.rangeSelector)
            let range = ControlValueRange(minimum: rawRange.minimum, maximum: rawRange.maximum)
            let controlID = String(objectID)
            let writable = try isSettable(objectID: objectID, selector: valueProperty.valueSelector)
            let name = (try? stringValue(objectID: objectID, selector: CMIOObjectPropertySelector(kCMIOObjectPropertyName))) ?? capability.label
            let automatic = hasProperty(objectID: objectID, selector: CMIOObjectPropertySelector(kCMIOFeatureControlPropertyAutomaticManual))

            records[recordKey(deviceID: deviceID, controlID: controlID)] = ControlRecord(
                objectID: objectID,
                valueSelector: valueProperty.valueSelector,
                rawRange: range,
                isWritable: writable
            )

            descriptors.append(CameraControlDescriptor(
                id: controlID,
                capability: capability,
                displayName: name,
                currentValue: range.normalized(currentRawValue),
                supportsAutomaticMode: automatic,
                isWritable: writable
            ))
        }

        return descriptors.sorted { $0.capability.rawValue < $1.capability.rawValue }
    }

    func readValue(controlID: String, deviceID: String) throws -> Double {
        let record = try record(controlID: controlID, deviceID: deviceID)
        let rawValue = try floatValue(objectID: record.objectID, selector: record.valueSelector)
        return record.rawRange.normalized(rawValue)
    }

    @discardableResult
    func writeValue(_ value: Double, controlID: String, deviceID: String) throws -> Double {
        let record = try record(controlID: controlID, deviceID: deviceID)
        guard record.isWritable else { throw CoreMediaIOError.readOnly }

        var rawValue = Float32(record.rawRange.rawValue(fromNormalized: value))
        var address = propertyAddress(record.valueSelector)
        let status = withUnsafePointer(to: &rawValue) { pointer in
            CMIOObjectSetPropertyData(
                record.objectID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Float32>.size),
                pointer
            )
        }
        guard status == noErr else { throw CoreMediaIOError.writeFailed(status) }
        return try readValue(controlID: controlID, deviceID: deviceID)
    }

    private func record(controlID: String, deviceID: String) throws -> ControlRecord {
        if let record = records[recordKey(deviceID: deviceID, controlID: controlID)] {
            return record
        }
        _ = try controls(for: deviceID)
        guard let record = records[recordKey(deviceID: deviceID, controlID: controlID)] else {
            throw CoreMediaIOError.controlNotFound
        }
        return record
    }

    private func recordKey(deviceID: String, controlID: String) -> String {
        "\(deviceID)::\(controlID)"
    }

    private func matchingDeviceID(for uid: String) throws -> CMIOObjectID? {
        for deviceID in try hardwareDeviceIDs() {
            if try stringValue(objectID: deviceID, selector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID)) == uid {
                return deviceID
            }
        }
        return nil
    }

    private func hardwareDeviceIDs() throws -> [CMIOObjectID] {
        var address = propertyAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let size = try propertyDataSize(objectID: CMIOObjectID(kCMIOObjectSystemObject), address: &address)
        guard size > 0 else { return [] }

        var values = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        let status = values.withUnsafeMutableBytes { bytes in
            CMIOObjectGetPropertyData(
                CMIOObjectID(kCMIOObjectSystemObject),
                &address,
                0,
                nil,
                size,
                &used,
                bytes.baseAddress
            )
        }
        guard status == noErr else { throw CoreMediaIOError.readFailed(status) }
        return Array(values.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    private func ownedObjects(of objectID: CMIOObjectID, qualifierClassID: CMIOClassID) throws -> [CMIOObjectID] {
        var address = propertyAddress(CMIOObjectPropertySelector(kCMIOObjectPropertyOwnedObjects))
        var qualifier = qualifierClassID
        var size: UInt32 = 0
        let sizeStatus = withUnsafePointer(to: &qualifier) { pointer in
            CMIOObjectGetPropertyDataSize(
                objectID,
                &address,
                UInt32(MemoryLayout<CMIOClassID>.size),
                pointer,
                &size
            )
        }
        guard sizeStatus == noErr else { throw CoreMediaIOError.readFailed(sizeStatus) }
        guard size > 0 else { return [] }

        var values = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        let status = withUnsafePointer(to: &qualifier) { qualifierPointer in
            values.withUnsafeMutableBytes { bytes in
                CMIOObjectGetPropertyData(
                    objectID,
                    &address,
                    UInt32(MemoryLayout<CMIOClassID>.size),
                    qualifierPointer,
                    size,
                    &used,
                    bytes.baseAddress
                )
            }
        }
        guard status == noErr else { throw CoreMediaIOError.readFailed(status) }
        return Array(values.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    private func classID(of objectID: CMIOObjectID) throws -> CMIOClassID {
        var address = propertyAddress(CMIOObjectPropertySelector(kCMIOObjectPropertyClass))
        var value: CMIOClassID = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<CMIOClassID>.size),
            &used,
            &value
        )
        guard status == noErr else { throw CoreMediaIOError.readFailed(status) }
        return value
    }

    private func capability(for classID: CMIOClassID) -> DeviceCapability? {
        switch classID {
        case CMIOClassID(kCMIOBrightnessControlClassID): return .brightness
        case CMIOClassID(kCMIOContrastControlClassID): return .contrast
        case CMIOClassID(kCMIOSaturationControlClassID): return .saturation
        case CMIOClassID(kCMIOSharpnessControlClassID): return .sharpness
        case CMIOClassID(kCMIOExposureControlClassID): return .exposure
        case CMIOClassID(kCMIOFocusControlClassID): return .focus
        case CMIOClassID(kCMIOWhiteBalanceControlClassID): return .whiteBalance
        default: return nil
        }
    }

    private func valueProperty(for objectID: CMIOObjectID) throws -> (valueSelector: CMIOObjectPropertySelector, rangeSelector: CMIOObjectPropertySelector)? {
        let absoluteValue = CMIOObjectPropertySelector(kCMIOFeatureControlPropertyAbsoluteValue)
        let absoluteRange = CMIOObjectPropertySelector(kCMIOFeatureControlPropertyAbsoluteRange)
        if hasProperty(objectID: objectID, selector: absoluteValue), hasProperty(objectID: objectID, selector: absoluteRange) {
            return (absoluteValue, absoluteRange)
        }

        let nativeValue = CMIOObjectPropertySelector(kCMIOFeatureControlPropertyNativeValue)
        let nativeRange = CMIOObjectPropertySelector(kCMIOFeatureControlPropertyNativeRange)
        if hasProperty(objectID: objectID, selector: nativeValue), hasProperty(objectID: objectID, selector: nativeRange) {
            return (nativeValue, nativeRange)
        }
        return nil
    }

    private func floatValue(objectID: CMIOObjectID, selector: CMIOObjectPropertySelector) throws -> Double {
        var address = propertyAddress(selector)
        var value: Float32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &used,
            &value
        )
        guard status == noErr else { throw CoreMediaIOError.readFailed(status) }
        return Double(value)
    }

    private func rangeValue(objectID: CMIOObjectID, selector: CMIOObjectPropertySelector) throws -> ControlValueRange {
        var address = propertyAddress(selector)
        var value = AudioValueRange(mMinimum: 0, mMaximum: 1)
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioValueRange>.size),
            &used,
            &value
        )
        guard status == noErr else { throw CoreMediaIOError.readFailed(status) }
        return ControlValueRange(minimum: value.mMinimum, maximum: value.mMaximum)
    }

    private func stringValue(objectID: CMIOObjectID, selector: CMIOObjectPropertySelector) throws -> String {
        var address = propertyAddress(selector)
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout.size(ofValue: value)),
            &used,
            &value
        )
        guard status == noErr, let string = value?.takeUnretainedValue() else {
            throw CoreMediaIOError.readFailed(status)
        }
        return string as String
    }

    private func isSettable(objectID: CMIOObjectID, selector: CMIOObjectPropertySelector) throws -> Bool {
        var address = propertyAddress(selector)
        var settable = DarwinBoolean(false)
        let status = CMIOObjectIsPropertySettable(objectID, &address, &settable)
        guard status == noErr else { throw CoreMediaIOError.readFailed(status) }
        return settable.boolValue
    }

    private func hasProperty(objectID: CMIOObjectID, selector: CMIOObjectPropertySelector) -> Bool {
        var address = propertyAddress(selector)
        return CMIOObjectHasProperty(objectID, &address)
    }

    private func propertyDataSize(objectID: CMIOObjectID, address: inout CMIOObjectPropertyAddress) throws -> UInt32 {
        var size: UInt32 = 0
        let status = CMIOObjectGetPropertyDataSize(objectID, &address, 0, nil, &size)
        guard status == noErr else { throw CoreMediaIOError.readFailed(status) }
        return size
    }

    private func propertyAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }
}
