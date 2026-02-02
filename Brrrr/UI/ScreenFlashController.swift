//
//  ScreenFlashController.swift
//  Brrrr
//
//  Flashes a borderless red overlay across all connected displays.
//

#if os(macOS)
import AppKit
import Foundation

@MainActor
final class ScreenFlashController {
	private var windows: [ScreenFlashWindow] = []
	private var lastScreensSignature: [CGRect] = []
	private var hideTask: Task<Void, Never>?
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

	/// Flash all displays with a semi-transparent red overlay.
	func flash(durationSeconds: TimeInterval = 0.1, color: NSColor = .systemRed, opacity: CGFloat = 0.65) {
		let durationSeconds = max(0, durationSeconds)
		rebuildWindowsIfNeeded(force: false)

		hideTask?.cancel()

		let cgColor = color.withAlphaComponent(opacity).cgColor
		for window in windows {
			window.setFillColor(cgColor)
			window.alphaValue = 1
			window.orderFrontRegardless()
		}

		hideTask = Task { @MainActor in
			if durationSeconds > 0 {
				try? await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))
			}
			for window in windows {
				window.orderOut(nil)
			}
		}
	}

	// MARK: - Private

	private func rebuildWindowsIfNeeded(force: Bool) {
		let screens = NSScreen.screens.sorted {
			let a = $0.frame.origin
			let b = $1.frame.origin
			if a.x != b.x { return a.x < b.x }
			return a.y < b.y
		}

		let signature = screens.map { $0.frame }
		guard force || signature != lastScreensSignature else { return }

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