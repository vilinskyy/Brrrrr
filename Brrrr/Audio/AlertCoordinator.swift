//
//  AlertCoordinator.swift
//  Brrrr
//

import Foundation
import os

#if os(macOS)
import AppKit
#endif

#if os(iOS)
import AudioToolbox
#endif

@MainActor
final class AlertCoordinator {
	/// Sound + screen should share the same cooldown so they always fire together.
	var cooldownSeconds: TimeInterval = 3

	var mode: AlertMode = .soundAndScreen

	/// `nil` means "system beep".
	var soundURL: URL? {
		didSet { rebuildSoundIfNeeded() }
	}

	/// 0...1
	var soundVolume: Double = 1.0

	/// 0...1
	var flashColorRed: Double = 1.0
	/// 0...1
	var flashColorGreen: Double = 0.0
	/// 0...1
	var flashColorBlue: Double = 0.0

	/// 0...1
	var flashOpacity: Double = 0.65
	var flashDurationSeconds: TimeInterval = 0.1

	private var lastTriggerTime: TimeInterval = -TimeInterval.greatestFiniteMagnitude

#if os(macOS)
	private let screenFlashController = ScreenFlashController()
	private var sound: NSSound?
#endif

	init() {
		rebuildSoundIfNeeded()
	}

	func resetCooldown() {
		lastTriggerTime = -TimeInterval.greatestFiniteMagnitude
	}

#if os(macOS)
	/// Dismiss any visible screen flash and cancel pending hide timers (e.g. on pause or leaving touch state).
	func dismissFlash() {
		AppLogger.alert.info("dismissFlash()")
		screenFlashController.hideAllWindows()
	}
#else
	func dismissFlash() {}
#endif

	/// Returns `true` if an alert was triggered.
	@discardableResult
	func triggerIfAllowed(ignoreCooldown: Bool = false, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
		guard ignoreCooldown || (now - lastTriggerTime) >= cooldownSeconds else {
			AppLogger.alert.debug("triggerIfAllowed denied (cooldown) cooldownSeconds=\(self.cooldownSeconds, privacy: .public)")
			return false
		}
		lastTriggerTime = now

		AppLogger.alert.info("triggerIfAllowed fired mode=\(String(describing: self.mode), privacy: .public) enablesSound=\(self.mode.enablesSound, privacy: .public) enablesScreen=\(self.mode.enablesScreen, privacy: .public)")

		// Play sound first; in practice this reduces perceived "sound lag" vs. flashing first.
		if mode.enablesSound {
			_ = playSound()
		}

		if mode.enablesScreen {
#if os(macOS)
			let r = max(0, min(1, flashColorRed))
			let g = max(0, min(1, flashColorGreen))
			let b = max(0, min(1, flashColorBlue))

			screenFlashController.flash(
				durationSeconds: flashDurationSeconds,
				color: NSColor(calibratedRed: r, green: g, blue: b, alpha: 1),
				opacity: CGFloat(max(0, min(1, flashOpacity)))
			)
#endif
		}

		return true
	}

	// MARK: - Private

	private func playSound() -> Bool {
#if os(macOS)
		let volume = Float(max(0, min(1, soundVolume)))

		if let sound {
			sound.stop()
			sound.volume = volume
			return sound.play()
		}

		NSSound.beep()
		return true
#else
		// iOS: keep it simple for now (a lightweight system sound).
		AudioServicesPlaySystemSound(1104)
		return true
#endif
	}

#if os(macOS)
	private func rebuildSoundIfNeeded() {
		guard let soundURL else {
			sound = nil
			return
		}

		sound = NSSound(contentsOf: soundURL, byReference: true)
	}
#else
	private func rebuildSoundIfNeeded() {}
#endif
}

