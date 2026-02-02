//
//  MenuBarIndicatorLabel.swift
//  Brrrr
//

#if os(macOS)
import AppKit
import SwiftUI

struct MenuBarIndicatorLabel: View {
	let touchState: TouchState

	var body: some View {
		Image(nsImage: dotImage(color: colorForState))
			.renderingMode(.original)
	}

	private var colorForState: NSColor {
		switch touchState {
		case .noTouch:
			return .systemGray
		case .maybeTouch:
			return .systemYellow
		case .touching:
			return .systemRed
		}
	}

	private func dotImage(color: NSColor) -> NSImage {
		let size = NSSize(width: 16, height: 16)
		let image = NSImage(size: size, flipped: false) { rect in
			let circleRect = rect.insetBy(dx: 3, dy: 3)
			let path = NSBezierPath(ovalIn: circleRect)
			color.setFill()
			path.fill()
			return true
		}
		image.isTemplate = false
		return image
	}
}

#endif