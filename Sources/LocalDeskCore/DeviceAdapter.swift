import Foundation

public protocol DeviceAdapter {
    var descriptor: DeviceDescriptor { get }
    func discover() throws -> DeviceDescriptor
    func connect() throws
    func disconnect()
}

public final class MockDeviceAdapter: DeviceAdapter {
    public private(set) var descriptor: DeviceDescriptor
    public private(set) var isConnected = false

    public init(descriptor: DeviceDescriptor) {
        self.descriptor = descriptor
    }

    public func discover() throws -> DeviceDescriptor {
        descriptor.isConnected = true
        return descriptor
    }

    public func connect() throws {
        isConnected = true
        descriptor.isConnected = true
    }

    public func disconnect() {
        isConnected = false
        descriptor.isConnected = false
    }
}
