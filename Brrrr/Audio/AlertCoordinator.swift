//
//  AlertCoordinator.swift
//  Brrrr
//

import AppKit
import Foundation

@MainActor
final class AlertCoordinator {
	/// Sound + screen should share the same cooldown so they always fire together.
	var cooldownSeconds: TimeInterval = 3

	var mode: AlertMode = .soundAndScreen

	/// `nil` means "system beep".
	var soundURL: URL? {
		didSet { rebuildSound() }
	}

	/// 0...1
	var soundVolume: Double = 1.0

	var flashColor: NSColor = .systemRed
	/// 0...1
	var flashOpacity: Double = 0.65
	var flashDurationSeconds: TimeInterval = 0.1

	private var lastTriggerTime: TimeInterval = -TimeInterval.greatestFiniteMagnitude
	private let screenFlashController = ScreenFlashController()

	private var sound: NSSound?

	init() {
		rebuildSound()
	}

	func resetCooldown() {
		lastTriggerTime = -TimeInterval.greatestFiniteMagnitude
	}

	/// Returns `true` if an alert was triggered.
	@discardableResult
	func triggerIfAllowed(ignoreCooldown: Bool = false, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
		guard ignoreCooldown || (now - lastTriggerTime) >= cooldownSeconds else { return false }
		lastTriggerTime = now

		// Play sound first; in practice this reduces perceived "sound lag" vs. flashing first.
		if mode.enablesSound {
			_ = playSound()
		}

		if mode.enablesScreen {
			screenFlashController.flash(
				durationSeconds: flashDurationSeconds,
				color: flashColor,
				opacity: CGFloat(max(0, min(1, flashOpacity)))
			)
		}

		return true
	}

	// MARK: - Private

	private func playSound() -> Bool {
		let volume = Float(max(0, min(1, soundVolume)))

		if let sound {
			sound.stop()
			sound.volume = volume
			return sound.play()
		}

		NSSound.beep()
		return true
	}

	private func rebuildSound() {
		guard let soundURL else {
			sound = nil
			return
		}

		sound = NSSound(contentsOf: soundURL, byReference: true)
	}
}

