//
//  TouchStatsTests.swift
//  BrrrrTests
//

import XCTest
@testable import Brrrrr

final class TouchStatsTests: XCTestCase {
	@MainActor
	func testTouchStatsLoadForToday() {
		let suiteName = "Brrrr.TouchStatsTests.\(UUID().uuidString)"
		guard let defaults = UserDefaults(suiteName: suiteName) else {
			return XCTFail("Failed to create UserDefaults suite")
		}
		defer {
			defaults.removePersistentDomain(forName: suiteName)
		}

		let now = Date()
		let today = Calendar.current.startOfDay(for: now)

		defaults.set(7, forKey: AppSettingsKey.touchesTodayCount)
		defaults.set(today, forKey: AppSettingsKey.touchesTodayDate)

		let stats = TouchStatsStore.load(from: defaults, now: now)
		XCTAssertEqual(stats.count, 7)
	}

	@MainActor
	func testTouchStatsResetOnNewDay() {
		let suiteName = "Brrrr.TouchStatsTests.\(UUID().uuidString)"
		guard let defaults = UserDefaults(suiteName: suiteName) else {
			return XCTFail("Failed to create UserDefaults suite")
		}
		defer {
			defaults.removePersistentDomain(forName: suiteName)
		}

		let now = Date()
		let today = Calendar.current.startOfDay(for: now)
		let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)

		defaults.set(5, forKey: AppSettingsKey.touchesTodayCount)
		defaults.set(yesterday, forKey: AppSettingsKey.touchesTodayDate)

		let stats = TouchStatsStore.load(from: defaults, now: now)
		XCTAssertEqual(stats.count, 0)

		let storedDate = defaults.object(forKey: AppSettingsKey.touchesTodayDate) as? Date
		XCTAssertNotNil(storedDate)
		if let storedDate {
			XCTAssertTrue(Calendar.current.isDate(storedDate, inSameDayAs: now))
		}

		XCTAssertNotNil(defaults.object(forKey: AppSettingsKey.touchesTodayCount))
	}
}
