//
//  IOSRootView.swift
//  Brrrr
//

#if os(iOS)

import AVFoundation
import SwiftUI
import UIKit

struct IOSRootView: View {
	@EnvironmentObject private var model: TouchStateModel
	@Environment(\.openURL) private var openURL
	@Environment(\.scenePhase) private var scenePhase
	@State private var isSettingsPresented: Bool = false
	@AppStorage(AppSettingsKey.mirrorVideo) private var mirrorVideo: Bool = true
	@AppStorage(AppSettingsKey.previewStyle) private var previewStyleRaw: Int = PreviewStyle.dots.rawValue
	@AppStorage(AppSettingsKey.alertMode) private var alertModeRaw: Int = AlertMode.soundOnly.rawValue
	@AppStorage(AppSettingsKey.flashColorRed) private var flashColorRed: Double = 1.0
	@AppStorage(AppSettingsKey.flashColorGreen) private var flashColorGreen: Double = 0.0
	@AppStorage(AppSettingsKey.flashColorBlue) private var flashColorBlue: Double = 0.0
	@AppStorage(AppSettingsKey.flashOpacity) private var flashOpacity: Double = 0.65
	@State private var flashVisible: Bool = false
	@State private var wasAutoPausedBySystem: Bool = false
	@State private var startTrackingGlow: Bool = false
	@State private var previewMetadataOutputRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
	@State private var previewMetadataToLayerTransform: CGAffineTransform = .identity

	var body: some View {
		ZStack {
			cameraArea
				.ignoresSafeArea()

			VStack(spacing: 8) {
				Spacer()
				bottomPanel
					.padding(.horizontal, 16)
				cameraSeesLabel
					.padding(.horizontal, 16)
			}
			.padding(.bottom, 12)
			.safeAreaPadding(.bottom)
		}
		.onAppear {
			model.cameraManager.refreshAvailableDevices()
			// Front camera only on iPhone.
			model.cameraManager.setSelectedDevice(uniqueID: nil)

			// iPhone default: enable screen flash unless user already chose an alert mode.
			if UserDefaults.standard.object(forKey: AppSettingsKey.alertMode) == nil {
				alertModeRaw = AlertMode.soundAndScreen.rawValue
				model.setAlertMode(.soundAndScreen)
			} else {
				model.setAlertMode(AlertMode(rawValue: alertModeRaw) ?? .soundAndScreen)
			}

			// iPhone default: lower Vision rate to reduce heat unless user already chose a value.
			if UserDefaults.standard.object(forKey: AppSettingsKey.maxVisionFPS) == nil {
				let defaultFPS: Double = 8
				UserDefaults.standard.set(defaultFPS, forKey: AppSettingsKey.maxVisionFPS)
				model.setMaxVisionFPS(defaultFPS)
			}

			// Match mac behavior: don't auto-start on first launch.
			if UserDefaults.standard.bool(forKey: AppSettingsKey.hasUserStartedMonitoring) {
				model.startMonitoring()
			}

			model.refreshTouchStatsIfNeeded()
		}
		.onChange(of: alertModeRaw) { _, newValue in
			model.setAlertMode(AlertMode(rawValue: newValue) ?? .soundAndScreen)
		}
		.onChange(of: model.flashPulse) {
			triggerFlashOverlay()
		}
		.onChange(of: scenePhase) { _, newPhase in
			handleScenePhaseChange(newPhase)
		}
		.sheet(isPresented: $isSettingsPresented) {
			IOSSettingsView()
				.environmentObject(model)
		}
		.overlay {
			if flashVisible {
				Color(
					red: max(0, min(1, flashColorRed)),
					green: max(0, min(1, flashColorGreen)),
					blue: max(0, min(1, flashColorBlue))
				)
				.opacity(max(0, min(1, flashOpacity)))
				.ignoresSafeArea()
				.transition(.opacity)
			}
		}
	}

