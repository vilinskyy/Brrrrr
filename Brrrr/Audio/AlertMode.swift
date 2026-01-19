//
//  AlertMode.swift
//  Brrrr
//

import Foundation

enum AlertMode: Int, CaseIterable, Identifiable, Sendable {
	case soundAndScreen = 0
	case soundOnly = 1
	case screenOnly = 2

	var id: Int { rawValue }

	var displayName: String {
		switch self {
		case .soundAndScreen: "Sound & Screen"
		case .soundOnly: "Sound only"
		case .screenOnly: "Screen only"
		}
	}

	var enablesSound: Bool {
		switch self {
		case .soundAndScreen, .soundOnly: true
		case .screenOnly: false
		}
	}

	var enablesScreen: Bool {
		switch self {
		case .soundAndScreen, .screenOnly: true
		case .soundOnly: false
		}
	}
}

