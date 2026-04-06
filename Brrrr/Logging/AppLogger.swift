//
//  AppLogger.swift
//  Brrrr
//
//  Structured logging for Console.app (subsystem + category).
//

import os

enum AppLogger {
	static let general = Logger(subsystem: "com.brrrr.app", category: "general")
	static let vision = Logger(subsystem: "com.brrrr.app", category: "vision")
	static let camera = Logger(subsystem: "com.brrrr.app", category: "camera")
	static let alert = Logger(subsystem: "com.brrrr.app", category: "alert")
	static let flash = Logger(subsystem: "com.brrrr.app", category: "flash")
	static let lifecycle = Logger(subsystem: "com.brrrr.app", category: "lifecycle")
}