	private var cameraArea: some View {
		ZStack {
			IOSCameraView(
				session: model.cameraManager.session,
				isMirrored: mirrorVideo,
				metadataOutputRect: $previewMetadataOutputRect,
				metadataToLayerTransform: $previewMetadataToLayerTransform
			)

			if previewStyle == .dots {
				TechnicalDotsOverlayView(
					detections: model.lastDetections,
					metadataOutputRect: previewMetadataOutputRect,
					isMirrored: mirrorVideo,
					metadataToLayerTransform: previewMetadataToLayerTransform
				)
			}

			if let overlay = overlayMessage {
				overlayView(overlay)
					.padding(24)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.background(Color.black.opacity(0.35))
			}
		}
	}

	private var bottomPanel: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Touched Today: \(model.touchesToday)")
				.font(.caption)
				.foregroundStyle(.secondary)
				.monospacedDigit()

			HStack(spacing: 12) {
				startStopTrackingButton
				Button {
					isSettingsPresented = true
				} label: {
					Image(systemName: "gearshape")
						.font(.title3.weight(.semibold))
						.accessibilityLabel("Settings")
						.frame(width: 44, height: 44)
						.background {
							Circle()
								.fill(.thinMaterial)
								.allowsHitTesting(false)
						}
						.overlay {
							Circle()
								.strokeBorder(.white.opacity(0.14), lineWidth: 1)
								.allowsHitTesting(false)
						}
				}
				.buttonStyle(.plain)
				.contentShape(Circle())
			}
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 18, style: .continuous)
				.strokeBorder(.white.opacity(0.12), lineWidth: 1)
		)
	}

	private var cameraSeesLabel: some View {
		Group {
			if model.hasUserStartedMonitoring {
				if let detections = model.lastDetections {
					let hands = detections.hands.count
					let heads = detections.faces.count
					Text("Camera sees: \(hands) \(hands == 1 ? "hand" : "hands"), \(heads) \(heads == 1 ? "head" : "heads")")
						.font(.caption)
						.foregroundStyle(.secondary)
						.monospacedDigit()
				} else {
					Text("Camera sees: —")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			} else {
				EmptyView()
			}
		}
	}

	private var startStopTrackingButton: some View {
		let isTracking = model.hasUserStartedMonitoring && !model.isPaused
		let shouldGlow = !model.hasUserStartedMonitoring
		return Button {
			if isTracking {
				model.pauseMonitoring()
			} else if model.hasUserStartedMonitoring {
				model.resumeMonitoring()
			} else {
				model.userStartMonitoring()
			}
		} label: {
			Text(isTracking ? "Stop Tracking" : "Start Tracking")
				.font(.headline)
				.frame(maxWidth: .infinity)
		}
		.buttonStyle(.plain)
		.padding(.horizontal, 16)
		.padding(.vertical, 12)
		.frame(maxWidth: .infinity)
		.background {
			Capsule()
				.fill(.thinMaterial)
				.allowsHitTesting(false)
		}
		.overlay {
			ZStack {
				Capsule()
					.strokeBorder(.white.opacity(0.14), lineWidth: 1)
					.allowsHitTesting(false)
				if shouldGlow {
					Capsule()
						.stroke(Color.accentColor.opacity(startTrackingGlow ? 0.9 : 0.25), lineWidth: startTrackingGlow ? 8 : 3)
						.blur(radius: startTrackingGlow ? 16 : 6)
						.opacity(startTrackingGlow ? 1.0 : 0.6)
						.animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: startTrackingGlow)
						.allowsHitTesting(false)
						.onAppear {
							startTrackingGlow = true
						}
				}
			}
		}
		.contentShape(Capsule())
	}

	private struct OverlayMessage {
		let title: String
		let detail: String?
		let showsOpenSettings: Bool
	}

	private var overlayMessage: OverlayMessage? {
		if let lastError = model.cameraManager.lastError {
			return OverlayMessage(title: "Camera Error", detail: lastError, showsOpenSettings: false)
		}

		switch model.cameraManager.authorizationState {
		case .authorized:
			break
		case .notDetermined:
			if model.hasUserStartedMonitoring {
				return OverlayMessage(
					title: "Requesting Camera Access…",
					detail: "iOS will ask for camera permission. The video stream stays on-device and is not recorded.",
					showsOpenSettings: false
				)
			}
		case .denied:
			return OverlayMessage(
				title: "Camera Access Denied",
				detail: "Enable camera access for Brrrrr in Settings to continue.",
				showsOpenSettings: true
			)
		case .restricted:
			return OverlayMessage(
				title: "Camera Access Restricted",
				detail: "Camera access is restricted by system policy.",
				showsOpenSettings: true
			)
		}

		if !model.hasUserStartedMonitoring {
			return OverlayMessage(
				title: "Tap Start Tracking to begin",
				detail: "Brrrrr detects hand-to-face touches on-device and alerts you in real time.",
				showsOpenSettings: false
			)
		}

		return nil
	}

	@ViewBuilder
	private func overlayView(_ overlay: OverlayMessage) -> some View {
		VStack(spacing: 12) {
			Text(overlay.title)
				.font(.title3.weight(.semibold))
				.multilineTextAlignment(.center)

			if let detail = overlay.detail {
				Text(detail)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.frame(maxWidth: 420)
			}

			if overlay.showsOpenSettings {
				Button("Open Settings") {
					if let url = URL(string: UIApplication.openSettingsURLString) {
						openURL(url)
					}
				}
				.buttonStyle(.borderedProminent)
			}
		}
		.padding(20)
		.background(.thinMaterial)
		.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
	}

	private var previewStyle: PreviewStyle {
		PreviewStyle(rawValue: previewStyleRaw) ?? .dots
	}

	private func triggerFlashOverlay() {
		withAnimation(.easeOut(duration: 0.02)) {
			flashVisible = true
		}
		Task { @MainActor in
			try? await Task.sleep(nanoseconds: 120_000_000) // 0.12s
			withAnimation(.easeOut(duration: 0.08)) {
				flashVisible = false
			}
		}
	}

	private func handleScenePhaseChange(_ phase: ScenePhase) {
		switch phase {
		case .active:
			model.refreshTouchStatsIfNeeded()
			guard wasAutoPausedBySystem else { return }
			guard model.isPaused, model.pauseRemainingSeconds == 0 else { return }
			wasAutoPausedBySystem = false
			model.resumeMonitoring()
		case .inactive, .background:
			guard model.hasUserStartedMonitoring, !model.isPaused else { return }
			wasAutoPausedBySystem = true
			model.pauseMonitoring()
		@unknown default:
			break
		}
	}
}

