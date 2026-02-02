//
//  VisionPipeline.swift
//  Brrrr
//
//  Runs on-device Vision hand + face landmark detection (no training, no network).
//

import AVFoundation
import CoreImage
import Foundation
import Vision

private extension NSLock {
	nonisolated func withLock<T>(_ body: () -> T) -> T {
		lock()
		defer { unlock() }
		return body()
	}
}

enum TouchDetectionVisionJoint: String, CaseIterable, Sendable {
	case thumbTip
	case indexTip
	case middleTip
	case ringTip
	case littleTip
}

struct NormalizedRect: Sendable, Hashable {
	var x: Double
	var y: Double
	var width: Double
	var height: Double
}

struct NormalizedPoint: Sendable, Hashable {
	var x: Double
	var y: Double
	var confidence: Double
}

struct HandLandmarks: Sendable, Hashable {
	var pointsByJoint: [TouchDetectionVisionJoint: NormalizedPoint]
}

struct FaceLandmarks: Sendable, Hashable {
	var boundingBox: NormalizedRect
	var nose: [NormalizedPoint]
	var outerLips: [NormalizedPoint]
	var faceContour: [NormalizedPoint]
}

struct VisionDetections: Sendable, Hashable {
	var timestamp: Double
	var hands: [HandLandmarks]
	var faces: [FaceLandmarks]
	/// Source frame dimensions used for Vision (pixel buffer size).
	/// Used to align the dots overlay with aspect-fill video previews.
	var frameWidth: Int = 0
	var frameHeight: Int = 0
}

