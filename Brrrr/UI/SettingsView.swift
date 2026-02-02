//
//  SettingsView.swift
//  Brrrr
//

#if os(macOS)
import AVFoundation
import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
	@EnvironmentObject private var model: TouchStateModel
	@StateObject private var launchAtLogin = LaunchAtLoginManager()
	@ObservedObject private var updater = AppUpdateService.shared

	@AppStorage(AppSettingsKey.selectedCameraID) private var selectedCameraID: String = ""
	@AppStorage(AppSettingsKey.soundCooldownSeconds) private var soundCooldownSeconds: Double = 3
	@AppStorage(AppSettingsKey.maxVisionFPS) private var maxVisionFPS: Double = 12
	@AppStorage(AppSettingsKey.mirrorVideo) private var mirrorVideo: Bool = true
	@AppStorage(AppSettingsKey.previewStyle) private var previewStyleRaw: Int = PreviewStyle.dots.rawValue
	@AppStorage(AppSettingsKey.alertMode) private var alertModeRaw: Int = AlertMode.soundOnly.rawValue
	@AppStorage(AppSettingsKey.alertSoundPath) private var alertSoundPath: String = ""
	@AppStorage(AppSettingsKey.alertSoundVolume) private var alertSoundVolume: Double = 1.0
	@AppStorage(AppSettingsKey.flashColorRed) private var flashColorRed: Double = 1.0
	@AppStorage(AppSettingsKey.flashColorGreen) private var flashColorGreen: Double = 0.0
	@AppStorage(AppSettingsKey.flashColorBlue) private var flashColorBlue: Double = 0.0
	@AppStorage(AppSettingsKey.flashOpacity) private var flashOpacity: Double = 0.65

	@State private var availableSounds: [SystemSoundItem] = []
	@State private var isPrivacyPolicyPresented: Bool = false

	private let sliderWidth: CGFloat = 220

	var body: some View {
		TabView {
			generalTab
				.tabItem {
					Label("General", systemImage: "gearshape")
				}

			privacyTab
				.tabItem {
					Label("Privacy", systemImage: "hand.raised")
				}
		}
		.frame(width: 520)
		.fixedSize(horizontal: false, vertical: true)
		.onAppear {
			model.cameraManager.refreshAvailableDevices()
			availableSounds = SystemSoundLibrary.availableSounds()
			launchAtLogin.refresh()
			applyAllSettingsToModel()
		}
		.onChange(of: selectedCameraID) { newValue in
			model.cameraManager.setSelectedDevice(uniqueID: newValue.isEmpty ? nil : newValue)
		}
		.onChange(of: soundCooldownSeconds) { newValue in
			model.setSoundCooldownSeconds(newValue)
		}
		.onChange(of: maxVisionFPS) { newValue in
			model.setMaxVisionFPS(newValue)
		}
		.onChange(of: previewStyleRaw) { newValue in
			model.setPreviewStyle(PreviewStyle(rawValue: newValue) ?? .dots)
		}
		.onChange(of: alertModeRaw) { newValue in
			model.setAlertMode(AlertMode(rawValue: newValue) ?? .soundAndScreen)
		}
		.onChange(of: alertSoundPath) { newValue in
			model.setAlertSoundPath(newValue)
		}
		.onChange(of: alertSoundVolume) { newValue in
			model.setAlertSoundVolume(newValue)
		}
		.onChange(of: flashColorRed) { _ in
			model.setFlashColor(red: flashColorRed, green: flashColorGreen, blue: flashColorBlue)
		}
		.onChange(of: flashColorGreen) { _ in
			model.setFlashColor(red: flashColorRed, green: flashColorGreen, blue: flashColorBlue)
		}
		.onChange(of: flashColorBlue) { _ in
			model.setFlashColor(red: flashColorRed, green: flashColorGreen, blue: flashColorBlue)
		}
		.onChange(of: flashOpacity) { newValue in
			model.setFlashOpacity(newValue)
		}
		.sheet(isPresented: $isPrivacyPolicyPresented) {
			PrivacyPolicySheet()
		}
	}

	// MARK: - General Tab

	@ViewBuilder
	private var generalTab: some View {
		VStack(alignment: .leading, spacing: 18) {
			// On a startup section
			HStack {
				Text("On a startup")
					.font(.headline)
				Spacer()
				Toggle("Launch at login", isOn: Binding(
					get: { launchAtLogin.isEnabled },
					set: { launchAtLogin.setEnabled($0) }
				))
				.toggleStyle(.switch)
			}

			if launchAtLogin.status == .requiresApproval {
				HStack(spacing: 8) {
					Text("Requires approval in System Settings → Login Items.")
						.font(.caption)
						.foregroundStyle(.secondary)

					Button("Open Login Items") {
						launchAtLogin.openLoginItemsSettings()
					}
					.buttonStyle(.link)
					.font(.caption)
				}
			}

			if let lastError = launchAtLogin.lastError {
				Text("Launch at login error: \(lastError)")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			Divider()

			// Camera settings
			VStack(alignment: .leading, spacing: 10) {
				HStack(alignment: .firstTextBaseline) {
					Text("Camera")
					Spacer()
					Picker("", selection: $selectedCameraID) {
						Text("Default").tag("")
						ForEach(model.cameraManager.availableVideoDevices, id: \.uniqueID) { device in
							Text(device.localizedName).tag(device.uniqueID)
						}
					}
					.labelsHidden()
					.pickerStyle(.menu)
				}

				Toggle("Mirror video", isOn: $mirrorVideo)

				Picker("Preview style", selection: $previewStyleRaw) {
					ForEach(PreviewStyle.allCases) { style in
						Text(style.displayName).tag(style.rawValue)
					}
				}
				.pickerStyle(.segmented)
			}

			sectionTitle("Alerts") {
				Button("Test") {
					model.testAlert()
				}
				.buttonStyle(.bordered)
				.controlSize(.small)
				.help("Triggers an alert without touching your face")
			}

			VStack(alignment: .leading, spacing: 12) {
				Picker("Mode", selection: $alertModeRaw) {
					ForEach(AlertMode.allCases) { mode in
						Text(mode.displayName).tag(mode.rawValue)
					}
				}
				.pickerStyle(.segmented)

				HStack(alignment: .firstTextBaseline) {
					Text("Cooldown")
					Spacer()
					Stepper(value: $soundCooldownSeconds, in: 0...30, step: 1) {
						Text("\(Int(soundCooldownSeconds))s")
							.monospacedDigit()
					}
				}

				HStack(alignment: .firstTextBaseline) {
					Text("Error sound")
					Spacer()
					Picker("", selection: $alertSoundPath) {
						Text("System Beep").tag("")
						ForEach(availableSounds) { sound in
							Text(sound.name).tag(sound.url.path)
						}
					}
					.labelsHidden()
					.pickerStyle(.menu)
				}
				.disabled(!alertMode.enablesSound)

				// Volume slider with clickable tick marks
				HStack(alignment: .top) {
					Text("Volume")
					Spacer()
					VStack(alignment: .trailing, spacing: 2) {
						Slider(value: $alertSoundVolume, in: 0...1)
							.frame(width: sliderWidth)
						HStack {
							Button("0%") { alertSoundVolume = 0 }
								.buttonStyle(.plain)
							Spacer()
							Button("50%") { alertSoundVolume = 0.5 }
								.buttonStyle(.plain)
							Spacer()
							Button("100%") { alertSoundVolume = 1.0 }
								.buttonStyle(.plain)
						}
						.font(.caption2)
						.foregroundStyle(.secondary)
						.frame(width: sliderWidth)
						.padding(.horizontal, 8)
					}
				}
				.disabled(!alertMode.enablesSound)

				// Screen blink with color picker on left, full-width slider
				HStack(alignment: .top) {
					Text("Screen blink")
					Spacer()
					ColorPicker("", selection: flashColorBinding, supportsOpacity: false)
						.labelsHidden()
					VStack(alignment: .trailing, spacing: 2) {
						Slider(value: $flashOpacity, in: 0...1)
							.frame(width: sliderWidth)
						HStack {
							Button("0%") { flashOpacity = 0 }
								.buttonStyle(.plain)
							Spacer()
							Button("25%") { flashOpacity = 0.25 }
								.buttonStyle(.plain)
							Spacer()
							Button("50%") { flashOpacity = 0.5 }
								.buttonStyle(.plain)
							Spacer()
							Button("75%") { flashOpacity = 0.75 }
								.buttonStyle(.plain)
							Spacer()
							Button("100%") { flashOpacity = 1.0 }
								.buttonStyle(.plain)
						}
						.font(.caption2)
						.foregroundStyle(.secondary)
						.frame(width: sliderWidth)
						.padding(.horizontal, 8)
					}
				}
				.disabled(!alertMode.enablesScreen)
			}

			Divider()

			// Processing rate with subtitle right below
			VStack(alignment: .leading, spacing: 4) {
				HStack(alignment: .top) {
					VStack(alignment: .leading, spacing: 2) {
						Text("Processing rate")
							.font(.headline)
						Text("Lower FPS uses less CPU but may react slower.")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					Spacer()
					VStack(alignment: .trailing, spacing: 2) {
						Slider(value: fpsBinding, in: 1...30)
							.frame(width: sliderWidth)
						HStack {
							Button("4") { maxVisionFPS = 4 }
								.buttonStyle(.plain)
							Spacer()
							Button("15") { maxVisionFPS = 15 }
								.buttonStyle(.plain)
							Spacer()
							Button("30 FPS") { maxVisionFPS = 30 }
								.buttonStyle(.plain)
						}
						.font(.caption2)
						.foregroundStyle(.secondary)
						.frame(width: sliderWidth)
						.padding(.horizontal, 8)
					}
				}
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(20)
	}

	// MARK: - Privacy Tab

	@ViewBuilder
	private var privacyTab: some View {
		VStack(alignment: .leading, spacing: 18) {
			sectionTitle("Data & Processing")

			VStack(alignment: .leading, spacing: 10) {
				Text(Self.inAppPrivacySummary)
					.font(.callout)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)

				Text("Microphone is never accessed.")
					.font(.callout)
					.foregroundStyle(.secondary)
			}

			Divider()

			sectionTitle("Privacy Policy")

			VStack(alignment: .leading, spacing: 10) {
				HStack(spacing: 12) {
					Button("View Privacy Policy") {
						isPrivacyPolicyPresented = true
					}
					.buttonStyle(.bordered)

					Button("Copy summary") {
						Self.copyToPasteboard(Self.inAppPrivacySummary)
					}
					.buttonStyle(.link)
				}
			}

			Spacer()

			Divider()

			sectionTitle("Updates")

			VStack(alignment: .leading, spacing: 10) {
				if updater.isDirectDistribution {
					Button("Check for Updates…") {
						updater.checkForUpdates()
					}
					.buttonStyle(.bordered)
					.controlSize(.small)
				} else {
					Text("This copy was installed from the Mac App Store. Updates are delivered by the App Store.")
						.font(.callout)
						.foregroundStyle(.secondary)
				}
			}

			Divider()

			// App version
			HStack {
				Text("Version")
					.foregroundStyle(.secondary)
				Spacer()
				Text(appVersion)
					.foregroundStyle(.secondary)
			}
			.font(.caption)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(20)
	}

	private struct PrivacyPolicySheet: View {
		@Environment(\.dismiss) private var dismiss

		var body: some View {
			VStack(alignment: .leading, spacing: 12) {
				HStack {
					Text("Privacy Policy")
						.font(.title3)
						.fontWeight(.semibold)
					Spacer()
					Button("Done") { dismiss() }
				}

				ScrollView {
					Text(SettingsView.privacyPolicyText)
						.font(.callout)
						.textSelection(.enabled)
						.frame(maxWidth: .infinity, alignment: .leading)
				}

				HStack(spacing: 12) {
					Button("Copy policy") {
						SettingsView.copyToPasteboard(SettingsView.privacyPolicyText)
					}
					.buttonStyle(.bordered)

					Spacer()
				}
			}
			.padding(16)
			.frame(minWidth: 560, minHeight: 520)
		}
	}

	private func applyAllSettingsToModel() {
		model.cameraManager.setSelectedDevice(uniqueID: selectedCameraID.isEmpty ? nil : selectedCameraID)
		model.setSoundCooldownSeconds(soundCooldownSeconds)
		model.setMaxVisionFPS(maxVisionFPS)
		model.setPreviewStyle(PreviewStyle(rawValue: previewStyleRaw) ?? .dots)
		model.setAlertMode(alertMode)
		model.setAlertSoundPath(alertSoundPath)
		model.setAlertSoundVolume(alertSoundVolume)
		model.setFlashColor(red: flashColorRed, green: flashColorGreen, blue: flashColorBlue)
		model.setFlashOpacity(flashOpacity)
	}

	private func sectionTitle(_ title: String) -> some View {
		HStack {
			Text(title)
				.font(.headline)
			Spacer()
		}
	}

	private func sectionTitle(_ title: String, trailing: () -> some View) -> some View {
		HStack {
			Text(title)
				.font(.headline)
			Spacer()
			trailing()
		}
	}

	private var alertMode: AlertMode {
		AlertMode(rawValue: alertModeRaw) ?? .soundAndScreen
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
				let ns = NSColor(newValue)
				guard let srgb = ns.usingColorSpace(.sRGB) else { return }
				flashColorRed = Double(srgb.redComponent)
				flashColorGreen = Double(srgb.greenComponent)
				flashColorBlue = Double(srgb.blueComponent)
			}
		)
	}

	private var appVersion: String {
		let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3"
		let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
		return "\(version) (\(build))"
	}

	private static func copyToPasteboard(_ text: String) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	private static let inAppPrivacySummary: String = """
	Brrrrr uses your Mac's camera to detect hand-to-face touches in real time. Processing is on-device. No photos or video are recorded, stored, or transmitted. Brrrrr does not include analytics or tracking. Direct-download builds can optionally check GitHub for updates when you choose “Check for Updates…”.
	"""

	private static let privacyPolicyText: String = """
	Privacy Policy — Brrrrr
	Effective date: 2026-01-18

	Summary
	Brrrrr does not collect personal data. The app uses your Mac's camera to detect hand-to-face touches in real time. All processing happens on-device. No photos or video are recorded, stored, or transmitted. Brrrrr does not access the microphone.

	Information we collect
	None. Brrrrr does not collect personal information, usage analytics, device identifiers, or telemetry.

	Camera usage
	The camera is used only for live processing. Frames are processed in memory and discarded immediately. No recordings are made.

	Microphone
	Brrrrr does not access the microphone and does not request microphone permissions.

	Network
	Core functionality does not require network access. If you installed the direct-download version, you can optionally check GitHub for updates when you choose “Check for Updates…”. No analytics or personal data are sent.

	Contact
	vilinskyy.com
	"""
}

#Preview {
	SettingsView()
		.environmentObject(TouchStateModel())
}

#endif
