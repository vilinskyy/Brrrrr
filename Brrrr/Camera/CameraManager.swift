//
//  CameraManager.swift
//  Brrrr
//
//  Camera-only capture manager (no microphone).
//

import AVFoundation
import Combine
import CoreGraphics
import Foundation

@MainActor
final class CameraManager: NSObject, ObservableObject {
	enum AuthorizationState: Equatable {
		case notDetermined
		case authorized
		case denied
		case restricted
	}

	@Published private(set) var authorizationState: AuthorizationState
	@Published private(set) var availableVideoDevices: [AVCaptureDevice] = []
	@Published private(set) var selectedDeviceUniqueID: String?
	@Published private(set) var lastError: String?

	private let sessionController = CameraSessionController()

	var session: AVCaptureSession { sessionController.session }

	/// Attach a video sample buffer delegate (camera frames only).
	/// Note: The delegate is called on an internal serial queue, never on the main thread.
	func setVideoSampleBufferDelegate(_ delegate: AVCaptureVideoDataOutputSampleBufferDelegate?) {
		sessionController.setVideoSampleBufferDelegate(delegate)
	}

	override init() {
		let status = AVCaptureDevice.authorizationStatus(for: .video)
		switch status {
		case .authorized:
			authorizationState = .authorized
		case .notDetermined:
			authorizationState = .notDetermined
		case .denied:
			authorizationState = .denied
		case .restricted:
			authorizationState = .restricted
		@unknown default:
			authorizationState = .denied
		}

		super.init()
		refreshAvailableDevices()
	}

	func refreshAvailableDevices() {
		let devices = CameraSessionController.discoverVideoDevices()
		availableVideoDevices = devices.sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
		if selectedDeviceUniqueID == nil {
			#if os(iOS)
			selectedDeviceUniqueID = CameraSessionController.resolveSelectedDevice(uniqueID: nil)?.uniqueID
			#else
			selectedDeviceUniqueID = AVCaptureDevice.default(for: .video)?.uniqueID ?? availableVideoDevices.first?.uniqueID
			#endif
		}
	}

	func setSelectedDevice(uniqueID: String?) {
		selectedDeviceUniqueID = uniqueID

		guard authorizationState == .authorized else { return }
		sessionController.setDevice(
			uniqueID: uniqueID,
			onErrorChanged: { [weak self] errorMessage in
				Task { @MainActor in
					self?.lastError = errorMessage
				}
			}
		)
	}

	func start() {
		lastError = nil

		// Reduce noise from system camera effects.
		//
		// Important: This is a global toggle. When Center Stage is in user-control mode,
		// attempting to set it throws an Obj-C exception (crashes the app).
		#if os(macOS)
		if #available(macOS 14.0, *) {
			if AVCaptureDevice.centerStageControlMode != .user {
				AVCaptureDevice.isCenterStageEnabled = false
			}
		}
		#endif

		switch authorizationState {
		case .authorized:
			refreshAvailableDevices()
			sessionController.startRunning(
				selectedDeviceUniqueID: selectedDeviceUniqueID,
				onErrorChanged: { [weak self] errorMessage in
					Task { @MainActor in
						self?.lastError = errorMessage
					}
				}
			)
		case .notDetermined:
			AVCaptureDevice.requestAccess(for: .video) { granted in
				Task { @MainActor [weak self] in
					guard let self else { return }

					self.authorizationState = granted ? .authorized : .denied
					if granted {
						self.refreshAvailableDevices()
						self.sessionController.startRunning(
							selectedDeviceUniqueID: self.selectedDeviceUniqueID,
							onErrorChanged: { [weak self] errorMessage in
								Task { @MainActor in
									self?.lastError = errorMessage
								}
							}
						)
					}
				}
			}
		case .denied, .restricted:
			break
		}
	}

	func stop() {
		sessionController.stopRunning()
	}
}

private final class CameraSessionController {
	let session = AVCaptureSession()

	private let sessionQueue = DispatchQueue(label: "CameraSessionController.sessionQueue")
	private var currentVideoInput: AVCaptureDeviceInput?
	#if os(iOS)
	private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
	#endif
	private let videoOutputQueue = DispatchQueue(label: "CameraSessionController.videoOutputQueue")
	private var videoDataOutput: AVCaptureVideoDataOutput?
	private var videoSampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?

	func startRunning(selectedDeviceUniqueID: String?, onErrorChanged: @escaping (String?) -> Void) {
		sessionQueue.async { [weak self] in
			guard let self else { return }

			self.session.beginConfiguration()
			#if os(iOS)
			// iOS: lower capture resolution to reduce heat/CPU while still being usable for Vision.
			if self.session.canSetSessionPreset(.vga640x480) {
				self.session.sessionPreset = .vga640x480
			} else if self.session.canSetSessionPreset(.hd1280x720) {
				self.session.sessionPreset = .hd1280x720
			} else {
				self.session.sessionPreset = .high
			}
			#else
			self.session.sessionPreset = .high
			#endif
			self.reconfigureVideoInput(selectedDeviceUniqueID: selectedDeviceUniqueID, onErrorChanged: onErrorChanged)
			self.configureVideoOutputIfNeeded()
			self.session.commitConfiguration()

			if !self.session.isRunning {
				self.session.startRunning()
			}
		}
	}

	func stopRunning() {
		sessionQueue.async { [weak self] in
			guard let self else { return }
			if self.session.isRunning {
				self.session.stopRunning()
			}
		}
	}

	func setDevice(uniqueID: String?, onErrorChanged: @escaping (String?) -> Void) {
		sessionQueue.async { [weak self] in
			guard let self else { return }
			self.session.beginConfiguration()
			self.reconfigureVideoInput(selectedDeviceUniqueID: uniqueID, onErrorChanged: onErrorChanged)
			self.configureVideoOutputIfNeeded()
			self.session.commitConfiguration()
		}
	}

