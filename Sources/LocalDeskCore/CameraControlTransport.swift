import Foundation

public protocol CameraControlTransport {
    func controls(for deviceID: String) throws -> [CameraControlDescriptor]
    func readValue(controlID: String, deviceID: String) throws -> Double
    @discardableResult
    func writeValue(_ value: Double, controlID: String, deviceID: String) throws -> Double
}
