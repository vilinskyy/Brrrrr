//
//  MenuBarStatusItemView.swift
//  Brrrr
//

#if os(macOS)
import AppKit
import AVFoundation
import SwiftUI

struct MenuBarStatusItemView: View {
	@EnvironmentObject private var model: TouchStateModel
	@StateObject private var launchAtLogin = LaunchAtLoginManager()

	@AppStorage(AppSettingsKey.selectedCameraID) private var selectedCameraID: String = ""
	@AppStorage(AppSettingsKey.alertMode) private var alertModeRaw: Int = AlertMode.soundAndScreen.rawValue

	var body: some View {
		MenuBarIndicatorLabel(touchState: model.touchState)
			.padding(.vertical, 2)
			.contextMenu {
				Button {
					launchAtLogin.setEnabled(!launchAtLogin.isEnabled)
				} label: {
					if launchAtLogin.isEnabled {
						Label("Launch at login", systemImage: "checkmark")
					} else {
						Text("Launch at login")
					}
				}

				Divider()

				Button(model.isPaused ? "Resume" : "Pause") {
					model.togglePause()
				}

				Button("Pause for 30 min") {
					model.pauseFor(minutes: 30)
				}

				Divider()

				Menu("Video Source") {
					Button {
						selectedCameraID = ""
						model.cameraManager.setSelectedDevice(uniqueID: nil)
					} label: {
						if selectedCameraID.isEmpty {
							Label("Default", systemImage: "checkmark")
						} else {
							Text("Default")
						}
					}

					Divider()

					ForEach(model.cameraManager.availableVideoDevices, id: \.uniqueID) { device in
						Button {
							selectedCameraID = device.uniqueID
							model.cameraManager.setSelectedDevice(uniqueID: device.uniqueID)
						} label: {
							if selectedCameraID == device.uniqueID {
								Label(device.localizedName, systemImage: "checkmark")
							} else {
								Text(device.localizedName)
							}
						}
					}
				}

				Divider()

				Menu("Alert Output") {
					ForEach(AlertMode.allCases) { mode in
						Button {
							alertModeRaw = mode.rawValue
							model.setAlertMode(mode)
						} label: {
							if alertModeRaw == mode.rawValue {
								Label(mode.displayName, systemImage: "checkmark")
							} else {
								Text(mode.displayName)
							}
						}
					}
				}

				Divider()

				Button("Settings…") {
					model.showSettingsWindow()
				}

				Button("Quit") {
					NSApp.terminate(nil)
				}
			}
	}
}

#endif