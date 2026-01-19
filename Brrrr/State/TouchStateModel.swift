//
//  TouchStateModel.swift
//  Brrrr
//

import AppKit
import Combine
import Darwin
import Foundation

@MainActor
final class TouchStateModel: ObservableObject {
	@Published private(set) var touchState: TouchState = .noTouch
	@Published private(set) var statusText: String = "Not started"
	@Published private(set) var flashPulse: Int = 0
	@Published private(set) var previewImage: CGImage?
	@Published private(set) var lastDetections: VisionDetections?
	@Published private(set) var measuredFPS: Double = 0
	@Published private(set) var cpuPercent: Double = 0
	@Published private(set) var isPaused: Bool = false
	@Published private(set) var pauseRemainingSeconds: Int = 0
	@Published private(set) var hasUserStartedMonitoring: Bool = false

	lazy var cameraManager = CameraManager()

	private lazy var visionPipeline = VisionPipeline()
	private let classifier = TouchClassifier()
	private let alertCoordinator = AlertCoordinator()

	private var lastOutput: TouchClassifierOutput?
	private var storedSettings = AppSettings.default
	private var isPipelineConfigured = false
	private var lastFrameTime: Double?
	private var cpuTask: Task<Void, Never>?
	private var resumeTask: Task<Void, Never>?
	private var pauseCountdownTask: Task<Void, Never>?
	private var pauseUntilUptime: TimeInterval?
	private lazy var settingsWindowController = SettingsWindowController(model: self)
	private var sleepObservers: [NSObjectProtocol] = []

	init() {
		hasUserStartedMonitoring = UserDefaults.standard.bool(forKey: AppSettingsKey.hasUserStartedMonitoring)
		if hasUserStartedMonitoring {
			statusText = "Vision: starting…"
		}
		applyStoredSettings()
		observeSleepEvents()
	}

	deinit {
		for observer in sleepObservers {
			NotificationCenter.default.removeObserver(observer)
		}
	}

