//
//  TouchClassifier.swift
//  Brrrr
//
//  Classifies face touching into 3 states using Vision landmarks (no training).
//

import Foundation

enum TouchState: Int, Comparable, Sendable {
	case noTouch = 0
	case maybeTouch = 1
	case touching = 2

	static func < (lhs: TouchState, rhs: TouchState) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

struct TouchClassifierOutput: Sendable, Hashable {
	var state: TouchState
	var rawConfidence: Double
	var smoothedConfidence: Double
	var minDistanceToFace: Double?
	var minDistanceToFaceNormalized: Double?
	var insideFaceBox: Bool
	var hasFace: Bool
	var hasHand: Bool
}

/// Stateful classifier with smoothing + hysteresis to reduce flicker.
final class TouchClassifier {
	struct Configuration: Sendable, Hashable {
		/// Exponential moving average weight for new samples \(\(0...1)\).
		var smoothingAlpha: Double = 0.25

		/// Distance thresholds are normalized by the detected face size.
		var maybeDistanceNormalized: Double = 0.16
		var touchDistanceNormalized: Double = 0.09

		/// If a fingertip overlaps the face bounding box, treat as partial evidence (still not "definite").
		var insideFaceRawConfidence: Double = 0.70

		/// Hysteresis thresholds on smoothed confidence.
		var maybeEnterThreshold: Double = 0.30
		var maybeExitThreshold: Double = 0.18
		var touchEnterThreshold: Double = 0.78
		var touchExitThreshold: Double = 0.58

		/// Expand the face bounding box by this margin (relative to face size) when checking overlap.
		var faceBoxMarginNormalized: Double = 0.06
	}

	private(set) var configuration: Configuration

	private var state: TouchState = .noTouch
	private var smoothedConfidence: Double = 0

	init(configuration: Configuration = Configuration()) {
		self.configuration = configuration
	}

	func reset() {
		state = .noTouch
		smoothedConfidence = 0
	}

	func update(with detections: VisionDetections) -> TouchClassifierOutput {
		let metrics = computeRawMetrics(detections: detections)

		let alpha = clamp(configuration.smoothingAlpha, min: 0, max: 1)
		smoothedConfidence = smoothedConfidence + alpha * (metrics.rawConfidence - smoothedConfidence)

		applyHysteresis(smoothed: smoothedConfidence)

		return TouchClassifierOutput(
			state: state,
			rawConfidence: metrics.rawConfidence,
			smoothedConfidence: smoothedConfidence,
			minDistanceToFace: metrics.minDistance,
			minDistanceToFaceNormalized: metrics.minDistanceNormalized,
			insideFaceBox: metrics.insideFaceBox,
			hasFace: metrics.hasFace,
			hasHand: metrics.hasHand
		)
	}

	// MARK: - Private

	private struct RawMetrics {
		var rawConfidence: Double
		var minDistance: Double?
		var minDistanceNormalized: Double?
		var insideFaceBox: Bool
		var hasFace: Bool
		var hasHand: Bool
	}

	private func applyHysteresis(smoothed: Double) {
		switch state {
		case .noTouch:
			if smoothed >= configuration.touchEnterThreshold {
				state = .touching
			} else if smoothed >= configuration.maybeEnterThreshold {
				state = .maybeTouch
			}
		case .maybeTouch:
			if smoothed >= configuration.touchEnterThreshold {
				state = .touching
			} else if smoothed <= configuration.maybeExitThreshold {
				state = .noTouch
			}
		case .touching:
			if smoothed <= configuration.touchExitThreshold {
				// Drop to maybe or none depending on where we landed.
				state = (smoothed >= configuration.maybeEnterThreshold) ? .maybeTouch : .noTouch
			}
		}
	}

	private func computeRawMetrics(detections: VisionDetections) -> RawMetrics {
		guard let face = detections.faces.max(by: { faceArea($0) < faceArea($1) }) else {
			return RawMetrics(
				rawConfidence: 0,
				minDistance: nil,
				minDistanceNormalized: nil,
				insideFaceBox: false,
				hasFace: false,
				hasHand: !detections.hands.isEmpty
			)
		}

		let fingertips: [NormalizedPoint] = detections.hands.flatMap { hand in
			hand.pointsByJoint.values
		}

		guard !fingertips.isEmpty else {
			return RawMetrics(
				rawConfidence: 0,
				minDistance: nil,
				minDistanceNormalized: nil,
				insideFaceBox: false,
				hasFace: true,
				hasHand: false
			)
		}

		let faceScale = max(face.boundingBox.width, face.boundingBox.height)
		let margin = configuration.faceBoxMarginNormalized * faceScale

		let faceMinX = face.boundingBox.x - margin
		let faceMaxX = face.boundingBox.x + face.boundingBox.width + margin
		let faceMinY = face.boundingBox.y - margin
		let faceMaxY = face.boundingBox.y + face.boundingBox.height + margin

		let insideFaceBox = fingertips.contains { p in
			p.x >= faceMinX && p.x <= faceMaxX && p.y >= faceMinY && p.y <= faceMaxY
		}

		let facePoints = (face.nose + face.outerLips + face.faceContour)

		let fallbackFacePoint = NormalizedPoint(
			x: face.boundingBox.x + (face.boundingBox.width / 2),
			y: face.boundingBox.y + (face.boundingBox.height / 2),
			confidence: 1
		)
		let targets = facePoints.isEmpty ? [fallbackFacePoint] : facePoints

		var minDist: Double = .infinity
		for finger in fingertips {
			for target in targets {
				let dx = finger.x - target.x
				let dy = finger.y - target.y
				let d = (dx * dx + dy * dy).squareRoot()
				if d < minDist { minDist = d }
			}
		}

		let normalized = minDist / max(faceScale, 1e-6)

		var raw: Double = 0
		if normalized <= configuration.touchDistanceNormalized {
			raw = 1.0
		} else if normalized <= configuration.maybeDistanceNormalized {
			raw = 0.60
		}

		if insideFaceBox {
			raw = max(raw, configuration.insideFaceRawConfidence)
		}

		return RawMetrics(
			rawConfidence: raw,
			minDistance: minDist.isFinite ? minDist : nil,
			minDistanceNormalized: minDist.isFinite ? normalized : nil,
			insideFaceBox: insideFaceBox,
			hasFace: true,
			hasHand: true
		)
	}

	private func faceArea(_ face: FaceLandmarks) -> Double {
		face.boundingBox.width * face.boundingBox.height
	}

	private func clamp(_ value: Double, min: Double, max: Double) -> Double {
		Swift.max(min, Swift.min(max, value))
	}
}

