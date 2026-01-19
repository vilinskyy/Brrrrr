//
//  TechnicalDotsOverlayView.swift
//  Brrrr
//

import SwiftUI

/// Renders a "technical" dots/skeleton-like visualization from Vision landmarks.
struct TechnicalDotsOverlayView: View {
	let detections: VisionDetections?

	var body: some View {
		Canvas { context, size in
			drawGrid(context: context, size: size)

			guard let detections else { return }

			// Face landmarks
			for face in detections.faces {
				drawDots(face.faceContour, color: .cyan.opacity(0.85), radius: 2.0, in: &context, size: size)
				drawDots(face.outerLips, color: .pink.opacity(0.85), radius: 2.0, in: &context, size: size)
				drawDots(face.nose, color: .green.opacity(0.85), radius: 2.0, in: &context, size: size)
			}

			// Hands (currently fingertips only)
			for hand in detections.hands {
				drawHandDots(hand, in: &context, size: size)
			}
		}
		.allowsHitTesting(false)
	}

	// MARK: - Drawing

	private func drawGrid(context: GraphicsContext, size: CGSize) {
		let spacing: CGFloat = 22
		var path = Path()

		for x in stride(from: 0, through: size.width, by: spacing) {
			path.move(to: CGPoint(x: x, y: 0))
			path.addLine(to: CGPoint(x: x, y: size.height))
		}

		for y in stride(from: 0, through: size.height, by: spacing) {
			path.move(to: CGPoint(x: 0, y: y))
			path.addLine(to: CGPoint(x: size.width, y: y))
		}

		context.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 1)
	}

	private func drawHandDots(_ hand: HandLandmarks, in context: inout GraphicsContext, size: CGSize) {
		for point in hand.pointsByJoint.values {
			let p = toPoint(point, size: size)
			let radius = CGFloat(2.5 + (point.confidence * 2.0))
			let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
			context.fill(Path(ellipseIn: rect), with: .color(.yellow.opacity(0.90)))
		}
	}

	private func drawDots(_ points: [NormalizedPoint], color: Color, radius: CGFloat, in context: inout GraphicsContext, size: CGSize) {
		for point in points {
			let p = toPoint(point, size: size)
			let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
			context.fill(Path(ellipseIn: rect), with: .color(color))
		}
	}

	private func toPoint(_ p: NormalizedPoint, size: CGSize) -> CGPoint {
		let x = CGFloat(p.x) * size.width
		let y = (1 - CGFloat(p.y)) * size.height
		return CGPoint(x: x, y: y)
	}
}