	private nonisolated func observeSleepEvents() {
		let workspace = NSWorkspace.shared
		let nc = workspace.notificationCenter

		// Pause when system sleeps (closing lid, menu bar sleep, etc.)
		let sleepObserver = nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor [weak self] in
				self?.pauseOnSleep()
			}
		}

		// Pause when screen locks (⌘+Ctrl+Q or screensaver)
		let screenSleepObserver = nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor [weak self] in
				self?.pauseOnSleep()
			}
		}

		Task { @MainActor [weak self] in
			self?.sleepObservers = [sleepObserver, screenSleepObserver]
		}
	}

	private func pauseOnSleep() {
		guard hasUserStartedMonitoring, !isPaused else { return }
		pauseMonitoring()
	}

	func userStartMonitoring() {
		guard !hasUserStartedMonitoring else {
			startMonitoring()
			return
		}
		UserDefaults.standard.set(true, forKey: AppSettingsKey.hasUserStartedMonitoring)
		hasUserStartedMonitoring = true
		statusText = "Vision: starting…"
		startMonitoring()
	}

	func startMonitoring() {
		hasUserStartedMonitoring = true
		isPaused = false

		// Apply persisted settings (camera selection, vision FPS) at start time.
		let selectedCameraID = UserDefaults.standard.string(forKey: AppSettingsKey.selectedCameraID) ?? ""
		if !selectedCameraID.isEmpty {
			cameraManager.setSelectedDevice(uniqueID: selectedCameraID)
		}

		visionPipeline.maxFPS = max(0, storedSettings.maxVisionFPS)
		configurePipelineIfNeeded()

		cameraManager.setVideoSampleBufferDelegate(visionPipeline)
		cameraManager.start()
		startCPUUsageMonitoring()
	}

	func stopMonitoring() {
		cpuTask?.cancel()
		cpuTask = nil
		resumeTask?.cancel()
		resumeTask = nil
		pauseCountdownTask?.cancel()
		pauseCountdownTask = nil
		pauseUntilUptime = nil
		pauseRemainingSeconds = 0
		cameraManager.stop()
		cameraManager.setVideoSampleBufferDelegate(nil)
	}

	func pauseMonitoring() {
		guard !isPaused else { return }
		isPaused = true
		stopMonitoring()
		statusText = "Paused"
	}

	func resumeMonitoring() {
		guard isPaused else { return }
		resumeTask?.cancel()
		resumeTask = nil
		pauseCountdownTask?.cancel()
		pauseCountdownTask = nil
		pauseUntilUptime = nil
		pauseRemainingSeconds = 0
		isPaused = false
		startMonitoring()
	}

	func togglePause() {
		if isPaused {
			resumeMonitoring()
		} else {
			pauseMonitoring()
		}
	}

	func pauseFor(minutes: Double) {
		let seconds = max(0, minutes) * 60
		guard seconds > 0 else {
			pauseMonitoring()
			return
		}

		isPaused = true
		stopMonitoring()
		statusText = "Paused"

		let now = ProcessInfo.processInfo.systemUptime
		pauseUntilUptime = now + seconds
		pauseRemainingSeconds = Int(ceil(seconds))

		resumeTask?.cancel()
		resumeTask = Task { @MainActor [weak self] in
			try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
			self?.resumeMonitoring()
		}

		startPauseCountdown()
	}

	// MARK: - Settings hooks (wired up later in SettingsView)

	func setAlertMode(_ mode: AlertMode) {
		alertCoordinator.mode = mode
	}

	func setSoundCooldownSeconds(_ seconds: TimeInterval) {
		alertCoordinator.cooldownSeconds = max(0, seconds)
	}

	func setAlertSoundPath(_ path: String) {
		let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.isEmpty {
			alertCoordinator.soundURL = nil
		} else {
			alertCoordinator.soundURL = URL(fileURLWithPath: trimmed)
		}
	}

	func setAlertSoundVolume(_ volume: Double) {
		alertCoordinator.soundVolume = max(0, min(1, volume))
	}

	func setFlashColor(red: Double, green: Double, blue: Double) {
		let r = max(0, min(1, red))
		let g = max(0, min(1, green))
		let b = max(0, min(1, blue))
		alertCoordinator.flashColor = NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
	}

	func setFlashOpacity(_ opacity: Double) {
		alertCoordinator.flashOpacity = max(0, min(1, opacity))
	}

	func setPreviewStyle(_ style: PreviewStyle) {
		visionPipeline.previewStyle = style
	}

	func testAlert() {
		alertCoordinator.triggerIfAllowed(ignoreCooldown: true)
	}

	func showSettingsWindow() {
		settingsWindowController.show()
	}

	func setMaxVisionFPS(_ fps: Double) {
		storedSettings.maxVisionFPS = max(0, fps)
		if isPipelineConfigured {
			visionPipeline.maxFPS = storedSettings.maxVisionFPS
		}
	}

	// MARK: - Private

	private func applyStoredSettings() {
		let settings = AppSettings.load()
		storedSettings = settings

		setSoundCooldownSeconds(settings.soundCooldownSeconds)
		setAlertMode(AlertMode(rawValue: settings.alertModeRaw) ?? .soundAndScreen)
		setAlertSoundPath(settings.alertSoundPath)
		setAlertSoundVolume(settings.alertSoundVolume)
		setFlashColor(red: settings.flashColorRed, green: settings.flashColorGreen, blue: settings.flashColorBlue)
		setFlashOpacity(settings.flashOpacity)
		setPreviewStyle(PreviewStyle(rawValue: settings.previewStyleRaw) ?? .dots)
		// Vision FPS + camera selection are applied when monitoring starts to avoid hardware/vision setup at init time.
	}

	private func configurePipelineIfNeeded() {
		guard !isPipelineConfigured else { return }

		visionPipeline.onDetections = { [weak self] detections in
			Task { @MainActor [weak self] in
				guard let self else { return }
				self.handleDetections(detections)
			}
		}

		visionPipeline.onPreviewFrame = { [weak self] cgImage in
			Task { @MainActor [weak self] in
				self?.previewImage = cgImage
			}
		}

		isPipelineConfigured = true
	}

	private func handleDetections(_ detections: VisionDetections) {
		lastDetections = detections

		if let last = lastFrameTime {
			let dt = detections.timestamp - last
			if dt > 0 {
				let fps = 1.0 / dt
				// Light smoothing to avoid jitter in the UI.
				measuredFPS = (measuredFPS == 0) ? fps : (measuredFPS * 0.8 + fps * 0.2)
			}
		}
		lastFrameTime = detections.timestamp

		let output = classifier.update(with: detections)
		lastOutput = output

		touchState = output.state

		let stateText: String = switch output.state {
		case .noTouch: "No touch"
		case .maybeTouch: "Maybe"
		case .touching: "Touching"
		}

		if let d = output.minDistanceToFaceNormalized {
			let dString = String(format: "%.3f", d)
			statusText = "Faces: \(detections.faces.count)  Hands: \(detections.hands.count)  •  \(stateText)  •  d=\(dString)"
		} else {
			statusText = "Faces: \(detections.faces.count)  Hands: \(detections.hands.count)  •  \(stateText)"
		}

		if output.state == .touching {
			let didTrigger = alertCoordinator.triggerIfAllowed()
			if didTrigger { flashPulse &+= 1 }
		}
	}

	private func startCPUUsageMonitoring() {
		cpuTask?.cancel()
		cpuTask = Task { @MainActor [weak self] in
			guard let self else { return }

			var lastWall = ProcessInfo.processInfo.systemUptime
			var lastCPU = Self.currentProcessCPUSeconds()

			while !Task.isCancelled {
				try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

				let nowWall = ProcessInfo.processInfo.systemUptime
				let nowCPU = Self.currentProcessCPUSeconds()
				let dWall = nowWall - lastWall
				let dCPU = nowCPU - lastCPU

				lastWall = nowWall
				lastCPU = nowCPU

				guard dWall > 0 else { continue }

				let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
				let pct = (dCPU / (dWall * Double(cores))) * 100
				self.cpuPercent = max(0, min(100, pct))
			}
		}
	}

	private static func currentProcessCPUSeconds() -> Double {
		var usage = rusage()
		_ = getrusage(RUSAGE_SELF, &usage)

		let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000.0
		let sys = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000.0
		return user + sys
	}

	private func startPauseCountdown() {
		pauseCountdownTask?.cancel()

		guard isPaused, pauseUntilUptime != nil else { return }

		pauseCountdownTask = Task { @MainActor [weak self] in
			guard let self else { return }

			while !Task.isCancelled, self.isPaused, let until = self.pauseUntilUptime {
				let now = ProcessInfo.processInfo.systemUptime
				let remaining = max(0, Int(ceil(until - now)))
				self.pauseRemainingSeconds = remaining
				if remaining <= 0 {
					break
				}
				try? await Task.sleep(nanoseconds: 1_000_000_000)
			}
		}
	}
}

