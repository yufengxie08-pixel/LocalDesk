import AVFoundation
import LocalDeskCore

enum CameraManagerError: LocalizedError {
    case deviceNotFound
    case unsupported(String)
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "找不到指定摄像头。"
        case .unsupported(let capability): return "摄像头不支持：\(capability)"
        case .configurationFailed: return "摄像头参数应用失败。"
        }
    }
}

@MainActor
final class CameraManager: ObservableObject {
    @Published private(set) var descriptors: [DeviceDescriptor] = []
    @Published private(set) var controlsByDeviceID: [String: [CameraControlDescriptor]] = [:]
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    private var cameras: [String: AVCaptureDevice] = [:]
    private let transport: any CameraControlTransport

    init(transport: any CameraControlTransport = CoreMediaIOCameraTransport()) {
        self.transport = transport
    }

    func requestAccess() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if granted {
            rescan()
        }
        return granted
    }

    func rescan() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard authorizationStatus == .authorized else {
            descriptors = []
            cameras = [:]
            controlsByDeviceID = [:]
            return
        }

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )

        var nextCameras: [String: AVCaptureDevice] = [:]
        var nextControls: [String: [CameraControlDescriptor]] = [:]
        let nextDescriptors = session.devices.map { device -> DeviceDescriptor in
            let id = device.uniqueID
            nextCameras[id] = device
            let controls: [CameraControlDescriptor]
            let errorMessage: String?
            do {
                controls = try transport.controls(for: id)
                errorMessage = nil
            } catch CoreMediaIOError.deviceNotFound {
                controls = []
                errorMessage = nil
            } catch {
                controls = []
                errorMessage = error.localizedDescription
            }
            nextControls[id] = controls

            return DeviceDescriptor(
                id: id,
                name: device.localizedName,
                kind: .camera,
                isConnected: true,
                capabilities: Set(controls.map(\.capability)),
                lastError: errorMessage
            )
        }

        cameras = nextCameras
        controlsByDeviceID = nextControls
        descriptors = nextDescriptors
    }

    func controls(for deviceID: String) -> [CameraControlDescriptor] {
        controlsByDeviceID[deviceID] ?? []
    }

    @discardableResult
    func setControl(_ value: Double, controlID: String, deviceID: String) throws -> Double {
        guard cameras[deviceID] != nil else { throw CameraManagerError.deviceNotFound }
        let confirmedValue = try transport.writeValue(value, controlID: controlID, deviceID: deviceID)
        guard let index = controlsByDeviceID[deviceID]?.firstIndex(where: { $0.id == controlID }) else {
            return confirmedValue
        }
        controlsByDeviceID[deviceID]?[index].currentValue = confirmedValue
        return confirmedValue
    }

    func apply(_ configuration: CameraConfiguration, to deviceID: String) throws {
        guard cameras[deviceID] != nil else {
            throw CameraManagerError.deviceNotFound
        }

        let values: [(DeviceCapability, Double?)] = [
            (.brightness, configuration.brightness),
            (.contrast, configuration.contrast),
            (.saturation, configuration.saturation),
            (.sharpness, configuration.sharpness),
            (.exposure, configuration.exposure),
            (.focus, configuration.focus),
            (.whiteBalance, configuration.whiteBalance)
        ]

        for (capability, value) in values {
            guard let value else { continue }
            guard let control = controls(for: deviceID).first(where: { $0.capability == capability }) else {
                throw CameraManagerError.unsupported(capability.label)
            }
            try setControl(value, controlID: control.id, deviceID: deviceID)
        }
    }
}
