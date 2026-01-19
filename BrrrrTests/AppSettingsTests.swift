//
//  AppSettingsTests.swift
//  BrrrrTests
//

import XCTest
@testable import Brrrr

final class AppSettingsTests: XCTestCase {
	func testRoundTripSaveLoad() {
		let suiteName = "Brrrr.AppSettingsTests.\(UUID().uuidString)"
		guard let defaults = UserDefaults(suiteName: suiteName) else {
			return XCTFail("Failed to create UserDefaults suite")
		}
		defer {
			defaults.removePersistentDomain(forName: suiteName)
		}

		let settings = AppSettings(
			selectedCameraID: "camera-123",
			soundCooldownSeconds: 7,
			maxVisionFPS: 9,
			mirrorVideo: false,
			previewStyleRaw: PreviewStyle.dots.rawValue,
			alertModeRaw: AlertMode.screenOnly.rawValue,
			alertSoundPath: "/System/Library/Sounds/Basso.aiff",
			alertSoundVolume: 0.42,
			flashColorRed: 0.1,
			flashColorGreen: 0.2,
			flashColorBlue: 0.3,
			flashOpacity: 0.75
		)

		settings.save(to: defaults)
		let loaded = AppSettings.load(from: defaults)

		XCTAssertEqual(loaded, settings)
	}

	func testLoadUsesDefaultsWhenKeysMissing() {
		let suiteName = "Brrrr.AppSettingsTests.\(UUID().uuidString)"
		guard let defaults = UserDefaults(suiteName: suiteName) else {
			return XCTFail("Failed to create UserDefaults suite")
		}
		defer {
			defaults.removePersistentDomain(forName: suiteName)
		}

		let loaded = AppSettings.load(from: defaults)
		XCTAssertEqual(loaded, .default)
	}
}

