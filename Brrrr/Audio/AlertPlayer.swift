//
//  AlertPlayer.swift
//  Brrrr
//

#if os(macOS)
import AppKit
import Foundation

@MainActor
final class AlertPlayer {
	/// When false, no sounds will be played.
	var isEnabled: Bool = true

	/// Minimum seconds between alerts while touching persists.
	var cooldownSeconds: TimeInterval = 3

	private var lastPlayTime: TimeInterval = -TimeInterval.greatestFiniteMagnitude

	func resetCooldown() {
		lastPlayTime = -TimeInterval.greatestFiniteMagnitude
	}

	@discardableResult
	func playErrorIfAllowed(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
		guard isEnabled else { return false }
		guard (now - lastPlayTime) >= cooldownSeconds else { return false }

		NSSound.beep()
		lastPlayTime = now
		return true
	}
}

#endif