/// AVCapture video output delegate that produces `VisionDetections`.
///
/// - Important: The capture callback is invoked on the queue provided to
///   `AVCaptureVideoDataOutput.setSampleBufferDelegate`. This class is designed to be
///   used on a single serial queue.
final class VisionPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
	/// Deliver detections from the capture callback queue (caller can hop to MainActor).
	nonisolated var onDetections: (@Sendable (VisionDetections) -> Void)? {
		get { configLock.withLock { _onDetections } }
		set { configLock.withLock { _onDetections = newValue } }
	}

	/// Deliver preview frames (as `CGImage`) from the capture callback queue.
	nonisolated var onPreviewFrame: (@Sendable (CGImage) -> Void)? {
		get { configLock.withLock { _onPreviewFrame } }
		set { configLock.withLock { _onPreviewFrame = newValue } }
	}

	/// Visual style of the preview frames.
	nonisolated var previewStyle: PreviewStyle {
		get { configLock.withLock { _previewStyle } }
		set { configLock.withLock { _previewStyle = newValue } }
	}

	/// Throttle Vision work to reduce CPU usage.
	nonisolated var maxFPS: Double {
		get { configLock.withLock { _maxFPS } }
		set { configLock.withLock { _maxFPS = max(0, newValue) } }
	}

	private let configLock = NSLock()
	nonisolated(unsafe) private var _onDetections: (@Sendable (VisionDetections) -> Void)?
	nonisolated(unsafe) private var _onPreviewFrame: (@Sendable (CGImage) -> Void)?
	nonisolated(unsafe) private var _previewStyle: PreviewStyle = .normal
	nonisolated(unsafe) private var _maxFPS: Double = 12

	private let minHandConfidence: Float = 0.30
	nonisolated private let previewCIContext = CIContext(options: nil)

	nonisolated(unsafe) private let handRequest: VNDetectHumanHandPoseRequest = {
		let request = VNDetectHumanHandPoseRequest()
		request.maximumHandCount = 2
		return request
	}()

	nonisolated(unsafe) private let faceRequest: VNDetectFaceLandmarksRequest = {
		let request = VNDetectFaceLandmarksRequest()
		return request
	}()

	nonisolated(unsafe) private let sequenceHandler = VNSequenceRequestHandler()
	nonisolated(unsafe) private var lastAnalysisTime: CFTimeInterval = 0

	// MARK: AVCaptureVideoDataOutputSampleBufferDelegate

	nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
		let frameWidth = CVPixelBufferGetWidth(pixelBuffer)
		let frameHeight = CVPixelBufferGetHeight(pixelBuffer)

		let now = CACurrentMediaTime()
		let configuredFPS = maxFPS
		let minInterval = (configuredFPS > 0) ? (1.0 / configuredFPS) : 0
		if (now - lastAnalysisTime) < minInterval {
			return
		}
		lastAnalysisTime = now

		let orientation: CGImagePropertyOrientation = {
			#if os(iOS)
			return Self.cgImageOrientation(from: connection)
			#else
			// macOS camera frames are effectively "up" oriented for our use case.
			return .up
			#endif
		}()

		do {
			// Preview frames are only emitted for the "normal" preview mode.
			// In "dots" mode, the UI renders an overlay from Vision detections instead of showing raw video.
			if previewStyle == .normal, let previewCallback = onPreviewFrame {
				let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
				if let cgImage = previewCIContext.createCGImage(ciImage, from: ciImage.extent) {
					previewCallback(cgImage)
				}
			}

			try sequenceHandler.perform([handRequest, faceRequest], on: pixelBuffer, orientation: orientation)

			let hands = (handRequest.results ?? []).map { observation in
				HandLandmarks(pointsByJoint: self.extractFingertips(from: observation))
			}

			let faces = (faceRequest.results ?? []).map { observation in
				self.extractFaceLandmarks(from: observation)
			}

			onDetections?(
				VisionDetections(
					timestamp: now,
					hands: hands,
					faces: faces,
					frameWidth: frameWidth,
					frameHeight: frameHeight
				)
			)
		} catch {
			// Swallow errors; transient failures are expected on real-world frames.
		}
	}

	#if os(iOS)
	nonisolated private static func cgImageOrientation(from connection: AVCaptureConnection) -> CGImagePropertyOrientation {
		let rawAngle = connection.videoRotationAngle
		let snapped = (rawAngle / 90).rounded() * 90
		let normalized = snapped.truncatingRemainder(dividingBy: 360)
		let angle = Int((normalized < 0 ? (normalized + 360) : normalized).rounded())

		let base: CGImagePropertyOrientation = switch angle {
		case 0: .up
		case 90: .right
		case 180: .down
		case 270: .left
		default: .up
		}

		guard connection.isVideoMirrored else { return base }
		return switch base {
		case .up: .upMirrored
		case .down: .downMirrored
		case .left: .leftMirrored
		case .right: .rightMirrored
		default: base
		}
	}
	#endif

	// MARK: - Extraction

	nonisolated private func extractFingertips(from observation: VNHumanHandPoseObservation) -> [TouchDetectionVisionJoint: NormalizedPoint] {
		var out: [TouchDetectionVisionJoint: NormalizedPoint] = [:]

		let mapping: [(TouchDetectionVisionJoint, VNHumanHandPoseObservation.JointName)] = [
			(.thumbTip, .thumbTip),
			(.indexTip, .indexTip),
			(.middleTip, .middleTip),
			(.ringTip, .ringTip),
			(.littleTip, .littleTip),
		]

		for (joint, vnJoint) in mapping {
			guard let point = try? observation.recognizedPoint(vnJoint) else { continue }
			guard point.confidence >= minHandConfidence else { continue }
			out[joint] = NormalizedPoint(
				x: Double(point.location.x),
				y: Double(point.location.y),
				confidence: Double(point.confidence)
			)
		}

		return out
	}

	nonisolated private func extractFaceLandmarks(from observation: VNFaceObservation) -> FaceLandmarks {
		let bbox = observation.boundingBox
		let bboxNormalized = NormalizedRect(
			x: Double(bbox.origin.x),
			y: Double(bbox.origin.y),
			width: Double(bbox.size.width),
			height: Double(bbox.size.height)
		)

		let nose = mapRegion(observation.landmarks?.nose, in: bbox)
		let outerLips = mapRegion(observation.landmarks?.outerLips, in: bbox)
		let faceContour = mapRegion(observation.landmarks?.faceContour, in: bbox)

		return FaceLandmarks(
			boundingBox: bboxNormalized,
			nose: nose,
			outerLips: outerLips,
			faceContour: faceContour
		)
	}

	nonisolated private func mapRegion(_ region: VNFaceLandmarkRegion2D?, in faceBoundingBox: CGRect) -> [NormalizedPoint] {
		guard let region else { return [] }

		return region.normalizedPoints.map { p in
			let x = faceBoundingBox.origin.x + (p.x * faceBoundingBox.size.width)
			let y = faceBoundingBox.origin.y + (p.y * faceBoundingBox.size.height)
			return NormalizedPoint(x: Double(x), y: Double(y), confidence: 1.0)
		}
	}
}

