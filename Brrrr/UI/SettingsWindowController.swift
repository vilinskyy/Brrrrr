//
//  SettingsWindowController.swift
//  Brrrr
//

#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
	private weak var model: TouchStateModel?
	private var window: NSWindow?

	init(model: TouchStateModel) {
		self.model = model
	}

	func show() {
		NSApp.activate(ignoringOtherApps: true)

		if let window {
			window.makeKeyAndOrderFront(nil)
			return
		}

		guard let model else { return }

		let rootView = SettingsView()
			.environmentObject(model)

		let hostingView = NSHostingView(rootView: rootView)
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 560, height: 840),
			styleMask: [.titled, .closable, .miniaturizable],
			backing: .buffered,
			defer: false
		)
		window.title = "Brrrrr Settings"
		window.isReleasedWhenClosed = false
		window.center()
		window.contentView = hostingView

		// Keep a reference so we can reopen the same window.
		self.window = window

		// If the user closes it, we can recreate it next time.
		NotificationCenter.default.addObserver(
			forName: NSWindow.willCloseNotification,
			object: window,
			queue: .main
		) { [weak self] _ in
			Task { @MainActor [weak self] in
				self?.window = nil
			}
		}

		window.makeKeyAndOrderFront(nil)
	}
}

#endif