//
//  TouchStatsStore.swift
//  Brrrr
//

import Foundation

/// Persists a simple daily touch counter in `UserDefaults`.
struct TouchStatsStore: Sendable, Hashable {
	var day: Date
	var count: Int

	static func load(from defaults: UserDefaults, now: Date = Date(), calendar: Calendar = .current) -> TouchStatsStore {
		let storedCount = defaults.integer(forKey: AppSettingsKey.touchesTodayCount)
		let storedDate = defaults.object(forKey: AppSettingsKey.touchesTodayDate) as? Date

		if let storedDate, calendar.isDate(storedDate, inSameDayAs: now) {
			return TouchStatsStore(day: storedDate, count: storedCount)
		}

		let today = calendar.startOfDay(for: now)
		let store = TouchStatsStore(day: today, count: 0)
		store.persist(to: defaults)
		return store
	}

	func persist(to defaults: UserDefaults) {
		defaults.set(count, forKey: AppSettingsKey.touchesTodayCount)
		defaults.set(day, forKey: AppSettingsKey.touchesTodayDate)
	}
}

