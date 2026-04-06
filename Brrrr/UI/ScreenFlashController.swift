//
//  ScreenFlashController.swift
//  Brrrr
//
//  Flashes a borderless red overlay across all connected displays.
//

#if os(macOS)
import AppKit
import Foundation
import os

@MainActor
final class ScreenFlashController {
	private var windows: [ScreenFlashWindow] = []
	private var lastScreensSignature: [CGRect] = []
	private var hideWorkItem: DispatchWorkItem?
	private var failsafeWorkItem: DispatchWorkItem?
	private var screenObserver: NSObjectProtocol?

	init() {
		// Keep windows in sync when monitors are connected/disconnected.
		screenObserver = NotificationCenter.default.addObserver(
			forName: NSApplication.didChangeScreenParametersNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			Task { @MainActor [weak self] in
				self?.rebuildWindowsIfNeeded(force: true)
			}
		}
	}

	deinit {
		if let screenObserver {
			NotificationCenter.default.removeObserver(screenObserver)
		}
	}

	/// Flash all displays with a semi-transparent overlay.
	/// Uses `DispatchQueue.main` instead of `Task.sleep` to avoid a macOS 26.4 Swift concurrency issue
	/// where cancelled `@MainActor` tasks can mis-schedule after `Task.sleep`.
	func flash(durationSeconds: TimeInterval = 0.1, color: NSColor = .systemRed, opacity: CGFloat = 0.65) {
		let durationSeconds = max(0, durationSeconds)
		rebuildWindowsIfNeeded(force: false)

		cancelScheduledHide()

		AppLogger.flash.info("Flash start durationSeconds=\(durationSeconds, privacy: .public) opacity=\(Double(opacity), privacy: .public) windowCount=\(self.windows.count, privacy: .public)")

		let cgColor = color.withAlphaComponent(opacity).cgColor
		for window in windows {
			window.setFillColor(cgColor)
			window.alphaValue = 1
			window.orderFrontRegardless()
		}

		let hideItem = DispatchWorkItem { [weak self] in
			AppLogger.flash.info("Flash scheduled hide firing")
			self?.hideAllWindows()
		}
		hideWorkItem = hideItem
		DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds, execute: hideItem)

		let failsafeDelay = max(durationSeconds * 3, 2.0)
		let failsafeItem = DispatchWorkItem { [weak self] in
			AppLogger.flash.error("Flash failsafe fired — forcing overlay dismiss (delay=\(failsafeDelay, privacy: .public)s)")
			self?.hideAllWindows()
		}
		failsafeWorkItem = failsafeItem
		DispatchQueue.main.asyncAfter(deadline: .now() + failsafeDelay, execute: failsafeItem)
	}

	/// Immediately hide all flash windows and cancel any pending hide timers.
	func hideAllWindows() {
		cancelScheduledHide()
		for window in windows {
			window.orderOut(nil)
		}
		AppLogger.flash.debug("Flash windows hidden")
	}

	// MARK: - Private

	private func cancelScheduledHide() {
		hideWorkItem?.cancel()
		hideWorkItem = nil
		failsafeWorkItem?.cancel()
		failsafeWorkItem = nil
	}

	private func rebuildWindowsIfNeeded(force: Bool) {
		let screens = NSScreen.screens.sorted {
			let a = $0.frame.origin
			let b = $1.frame.origin
			if a.x != b.x { return a.x < b.x }
			return a.y < b.y
		}

		let signature = screens.map { $0.frame }
		guard force || signature != lastScreensSignature else { return }

		AppLogger.flash.info("Rebuilding flash windows force=\(force, privacy: .public) screenCount=\(screens.count, privacy: .public)")

		for window in windows {
			window.close()
		}
		windows = screens.map { ScreenFlashWindow(screen: $0) }
		lastScreensSignature = signature
	}
}

private final class ScreenFlashWindow: NSPanel {
	private let fillView = NSView()

	init(screen: NSScreen) {
		// Note: `NSWindow.init(... screen:)` is a convenience initializer, so we can't call it from a subclass.
		super.init(
			contentRect: screen.frame,
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)

		isReleasedWhenClosed = false
		isOpaque = false
		backgroundColor = .clear
		hasShadow = false
		hidesOnDeactivate = false
		isMovable = false
		ignoresMouseEvents = true
		animationBehavior = .none

		// Show above other apps (including full-screen), without stealing focus.
		level = .screenSaver
		collectionBehavior = [
			.canJoinAllSpaces,
			.fullScreenAuxiliary,
			.ignoresCycle,
			.stationary,
		]

		fillView.wantsLayer = true
		fillView.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.65).cgColor
		fillView.autoresizingMask = [.width, .height]
		contentView = fillView

		alphaValue = 0
		orderOut(nil)
	}

	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }

	func setFillColor(_ color: CGColor) {
		fillView.layer?.backgroundColor = color
	}
}

#endif
