//
//  TouchStatsTests.swift
//  BrrrrTests
//

import XCTest
@testable import Brrrrr

final class TouchStatsTests: XCTestCase {
	private func withRestoredTouchDefaults(_ body: () -> Void) {
		let defaults = UserDefaults.standard
		let previousCount = defaults.object(forKey: AppSettingsKey.touchesTodayCount)
		let previousDate = defaults.object(forKey: AppSettingsKey.touchesTodayDate)

		defer {
			if let previousCount {
				defaults.set(previousCount, forKey: AppSettingsKey.touchesTodayCount)
			} else {
				defaults.removeObject(forKey: AppSettingsKey.touchesTodayCount)
			}

			if let previousDate {
				defaults.set(previousDate, forKey: AppSettingsKey.touchesTodayDate)
			} else {
				defaults.removeObject(forKey: AppSettingsKey.touchesTodayDate)
			}
		}

		body()
	}

	@MainActor
	func testTouchStatsLoadForToday() {
		withRestoredTouchDefaults {
			let defaults = UserDefaults.standard
			let now = Date()
			let today = Calendar.current.startOfDay(for: now)

			defaults.set(7, forKey: AppSettingsKey.touchesTodayCount)
			defaults.set(today, forKey: AppSettingsKey.touchesTodayDate)

			let model = TouchStateModel()
			XCTAssertEqual(model.touchesToday, 7)
		}
	}

	@MainActor
	func testTouchStatsResetOnNewDay() {
		withRestoredTouchDefaults {
			let defaults = UserDefaults.standard
			let now = Date()
			let today = Calendar.current.startOfDay(for: now)
			let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)

			defaults.set(5, forKey: AppSettingsKey.touchesTodayCount)
			defaults.set(yesterday, forKey: AppSettingsKey.touchesTodayDate)

			let model = TouchStateModel()
			XCTAssertEqual(model.touchesToday, 0)

			let storedDate = defaults.object(forKey: AppSettingsKey.touchesTodayDate) as? Date
			XCTAssertNotNil(storedDate)
			if let storedDate {
				XCTAssertTrue(Calendar.current.isDate(storedDate, inSameDayAs: now))
			}

			XCTAssertNotNil(defaults.object(forKey: AppSettingsKey.touchesTodayCount))
		}
	}
}
