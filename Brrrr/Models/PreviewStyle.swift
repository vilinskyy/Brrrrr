//
//  PreviewStyle.swift
//  Brrrr
//

import Foundation

enum PreviewStyle: Int, CaseIterable, Identifiable, Sendable {
	case normal = 0
	case dots = 1

	var id: Int { rawValue }

	var displayName: String {
		switch self {
		case .normal: "Normal"
		case .dots: "Geometry"
		}
	}
}

