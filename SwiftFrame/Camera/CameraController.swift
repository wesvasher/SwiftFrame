@preconcurrency import AVFoundation
import CoreImage
import AppKit

struct CameraDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

/// One camera feed for one capture window. Every window has its own, so
/// several windows can watch the same camera or different ones.
@MainActor
final class CameraController: NSObject, ObservableObject {
    enum Status: Equatable {
        case starting, running, denied, noCamera
        case failed(String)
    }

    @Published private(set) var devices: [CameraDevice] = []
    @Published private(set) var status: Status = .starting
    @Published private(set) var deviceID: String?

    nonisolated let session = AVCaptureSession()
    private nonisolated let output = AVCaptureVideoDataOutput()
    private nonisolated let queue = DispatchQueue(label: "com.wesvasher.swiftframe.camera")
    private nonisolated let latest = LatestFrame()
    private nonisolated let ciContext = CIContext()
    private nonisolated let peakingRequest = PeakingRequest()
    /// Focus peaking pictures for the live view, while it's asked for.
    let peakingFeed = PeakingFeed()
    private var watchers: [Task<Void, Never>] = []

    override init() {
        super.init()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
    }

    /// Asks for camera access if needed and starts the preferred camera (or
    /// the first one).
    func start(preferring id: String?) async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { status = .denied; return }
        default:
            status = .denied
            return
        }
        refreshDevices()
        watchDevices()
        let pick = devices.first { $0.id == id } ?? devices.first
        select(pick?.id)
    }

    func stop() {
        watchers.forEach { $0.cancel() }
        watchers = []
        let session = session
        queue.async { session.stopRunning() }
    }

    func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video, position: .unspecified)
        devices = discovery.devices.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    func select(_ id: String?) {
        guard let id else {
            deviceID = nil
            status = .noCamera
            return
        }
        deviceID = id
        status = .starting
        let session = session, output = output
        queue.async { [weak self] in
            let result = Self.configure(session: session, output: output, deviceID: id)
            Task { @MainActor in
                guard let self, self.deviceID == id else { return }
                self.status = result
            }
        }
    }

    private nonisolated static func configure(session: AVCaptureSession, output: AVCaptureVideoDataOutput,
                                              deviceID: String) -> Status {
        guard let device = AVCaptureDevice(uniqueID: deviceID) else { return .noCamera }
        session.beginConfiguration()
        for input in session.inputs { session.removeInput(input) }
        let result: Status
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
            if session.canAddInput(input) { session.addInput(input) }
            if !session.outputs.contains(output), session.canAddOutput(output) { session.addOutput(output) }
            result = .running
        } catch {
            result = .failed(error.localizedDescription)
        }
        session.commitConfiguration()
        if result == .running, !session.isRunning { session.startRunning() }
        return result
    }

    private func watchDevices() {
        guard watchers.isEmpty else { return }
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            watchers.append(Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name).map({ _ in () }) {
                    guard let self else { return }
                    self.refreshDevices()
                    if let id = self.deviceID, !self.devices.contains(where: { $0.id == id }) {
                        self.select(self.devices.first?.id)
                    } else if self.deviceID == nil, let first = self.devices.first {
                        self.select(first.id)
                    }
                }
            })
        }
    }

    /// Starts or stops working out focus peaking pictures (nil stops it).
    func setFocusPeaking(_ peaking: FocusPeaking?) {
        let on = peaking?.isOn == true
        peakingRequest.set(on ? peaking : nil)
        if !on { peakingFeed.image = nil }
    }

    fileprivate func receivePeaking(_ image: CGImage?, generation: Int) {
        guard peakingRequest.isCurrent(generation) else { return }
        peakingFeed.image = image
    }

    /// The newest camera picture, mirrored if asked.
    func captureStill(mirrored: Bool) -> CGImage? {
        guard let buffer = latest.buffer else { return nil }
        var image = CIImage(cvPixelBuffer: buffer)
        if mirrored { image = image.oriented(.upMirrored) }
        return ciContext.createCGImage(image, from: image.extent)
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latest.buffer = buffer
        guard let (peaking, generation) = peakingRequest.due(at: CACurrentMediaTime()) else { return }
        let image = UncheckedImage(peaking.overlay(for: buffer, context: ciContext))
        Task { @MainActor [weak self] in
            self?.receivePeaking(image.image, generation: generation)
        }
    }
}

/// The newest pixel buffer, shared between the camera queue and the main thread.
private final class LatestFrame: @unchecked Sendable {
    private let lock = NSLock()
    private var _buffer: CVPixelBuffer?
    var buffer: CVPixelBuffer? {
        get { lock.withLock { _buffer } }
        set { lock.withLock { _buffer = newValue } }
    }
}

/// What focus peaking the camera queue should work out, and when it last did,
/// so it runs about 15 times a second rather than for every camera frame.
private final class PeakingRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var peaking: FocusPeaking?
    private var generation = 0
    private var last: CFTimeInterval = 0
    private let interval: CFTimeInterval = 1.0 / 15

    @discardableResult
    func set(_ peaking: FocusPeaking?) -> Int {
        lock.withLock {
            self.peaking = peaking
            generation += 1
            last = 0
            return generation
        }
    }

    func isCurrent(_ generation: Int) -> Bool {
        lock.withLock { peaking != nil && generation == self.generation }
    }

    func due(at time: CFTimeInterval) -> (FocusPeaking, Int)? {
        lock.withLock {
            guard let peaking, time - last >= interval else { return nil }
            last = time
            return (peaking, generation)
        }
    }
}

/// A finished picture handed from the camera queue to the main actor.
private struct UncheckedImage: @unchecked Sendable {
    let image: CGImage?
    init(_ image: CGImage?) { self.image = image }
}
