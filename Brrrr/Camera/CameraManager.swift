//
//  CameraManager.swift
//  Brrrr
//
//  Camera-only capture manager (no microphone).
//

import AVFoundation
import Combine
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
			selectedDeviceUniqueID = AVCaptureDevice.default(for: .video)?.uniqueID ?? availableVideoDevices.first?.uniqueID
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
		if #available(macOS 14.0, *) {
			if AVCaptureDevice.centerStageControlMode != .user {
				AVCaptureDevice.isCenterStageEnabled = false
			}
		}

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
	private let videoOutputQueue = DispatchQueue(label: "CameraSessionController.videoOutputQueue")
	private var videoDataOutput: AVCaptureVideoDataOutput?
	private var videoSampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?

	func startRunning(selectedDeviceUniqueID: String?, onErrorChanged: @escaping (String?) -> Void) {
		sessionQueue.async { [weak self] in
			guard let self else { return }

			self.session.beginConfiguration()
			self.session.sessionPreset = .high
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
		if #available(macOS 14.0, *) {
			deviceTypes = [.builtInWideAngleCamera, .external]
		} else {
			deviceTypes = [.builtInWideAngleCamera, .externalUnknown]
		}
		let discovery = AVCaptureDevice.DiscoverySession(
			deviceTypes: deviceTypes,
			mediaType: .video,
			position: .unspecified
		)
		return discovery.devices
	}

	static func resolveSelectedDevice(uniqueID: String?) -> AVCaptureDevice? {
		let devices = discoverVideoDevices()
		if let uniqueID, let device = devices.first(where: { $0.uniqueID == uniqueID }) {
			return device
		}
		return AVCaptureDevice.default(for: .video) ?? devices.first
	}

	// MARK: - Configuration

	private func configureVideoOutputIfNeeded() {
		if videoDataOutput == nil {
			let output = AVCaptureVideoDataOutput()
			output.alwaysDiscardsLateVideoFrames = true
			output.videoSettings = [
				kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
			]

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

