//
//  MenuBarController.swift
//  Brrrr
//

import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
	private let model: TouchStateModel
	private let statusItem: NSStatusItem
	private var cancellables: Set<AnyCancellable> = []
	private let popover = NSPopover()
	private let launchAtLogin = LaunchAtLoginManager()
	private var menuUpdateTimer: Timer?
	private weak var countdownMenuItem: NSMenuItem?

	init(model: TouchStateModel) {
		self.model = model
		self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
		super.init()

		configureStatusItem()
		configurePopover()
		bind()
		updateStatus(for: model.touchState)

		// First launch onboarding: open the popover so the user can explicitly press Start.
		if !model.hasUserStartedMonitoring {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
				Task { @MainActor [weak self] in
					self?.togglePopover()
				}
			}
		}
	}

	private func bind() {
		model.$touchState
			.sink { [weak self] state in
				self?.updateStatus(for: state)
			}
			.store(in: &cancellables)

		model.$isPaused
			.sink { [weak self] _ in
				guard let self else { return }
				self.updateStatus(for: self.model.touchState)
			}
			.store(in: &cancellables)

		// Used for the timer icon and context menu countdown.
		model.$pauseRemainingSeconds
			.sink { [weak self] _ in
				guard let self else { return }
				self.updateStatus(for: self.model.touchState)
				self.updateCountdownMenuTitleIfNeeded()
			}
			.store(in: &cancellables)
	}

	private func configureStatusItem() {
		guard let button = statusItem.button else { return }

		button.image = makeDotImage(color: .systemGray)
		button.toolTip = "Brrrrr"
		button.target = self
		button.action = #selector(handleStatusItemClick(_:))
		button.sendAction(on: [.leftMouseUp, .rightMouseUp])
	}

	private func configurePopover() {
		let rootView = MenuBarPopoverView()
			.environmentObject(model)

		let hostingController = NSHostingController(rootView: rootView)
		popover.contentViewController = hostingController
		popover.behavior = .transient
		popover.animates = true
	}

	private func updateStatus(for state: TouchState) {
		guard let button = statusItem.button else { return }

		if model.isPaused {
			if model.pauseRemainingSeconds > 0 {
				button.image = makeSymbolImage(name: "timer")
				button.toolTip = "Brrrrr — paused (\(formatDuration(seconds: model.pauseRemainingSeconds)))"
			} else {
				button.image = makeSymbolImage(name: "pause.fill")
				button.toolTip = "Brrrrr — paused"
			}
			return
		}

		switch state {
		case .noTouch:
			button.image = makeDotImage(color: .systemGray)
			button.toolTip = "Brrrrr — no touch"
		case .maybeTouch:
			button.image = makeDotImage(color: .systemYellow)
			button.toolTip = "Brrrrr — maybe touching"
		case .touching:
			button.image = makeDotImage(color: .systemRed)
			button.toolTip = "Brrrrr — touching"
		}
	}

	@objc private func handleStatusItemClick(_ sender: Any?) {
		guard let event = NSApp.currentEvent else {
			togglePopover()
			return
		}

		switch event.type {
		case .rightMouseUp:
			showContextMenu()
		default:
			togglePopover()
		}
	}

	private func togglePopover() {
		guard let button = statusItem.button else { return }

		if popover.isShown {
			popover.performClose(nil)
		} else {
			popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
		}
	}

	private func showContextMenu() {
		model.cameraManager.refreshAvailableDevices()
		launchAtLogin.refresh()

		let menu = buildContextMenu()
		menu.delegate = self

		// Show menu on right-click without stealing left-click behavior.
		statusItem.menu = menu
		statusItem.button?.performClick(nil)
		statusItem.menu = nil
	}

	private func buildContextMenu() -> NSMenu {
		let menu = NSMenu()

		// Start / pause / resume
		if !model.hasUserStartedMonitoring {
			menu.addItem(NSMenuItem(title: "Start", action: #selector(startFromMenu), keyEquivalent: ""))
		} else {
			let pauseTitle = model.isPaused ? "Resume" : "Pause"
			menu.addItem(NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: ""))
		}

		if model.pauseRemainingSeconds > 0 {
			let timerItem = NSMenuItem(title: "Resuming in \(formatDuration(seconds: model.pauseRemainingSeconds))", action: nil, keyEquivalent: "")
			timerItem.image = makeSymbolImage(name: "timer")
			timerItem.isEnabled = false
			menu.addItem(timerItem)
			countdownMenuItem = timerItem
		} else {
			countdownMenuItem = nil
		}

		let pauseForItem = NSMenuItem(title: "Pause for 30 min", action: #selector(pauseFor30Min), keyEquivalent: "")
		pauseForItem.isEnabled = model.hasUserStartedMonitoring && model.pauseRemainingSeconds == 0
		menu.addItem(pauseForItem)
		menu.addItem(.separator())

		// Video source submenu
		let videoMenuItem = NSMenuItem(title: "Video Source", action: nil, keyEquivalent: "")
		let videoSubmenu = NSMenu()
		let selected = UserDefaults.standard.string(forKey: AppSettingsKey.selectedCameraID) ?? ""

		let defaultItem = NSMenuItem(title: "Default", action: #selector(selectCamera(_:)), keyEquivalent: "")
		defaultItem.representedObject = ""
		defaultItem.state = selected.isEmpty ? .on : .off
		videoSubmenu.addItem(defaultItem)
		videoSubmenu.addItem(.separator())

		for device in model.cameraManager.availableVideoDevices {
			let item = NSMenuItem(title: device.localizedName, action: #selector(selectCamera(_:)), keyEquivalent: "")
			item.representedObject = device.uniqueID
			item.state = (selected == device.uniqueID) ? .on : .off
			videoSubmenu.addItem(item)
		}
		videoMenuItem.submenu = videoSubmenu
		menu.addItem(videoMenuItem)

		// Alert output submenu
		let alertMenuItem = NSMenuItem(title: "Alert Output", action: nil, keyEquivalent: "")
		let alertSubmenu = NSMenu()
		let modeRaw = UserDefaults.standard.object(forKey: AppSettingsKey.alertMode) as? Int ?? AlertMode.soundOnly.rawValue
		for mode in AlertMode.allCases {
			let item = NSMenuItem(title: mode.displayName, action: #selector(selectAlertMode(_:)), keyEquivalent: "")
			item.representedObject = mode.rawValue
			item.state = (modeRaw == mode.rawValue) ? .on : .off
			alertSubmenu.addItem(item)
		}
		alertMenuItem.submenu = alertSubmenu
		menu.addItem(alertMenuItem)

		menu.addItem(.separator())

		// Launch at login
		let loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
		loginItem.state = launchAtLogin.isEnabled ? .on : .off
		menu.addItem(loginItem)

		menu.addItem(.separator())

		// Options / Quit - explicitly prevent macOS from auto-adding icons
		let optionsItem = NSMenuItem(title: "Options…", action: #selector(openSettings), keyEquivalent: "")
		optionsItem.image = NSImage()  // Empty image prevents system from adding default icon
		menu.addItem(optionsItem)
		
		let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
		quitItem.image = NSImage()
		menu.addItem(quitItem)

		// Ensure targets are set
		for item in menu.items {
			item.target = self
			item.submenu?.items.forEach { $0.target = self }
		}

		return menu
	}

	@objc private func togglePause() {
		model.togglePause()
	}

	@objc private func startFromMenu() {
		model.userStartMonitoring()
	}

	@objc private func pauseFor30Min() {
		model.pauseFor(minutes: 30)
	}

	@objc private func openSettings() {
		model.showSettingsWindow()
	}

	@objc private func toggleLaunchAtLogin() {
		launchAtLogin.setEnabled(!launchAtLogin.isEnabled)
	}

	@objc private func quitApp() {
		NSApp.terminate(nil)
	}

	@objc private func selectCamera(_ sender: NSMenuItem) {
		let uniqueID = (sender.representedObject as? String) ?? ""
		UserDefaults.standard.set(uniqueID, forKey: AppSettingsKey.selectedCameraID)
		model.cameraManager.setSelectedDevice(uniqueID: uniqueID.isEmpty ? nil : uniqueID)
	}

	@objc private func selectAlertMode(_ sender: NSMenuItem) {
		let raw = sender.representedObject as? Int ?? AlertMode.soundAndScreen.rawValue
		let mode = AlertMode(rawValue: raw) ?? .soundAndScreen
		UserDefaults.standard.set(mode.rawValue, forKey: AppSettingsKey.alertMode)
		model.setAlertMode(mode)
	}

	// MARK: NSMenuDelegate

	func menuWillOpen(_ menu: NSMenu) {
		menuUpdateTimer?.invalidate()
		menuUpdateTimer = nil

		guard model.pauseRemainingSeconds > 0, countdownMenuItem != nil else { return }

		menuUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
			Task { @MainActor [weak self] in
				self?.updateCountdownMenuTitleIfNeeded()
			}
		}
		updateCountdownMenuTitleIfNeeded()
	}

	func menuDidClose(_ menu: NSMenu) {
		menuUpdateTimer?.invalidate()
		menuUpdateTimer = nil
		countdownMenuItem = nil
	}

	private func updateCountdownMenuTitleIfNeeded() {
		guard let item = countdownMenuItem else { return }
		let remaining = model.pauseRemainingSeconds
		item.title = "Resuming in \(formatDuration(seconds: remaining))"
	}

	private func formatDuration(seconds: Int) -> String {
		let seconds = max(0, seconds)
		let h = seconds / 3600
		let m = (seconds % 3600) / 60
		let s = seconds % 60
		if h > 0 {
			return String(format: "%d:%02d:%02d", h, m, s)
		}
		return String(format: "%d:%02d", m, s)
	}

	private func makeSymbolImage(name: String) -> NSImage? {
		let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
		image?.isTemplate = true
		return image
	}

	private func makeDotImage(color: NSColor) -> NSImage {
		let size = NSSize(width: 16, height: 16)
		let image = NSImage(size: size, flipped: false) { rect in
			let circleRect = rect.insetBy(dx: 3, dy: 3)
			let path = NSBezierPath(ovalIn: circleRect)
			color.setFill()
			path.fill()
			return true
		}
		image.isTemplate = false
		return image
	}
}