private struct IOSSettingsView: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var model: TouchStateModel
	@AppStorage(AppSettingsKey.mirrorVideo) private var mirrorVideo: Bool = true
	@AppStorage(AppSettingsKey.alertMode) private var alertModeRaw: Int = AlertMode.soundAndScreen.rawValue
	@AppStorage(AppSettingsKey.soundCooldownSeconds) private var soundCooldownSeconds: Double = 3
	@AppStorage(AppSettingsKey.maxVisionFPS) private var maxVisionFPS: Double = 12
	@AppStorage(AppSettingsKey.previewStyle) private var previewStyleRaw: Int = PreviewStyle.dots.rawValue
	@AppStorage(AppSettingsKey.flashColorRed) private var flashColorRed: Double = 1.0
	@AppStorage(AppSettingsKey.flashColorGreen) private var flashColorGreen: Double = 0.0
	@AppStorage(AppSettingsKey.flashColorBlue) private var flashColorBlue: Double = 0.0
	@AppStorage(AppSettingsKey.flashOpacity) private var flashOpacity: Double = 0.65

	var body: some View {
		NavigationStack {
			Form {
				Section("Camera") {
					Text("Front camera only")
						.foregroundStyle(.secondary)

					Toggle("Mirror video", isOn: $mirrorVideo)
				}

				Section("Alerts") {
					Picker("Mode", selection: $alertModeRaw) {
						ForEach(AlertMode.allCases) { mode in
							Text(mode.displayName).tag(mode.rawValue)
						}
					}
					.pickerStyle(.segmented)

					Stepper(value: $soundCooldownSeconds, in: 0...30, step: 1) {
						Text("Cooldown: \(Int(soundCooldownSeconds))s")
							.monospacedDigit()
					}

					ColorPicker("Flash color", selection: flashColorBinding)

					HStack {
						Text("Flash opacity")
						Spacer()
						Slider(value: $flashOpacity, in: 0...1)
							.frame(width: 180)
					}

					Button("Test Alert") {
						model.testAlert()
					}
				}

				Section("Processing") {
					HStack {
						Text("Rate")
						Spacer()
						Text("\(Int(maxVisionFPS)) FPS")
							.monospacedDigit()
							.foregroundStyle(.secondary)
					}
					Slider(value: fpsBinding, in: 2...30)

					Picker("Overlay", selection: $previewStyleRaw) {
						ForEach(PreviewStyle.allCases) { style in
							Text(style.displayName).tag(style.rawValue)
						}
					}
				}

				Section("Stats") {
					LabeledContent("Touched Today", value: "\(model.touchesToday)")
				}
			}
			.navigationTitle("Settings")
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button("Done") { dismiss() }
				}
			}
		}
		.onAppear {
			model.cameraManager.refreshAvailableDevices()
			model.cameraManager.setSelectedDevice(uniqueID: nil)
			applyAllSettingsToModel()
		}
		.onChange(of: alertModeRaw) { _, newValue in
			model.setAlertMode(AlertMode(rawValue: newValue) ?? .soundAndScreen)
		}
		.onChange(of: soundCooldownSeconds) { _, newValue in
			model.setSoundCooldownSeconds(newValue)
		}
		.onChange(of: maxVisionFPS) { _, newValue in
			model.setMaxVisionFPS(newValue)
		}
		.onChange(of: previewStyleRaw) { _, newValue in
			model.setPreviewStyle(PreviewStyle(rawValue: newValue) ?? .dots)
		}
		.onChange(of: flashColorRed) { _, _ in
			model.setFlashColor(red: flashColorRed, green: flashColorGreen, blue: flashColorBlue)
		}
		.onChange(of: flashColorGreen) { _, _ in
			model.setFlashColor(red: flashColorRed, green: flashColorGreen, blue: flashColorBlue)
		}
		.onChange(of: flashColorBlue) { _, _ in
			model.setFlashColor(red: flashColorRed, green: flashColorGreen, blue: flashColorBlue)
		}
		.onChange(of: flashOpacity) { _, newValue in
			model.setFlashOpacity(newValue)
		}
	}

	private var fpsBinding: Binding<Double> {
		Binding(
			get: { maxVisionFPS },
			set: { newValue in
				maxVisionFPS = Double(Int(newValue.rounded()))
			}
		)
	}

	private var flashColorBinding: Binding<Color> {
		Binding(
			get: {
				Color(
					red: max(0, min(1, flashColorRed)),
					green: max(0, min(1, flashColorGreen)),
					blue: max(0, min(1, flashColorBlue))
				)
			},
			set: { newValue in
				let ui = UIColor(newValue)
				var r: CGFloat = 1
				var g: CGFloat = 0
				var b: CGFloat = 0
				var a: CGFloat = 1
				ui.getRed(&r, green: &g, blue: &b, alpha: &a)
				flashColorRed = Double(r)
				flashColorGreen = Double(g)
				flashColorBlue = Double(b)
			}
		)
	}

	private func applyAllSettingsToModel() {
		model.setAlertMode(AlertMode(rawValue: alertModeRaw) ?? .soundAndScreen)
		model.setSoundCooldownSeconds(soundCooldownSeconds)
		model.setMaxVisionFPS(maxVisionFPS)
		model.setPreviewStyle(PreviewStyle(rawValue: previewStyleRaw) ?? .dots)
		model.setFlashColor(red: flashColorRed, green: flashColorGreen, blue: flashColorBlue)
		model.setFlashOpacity(flashOpacity)
	}
}

#endif

