//
//  TechnicalDotsOverlayView.swift
//  Brrrr
//

import SwiftUI

/// Renders a "technical" dots/skeleton-like visualization from Vision landmarks.
struct TechnicalDotsOverlayView: View {
	let detections: VisionDetections?
	/// Visible region of the camera feed in metadata coordinates (0...1), as reported by
	/// `AVCaptureVideoPreviewLayer.metadataOutputRectConverted(fromLayerRect:)`.
	///
	/// Using this avoids drift/stretch when the preview uses `.resizeAspectFill` cropping.
	var metadataOutputRect: CGRect? = nil
	/// Whether the UI preview is mirrored (front camera style).
	var isMirrored: Bool = false
	/// Transform mapping metadata coordinates (0...1) to view coordinates, derived from
	/// `AVCaptureVideoPreviewLayer.layerRectConverted(fromMetadataOutputRect:)`.
	/// When provided, it is the most reliable way to align dots to the preview layer.
	var metadataToLayerTransform: CGAffineTransform? = nil

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
		// Vision coordinates are normalized with origin at bottom-left.
		// Preview layer metadata coordinates are normalized with origin at top-left.
		let x = CGFloat(p.x)
		let y = 1 - CGFloat(p.y)

		if let metadataToLayerTransform {
			// Let the preview-layer-derived transform handle crop/scale/rotation/mirroring.
			return CGPoint(x: x, y: y).applying(metadataToLayerTransform)
		}

		var xx = x
		var yy = y

		if let rect = metadataOutputRect, rect.width > 0, rect.height > 0 {
			xx = (xx - rect.origin.x) / rect.width
			yy = (yy - rect.origin.y) / rect.height
		}

		if isMirrored {
			xx = 1 - xx
		}

		return CGPoint(x: xx * size.width, y: yy * size.height)
	}
}

