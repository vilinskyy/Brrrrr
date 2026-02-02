//
//  MenuBarPopoverView.swift
//  Brrrr
//

#if os(macOS)
import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
	@EnvironmentObject private var model: TouchStateModel
	@AppStorage(AppSettingsKey.mirrorVideo) private var mirrorVideo: Bool = true
	@AppStorage(AppSettingsKey.previewStyle) private var previewStyleRaw: Int = PreviewStyle.dots.rawValue

	var body: some View {
		VStack(spacing: 0) {
			ZStack {
				GeometryReader { proxy in
					ZStack {
						switch previewStyle {
						case .normal:
							if let cgImage = model.previewImage {
								Image(decorative: cgImage, scale: 1)
									.resizable()
									.scaledToFill()
									.frame(width: proxy.size.width, height: proxy.size.height)
									.clipped()
							} else {
								Color.black
							}
						case .dots:
							Color.black
							TechnicalDotsOverlayView(detections: model.lastDetections)
								.padding(0)
						}
					}
					.frame(width: proxy.size.width, height: proxy.size.height)
					.clipped()
					.scaleEffect(x: mirrorVideo ? -1 : 1, y: 1)
				}

				if !model.hasUserStartedMonitoring {
					VStack(spacing: 10) {
						Text("Brrrrr")
							.font(.headline)

						Text("Press Start to begin monitoring. The camera is not used until you start.")
							.font(.caption)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
							.frame(maxWidth: 280)

						Button("Start") {
							model.userStartMonitoring()
						}
						.keyboardShortcut(.defaultAction)
					}
					.padding(14)
					.background(.regularMaterial)
					.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
					.overlay(
						RoundedRectangle(cornerRadius: 12, style: .continuous)
							.strokeBorder(.separator, lineWidth: 1)
					)
					.padding(12)
				}

				if let overlay = overlayMessage {
					VStack(spacing: 10) {
						Text(overlay.title)
							.font(.headline)

						if let detail = overlay.detail {
							Text(detail)
								.font(.caption)
								.foregroundStyle(.secondary)
								.multilineTextAlignment(.center)
								.frame(maxWidth: 280)
						}

						HStack(spacing: 10) {
							if overlay.showsOpenSettings {
								Button("Open Privacy Settings") {
									openCameraPrivacySettings()
								}
							}
							Button("Retry") {
								model.startMonitoring()
							}
						}
					}
					.padding(14)
					.background(.regularMaterial)
					.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
					.overlay(
						RoundedRectangle(cornerRadius: 12, style: .continuous)
							.strokeBorder(.separator, lineWidth: 1)
					)
					.padding(12)
				}
			}

			Divider()

			HStack(spacing: 10) {
				VStack(alignment: .leading, spacing: 2) {
					Text(model.statusText)
						.lineLimit(2)

					Text("FPS \(Int(model.measuredFPS.rounded())) • CPU \(Int(model.cpuPercent.rounded()))%")
						.foregroundStyle(.secondary)
				}
				.font(.caption)
				.monospacedDigit()
				.frame(maxWidth: .infinity, alignment: .leading)

			Button {
				model.togglePause()
			} label: {
				Image(systemName: model.isPaused ? "play.circle" : "pause.circle")
			}
			.buttonStyle(.borderless)

			Button {
				model.showSettingsWindow()
			} label: {
				Image(systemName: "gearshape")
			}
			.buttonStyle(.borderless)

			Button {
				NSApp.terminate(nil)
			} label: {
				Image(systemName: "xmark.circle")
			}
			.buttonStyle(.borderless)
			}
			.padding(10)
			.background(.bar)
		}
		.frame(width: 360, height: 260)
		.onAppear {
			model.cameraManager.refreshAvailableDevices()
		}
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
			return nil
		case .notDetermined:
			// Only show this once the user has pressed Start.
			guard model.hasUserStartedMonitoring else { return nil }
			return OverlayMessage(
				title: "Requesting Camera Access…",
				detail: "macOS will ask for camera permission. Video stays on-device and is not recorded.",
				showsOpenSettings: false
			)
		case .denied:
			return OverlayMessage(
				title: "Camera Access Denied",
				detail: "Enable camera access for Brrrrr in System Settings.",
				showsOpenSettings: true
			)
		case .restricted:
			return OverlayMessage(
				title: "Camera Access Restricted",
				detail: "Camera access is restricted by system policy.",
				showsOpenSettings: true
			)
		}
	}

	private func showSettings() {
		// Intentionally unused: Settings are opened via SettingsWindowController for reliability in LSUIElement menu bar apps.
	}

	private var previewStyle: PreviewStyle {
		PreviewStyle(rawValue: previewStyleRaw) ?? .dots
	}

	private func openCameraPrivacySettings() {
		let candidates = [
			"x-apple.systempreferences:com.apple.preference.security?Privacy_Camera",
			"x-apple.systempreferences:com.apple.preference.security",
		]

		for candidate in candidates {
			if let url = URL(string: candidate) {
				NSWorkspace.shared.open(url)
				return
			}
		}
	}
}

#endif