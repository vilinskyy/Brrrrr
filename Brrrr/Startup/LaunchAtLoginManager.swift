//
//  LaunchAtLoginManager.swift
//  Brrrr
//

#if os(macOS)
import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
	@Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status
	@Published private(set) var lastError: String?

	/// Treat `.requiresApproval` as enabled for UI purposes (user requested enablement; macOS needs approval).
	var isEnabled: Bool { status == .enabled || status == .requiresApproval }

	func refresh() {
		status = SMAppService.mainApp.status
	}

	func setEnabled(_ enabled: Bool) {
		lastError = nil
		do {
			if enabled {
				try SMAppService.mainApp.register()
			} else {
				try SMAppService.mainApp.unregister()
			}
		} catch {
			lastError = error.localizedDescription
		}

		refresh()
	}

	func openLoginItemsSettings() {
		let candidates = [
			"x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
			"x-apple.systempreferences:com.apple.preference.users",
			"x-apple.systempreferences:",
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