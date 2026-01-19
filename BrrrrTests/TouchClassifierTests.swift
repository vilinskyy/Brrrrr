//
//  TouchClassifierTests.swift
//  BrrrrTests
//

import XCTest
@testable import Brrrr

final class TouchClassifierTests: XCTestCase {
	func testNoFaceOrHands_isNoTouch() async {
		let output = await MainActor.run {
			let classifier = TouchClassifier()
			let detections = VisionDetections(timestamp: 0, hands: [], faces: [])
			return classifier.update(with: detections)
		}
		XCTAssertEqual(output.state, .noTouch)
	}

	func testMaybeTouch_whenFingerNearFace() async {
		let output = await MainActor.run {
			let classifier = TouchClassifier(configuration: .init(smoothingAlpha: 1.0))

			let face = FaceLandmarks(
				boundingBox: NormalizedRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
				nose: [NormalizedPoint(x: 0.5, y: 0.55, confidence: 1)],
				outerLips: [NormalizedPoint(x: 0.5, y: 0.48, confidence: 1)],
				faceContour: []
			)

			// Finger close, but not within touchDistanceNormalized.
			let hand = HandLandmarks(pointsByJoint: [
				.indexTip: NormalizedPoint(x: 0.5, y: 0.58, confidence: 1),
			])

			let detections = VisionDetections(timestamp: 1, hands: [hand], faces: [face])
			return classifier.update(with: detections)
		}
		XCTAssertEqual(output.state, .maybeTouch)
	}

	func testTouching_whenFingerVeryClose() async {
		let output = await MainActor.run {
			let config = TouchClassifier.Configuration(
				smoothingAlpha: 1.0,
				maybeDistanceNormalized: 0.20,
				touchDistanceNormalized: 0.10,
				insideFaceRawConfidence: 0.70,
				maybeEnterThreshold: 0.30,
				maybeExitThreshold: 0.18,
				touchEnterThreshold: 0.78,
				touchExitThreshold: 0.58,
				faceBoxMarginNormalized: 0.0
			)
			let classifier = TouchClassifier(configuration: config)

			let face = FaceLandmarks(
				boundingBox: NormalizedRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
				nose: [NormalizedPoint(x: 0.5, y: 0.55, confidence: 1)],
				outerLips: [NormalizedPoint(x: 0.5, y: 0.48, confidence: 1)],
				faceContour: []
			)

			// Finger extremely close to nose (distance 0.005, faceScale ~0.2 => 0.025 normalized)
			let hand = HandLandmarks(pointsByJoint: [
				.indexTip: NormalizedPoint(x: 0.505, y: 0.552, confidence: 1),
			])

			let detections = VisionDetections(timestamp: 1, hands: [hand], faces: [face])
			return classifier.update(with: detections)
		}
		XCTAssertEqual(output.state, .touching)
	}
}

