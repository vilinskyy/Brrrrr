//
//  AppSettings.swift
//  Brrrr
//

import Foundation

enum AppSettingsKey {
	static let selectedCameraID = "selectedCameraID"
	static let hasUserStartedMonitoring = "hasUserStartedMonitoring"
	static let soundCooldownSeconds = "soundCooldownSeconds"
	static let maxVisionFPS = "maxVisionFPS"
	static let mirrorVideo = "mirrorVideo"
	static let previewStyle = "previewStyle"
	static let alertMode = "alertMode"
	static let alertSoundPath = "alertSoundPath"
	static let alertSoundVolume = "alertSoundVolume"
	static let flashColorRed = "flashColorRed"
	static let flashColorGreen = "flashColorGreen"
	static let flashColorBlue = "flashColorBlue"
	static let flashOpacity = "flashOpacity"
	static let touchesTodayCount = "touchesTodayCount"
	static let touchesTodayDate = "touchesTodayDate"
}

struct AppSettings: Sendable, Hashable {
	var selectedCameraID: String
	var soundCooldownSeconds: Double
	var maxVisionFPS: Double
	var mirrorVideo: Bool
	var previewStyleRaw: Int
	var alertModeRaw: Int
	var alertSoundPath: String
	var alertSoundVolume: Double
	var flashColorRed: Double
	var flashColorGreen: Double
	var flashColorBlue: Double
	var flashOpacity: Double

	static let `default` = AppSettings(
		selectedCameraID: "",
		soundCooldownSeconds: 3,
		maxVisionFPS: 12,
		mirrorVideo: true,
		previewStyleRaw: PreviewStyle.dots.rawValue,
		// Default to sound-only (flash can be sensitive for some users).
		alertModeRaw: AlertMode.soundOnly.rawValue,
		alertSoundPath: "",
		alertSoundVolume: 1.0,
		flashColorRed: 1.0,
		flashColorGreen: 0.0,
		flashColorBlue: 0.0,
		flashOpacity: 0.65
	)

	static func load(from defaults: UserDefaults = .standard) -> AppSettings {
		let selectedCameraID = defaults.string(forKey: AppSettingsKey.selectedCameraID) ?? Self.default.selectedCameraID

		let soundCooldownSeconds: Double = {
			guard defaults.object(forKey: AppSettingsKey.soundCooldownSeconds) != nil else { return Self.default.soundCooldownSeconds }
			return defaults.double(forKey: AppSettingsKey.soundCooldownSeconds)
		}()

		let maxVisionFPS: Double = {
			guard defaults.object(forKey: AppSettingsKey.maxVisionFPS) != nil else { return Self.default.maxVisionFPS }
			return defaults.double(forKey: AppSettingsKey.maxVisionFPS)
		}()

		let mirrorVideo: Bool = {
			guard defaults.object(forKey: AppSettingsKey.mirrorVideo) != nil else { return Self.default.mirrorVideo }
			return defaults.bool(forKey: AppSettingsKey.mirrorVideo)
		}()

		let previewStyleRaw: Int = {
			guard defaults.object(forKey: AppSettingsKey.previewStyle) != nil else { return Self.default.previewStyleRaw }
			return defaults.integer(forKey: AppSettingsKey.previewStyle)
		}()

		let alertModeRaw: Int = {
			guard defaults.object(forKey: AppSettingsKey.alertMode) != nil else { return Self.default.alertModeRaw }
			return defaults.integer(forKey: AppSettingsKey.alertMode)
		}()

		let alertSoundPath: String = {
			guard defaults.object(forKey: AppSettingsKey.alertSoundPath) != nil else { return Self.default.alertSoundPath }
			return defaults.string(forKey: AppSettingsKey.alertSoundPath) ?? Self.default.alertSoundPath
		}()

		let alertSoundVolume: Double = {
			guard defaults.object(forKey: AppSettingsKey.alertSoundVolume) != nil else { return Self.default.alertSoundVolume }
			return defaults.double(forKey: AppSettingsKey.alertSoundVolume)
		}()

		let flashColorRed: Double = {
			guard defaults.object(forKey: AppSettingsKey.flashColorRed) != nil else { return Self.default.flashColorRed }
			return defaults.double(forKey: AppSettingsKey.flashColorRed)
		}()

		let flashColorGreen: Double = {
			guard defaults.object(forKey: AppSettingsKey.flashColorGreen) != nil else { return Self.default.flashColorGreen }
			return defaults.double(forKey: AppSettingsKey.flashColorGreen)
		}()

		let flashColorBlue: Double = {
			guard defaults.object(forKey: AppSettingsKey.flashColorBlue) != nil else { return Self.default.flashColorBlue }
			return defaults.double(forKey: AppSettingsKey.flashColorBlue)
		}()

		let flashOpacity: Double = {
			guard defaults.object(forKey: AppSettingsKey.flashOpacity) != nil else { return Self.default.flashOpacity }
			return defaults.double(forKey: AppSettingsKey.flashOpacity)
		}()

		return AppSettings(
			selectedCameraID: selectedCameraID,
			soundCooldownSeconds: soundCooldownSeconds,
			maxVisionFPS: maxVisionFPS,
			mirrorVideo: mirrorVideo,
			previewStyleRaw: previewStyleRaw,
			alertModeRaw: alertModeRaw,
			alertSoundPath: alertSoundPath,
			alertSoundVolume: alertSoundVolume,
			flashColorRed: flashColorRed,
			flashColorGreen: flashColorGreen,
			flashColorBlue: flashColorBlue,
			flashOpacity: flashOpacity
		)
	}

	func save(to defaults: UserDefaults = .standard) {
		defaults.set(selectedCameraID, forKey: AppSettingsKey.selectedCameraID)
		defaults.set(soundCooldownSeconds, forKey: AppSettingsKey.soundCooldownSeconds)
		defaults.set(maxVisionFPS, forKey: AppSettingsKey.maxVisionFPS)
		defaults.set(mirrorVideo, forKey: AppSettingsKey.mirrorVideo)
		defaults.set(previewStyleRaw, forKey: AppSettingsKey.previewStyle)
		defaults.set(alertModeRaw, forKey: AppSettingsKey.alertMode)
		defaults.set(alertSoundPath, forKey: AppSettingsKey.alertSoundPath)
		defaults.set(alertSoundVolume, forKey: AppSettingsKey.alertSoundVolume)
		defaults.set(flashColorRed, forKey: AppSettingsKey.flashColorRed)
		defaults.set(flashColorGreen, forKey: AppSettingsKey.flashColorGreen)
		defaults.set(flashColorBlue, forKey: AppSettingsKey.flashColorBlue)
		defaults.set(flashOpacity, forKey: AppSettingsKey.flashOpacity)
	}
}