	func setVideoSampleBufferDelegate(_ delegate: AVCaptureVideoDataOutputSampleBufferDelegate?) {
		sessionQueue.async { [weak self] in
			guard let self else { return }
			self.videoSampleBufferDelegate = delegate
			self.session.beginConfiguration()
			self.configureVideoOutputIfNeeded()
			self.session.commitConfiguration()
		}
	}

	// MARK: - Discovery

	static func discoverVideoDevices() -> [AVCaptureDevice] {
		let deviceTypes: [AVCaptureDevice.DeviceType]
		#if os(iOS)
		deviceTypes = [
			.builtInWideAngleCamera,
			.builtInTrueDepthCamera,
			.builtInUltraWideCamera,
			.builtInTelephotoCamera,
			.builtInDualCamera,
			.builtInDualWideCamera,
			.builtInTripleCamera,
		]
		#else
		if #available(macOS 14.0, *) {
			deviceTypes = [.builtInWideAngleCamera, .external]
		} else {
			deviceTypes = [.builtInWideAngleCamera]
		}
		#endif
		let discovery = AVCaptureDevice.DiscoverySession(
			deviceTypes: deviceTypes,
			mediaType: .video,
			position: .unspecified
		)
		return discovery.devices
	}

	static func resolveSelectedDevice(uniqueID: String?) -> AVCaptureDevice? {
		let devices = discoverVideoDevices()
		#if os(iOS)
		// iOS app: front camera only (fallback to any camera if a device has no front camera).
		if let uniqueID, let device = devices.first(where: { $0.uniqueID == uniqueID }), device.position == .front {
			return device
		}

		let preferredFrontTypes: [AVCaptureDevice.DeviceType] = [
			.builtInTrueDepthCamera,
			.builtInWideAngleCamera,
		]

		let front =
			devices.first(where: { $0.position == .front && preferredFrontTypes.contains($0.deviceType) })
			?? devices.first(where: { $0.position == .front })

		return front ?? AVCaptureDevice.default(for: .video) ?? devices.first
		#else
		if let uniqueID, let device = devices.first(where: { $0.uniqueID == uniqueID }) {
			return device
		}
		return AVCaptureDevice.default(for: .video) ?? devices.first
		#endif
	}

	// MARK: - Configuration

	private func configureVideoOutputIfNeeded() {
		if videoDataOutput == nil {
			let output = AVCaptureVideoDataOutput()
			output.alwaysDiscardsLateVideoFrames = true
			#if os(iOS)
			// iOS: prefer native YUV buffers to reduce conversion cost.
			output.videoSettings = [
				kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
			]
			#else
			output.videoSettings = [
				kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
			]
			#endif

			guard session.canAddOutput(output) else {
				return
			}
			session.addOutput(output)
			videoDataOutput = output
		}

		guard let videoDataOutput else { return }

		// Keep a strong reference to the delegate (AVCaptureVideoDataOutput keeps it weak).
		if let videoSampleBufferDelegate {
			videoDataOutput.setSampleBufferDelegate(videoSampleBufferDelegate, queue: videoOutputQueue)
		} else {
			videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
		}

		#if os(iOS)
		// Ensure the Vision pipeline receives a consistent orientation in portrait UI.
		if let connection = videoDataOutput.connection(with: .video) {
			if let rotationCoordinator {
				let angle = rotationCoordinator.videoRotationAngleForHorizonLevelCapture
				let snapped = (angle / 90).rounded() * 90
				if connection.isVideoRotationAngleSupported(snapped) {
					connection.videoRotationAngle = snapped
				}
			} else {
				// Fallback: portrait interface.
				let portraitAngle: CGFloat = 90
				if connection.isVideoRotationAngleSupported(portraitAngle) {
					connection.videoRotationAngle = portraitAngle
				}
			}
			// Keep Vision input unmirrored; the UI handles mirroring separately.
			if connection.isVideoMirroringSupported {
				connection.automaticallyAdjustsVideoMirroring = false
				connection.isVideoMirrored = false
			}
		}
		#endif
	}

	private func reconfigureVideoInput(selectedDeviceUniqueID: String?, onErrorChanged: @escaping (String?) -> Void) {
		if let currentVideoInput {
			session.removeInput(currentVideoInput)
			self.currentVideoInput = nil
		}

		guard let device = CameraSessionController.resolveSelectedDevice(uniqueID: selectedDeviceUniqueID) else {
			onErrorChanged("No camera devices found.")
			return
		}

		#if os(iOS)
		rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)

		// Reduce capture FPS to lower power usage. Vision work is throttled separately.
		do {
			try device.lockForConfiguration()
			defer { device.unlockForConfiguration() }

			if let range = device.activeFormat.videoSupportedFrameRateRanges.first {
				let preferredFPS: Double = 15
				let targetFPS = max(range.minFrameRate, min(preferredFPS, range.maxFrameRate))
				let timescale = max(1, Int32(targetFPS.rounded()))
				let duration = CMTime(value: 1, timescale: timescale)
				device.activeVideoMinFrameDuration = duration
				device.activeVideoMaxFrameDuration = duration
			}
		} catch {
			// Best-effort; ignore configuration failures.
		}
		#endif

		do {
			let input = try AVCaptureDeviceInput(device: device)
			guard session.canAddInput(input) else {
				onErrorChanged("Unable to attach the selected camera.")
				return
			}
			session.addInput(input)
			currentVideoInput = input
			onErrorChanged(nil)
		} catch {
			onErrorChanged("Camera input error: \(error.localizedDescription)")
		}
	}
}

