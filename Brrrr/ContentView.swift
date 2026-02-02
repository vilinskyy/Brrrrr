//
//  ContentView.swift
//  Brrrr
//
//  Created by Oleksandr Vilinskyi on 18/01/2026.
//

#if os(macOS)
import AVFoundation
import AppKit
import SwiftUI

struct ContentView: View {
	@EnvironmentObject private var model: TouchStateModel
	@AppStorage(AppSettingsKey.selectedCameraID) private var selectedCameraID: String = ""
	@AppStorage(AppSettingsKey.mirrorVideo) private var mirrorVideo: Bool = true

	var body: some View {
		VStack(spacing: 0) {
			header

			ZStack {
				CameraView(session: model.cameraManager.session, isMirrored: mirrorVideo)
					.clipped()

				VStack {
					Spacer()
					HStack {
						Text(model.statusText)
							.font(.caption)
							.padding(.horizontal, 10)
							.padding(.vertical, 6)
							.background(.regularMaterial)
							.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
							.overlay(
								RoundedRectangle(cornerRadius: 10, style: .continuous)
									.strokeBorder(.separator, lineWidth: 1)
							)
						Spacer()
					}
					.padding(12)
				}

				if let overlay = overlayMessage {
					VStack(spacing: 12) {
						Text(overlay.title)
							.font(.title3.weight(.semibold))

						if let detail = overlay.detail {
							Text(detail)
								.foregroundStyle(.secondary)
								.multilineTextAlignment(.center)
								.frame(maxWidth: 420)
						}

						HStack(spacing: 12) {
							if overlay.showsOpenSettings {
								Button("Open Camera Privacy Settings") {
									openCameraPrivacySettings()
								}
							}
							Button("Retry") {
								model.startMonitoring()
							}
						}
					}
					.padding(20)
					.background(.regularMaterial)
					.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
					.overlay(
						RoundedRectangle(cornerRadius: 16, style: .continuous)
							.strokeBorder(.separator, lineWidth: 1)
					)
					.padding(24)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.frame(minWidth: 720, minHeight: 520)
	}

	@ViewBuilder
	private var header: some View {
		HStack {
			Text("Brrrrr")
				.font(.headline)

			Spacer()

			Picker("Camera", selection: $selectedCameraID) {
				Text("Default").tag("")
				ForEach(model.cameraManager.availableVideoDevices, id: \.uniqueID) { device in
					Text(device.localizedName).tag(device.uniqueID)
				}
			}
			.labelsHidden()
			.pickerStyle(.menu)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(.bar)
		.overlay(Rectangle().frame(height: 1).foregroundStyle(.separator), alignment: .bottom)
		.onAppear {
			model.cameraManager.refreshAvailableDevices()
			model.cameraManager.setSelectedDevice(uniqueID: selectedCameraID.isEmpty ? nil : selectedCameraID)
		}
		.onChange(of: selectedCameraID) { newValue in
			model.cameraManager.setSelectedDevice(uniqueID: newValue.isEmpty ? nil : newValue)
		}
	}

	private struct OverlayMessage {
		let title: String
		let detail: String?
		let showsOpenSettings: Bool
	}

	private var overlayMessage: OverlayMessage? {
		if let lastError = model.cameraManager.lastError {
			return OverlayMessage(
				title: "Camera Error",
				detail: lastError,
				showsOpenSettings: false
			)
		}

		switch model.cameraManager.authorizationState {
		case .authorized:
			return nil
		case .notDetermined:
			return OverlayMessage(
				title: "Requesting Camera Access…",
				detail: "macOS will ask for camera permission. The video stream stays on-device and is not recorded.",
				showsOpenSettings: false
			)
		case .denied:
			return OverlayMessage(
				title: "Camera Access Denied",
				detail: "Enable camera access for Brrrrr in System Settings to continue.",
				showsOpenSettings: true
			)
		case .restricted:
			return OverlayMessage(
				title: "Camera Access Restricted",
				detail: "Camera access is restricted by system policy (for example, Screen Time or a managed device profile).",
				showsOpenSettings: true
			)
		}
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

#Preview {
    ContentView()
}

#endif
