//
//  IOSCameraView.swift
//  Brrrr
//

#if os(iOS)

import AVFoundation
import SwiftUI
import UIKit

final class CameraPreviewUIView: UIView {
	private let previewLayer = AVCaptureVideoPreviewLayer()
	private var isMirrored: Bool = true
	private var lastMetadataOutputRect: CGRect = .zero
	private var lastMetadataToLayerTransform: CGAffineTransform = .identity
	private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
	private var sessionDidStartObserver: NSObjectProtocol?
	private var deviceOrientationObserver: NSObjectProtocol?

	/// Reports the `AVCaptureVideoPreviewLayer` visible rect in metadata coordinates (0...1).
	/// This is the most reliable way to align an overlay with `.resizeAspectFill` cropping.
	var onMetadataOutputRectChange: ((CGRect) -> Void)?
	/// Reports a transform that maps metadata coordinates (0...1) to this view’s coordinate space.
	/// Uses `AVCaptureVideoPreviewLayer.layerRectConverted(fromMetadataOutputRect:)` so overlays match
	/// the preview layer’s exact crop/scale/rotation/mirroring.
	var onMetadataToLayerTransformChange: ((CGAffineTransform) -> Void)?

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		previewLayer.videoGravity = .resizeAspectFill
		layer.addSublayer(previewLayer)

		UIDevice.current.beginGeneratingDeviceOrientationNotifications()
		deviceOrientationObserver = NotificationCenter.default.addObserver(
			forName: UIDevice.orientationDidChangeNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?.updateRotationCoordinatorIfPossible()
			self?.applyConnectionSettingsIfPossible()
			self?.reportMetadataOutputRectIfNeeded()
		}
	}

	func setSession(_ session: AVCaptureSession) {
		if previewLayer.session !== session {
			if let sessionDidStartObserver {
				NotificationCenter.default.removeObserver(sessionDidStartObserver)
				self.sessionDidStartObserver = nil
			}

			previewLayer.session = session

			// The preview layer connection becomes available once the session is running.
			sessionDidStartObserver = NotificationCenter.default.addObserver(
				forName: AVCaptureSession.didStartRunningNotification,
				object: session,
				queue: .main
			) { [weak self] _ in
				self?.updateRotationCoordinatorIfPossible()
				self?.applyConnectionSettingsIfPossible()
				self?.reportMetadataOutputRectIfNeeded()
			}
		}

		updateRotationCoordinatorIfPossible()
		applyConnectionSettingsIfPossible()
		reportMetadataOutputRectIfNeeded()
		reportMetadataToLayerTransformIfNeeded()
	}

	func setMirrored(_ mirrored: Bool) {
		isMirrored = mirrored
		updateRotationCoordinatorIfPossible()
		applyConnectionSettingsIfPossible()
		reportMetadataOutputRectIfNeeded()
		reportMetadataToLayerTransformIfNeeded()
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		previewLayer.frame = bounds
		updateRotationCoordinatorIfPossible()
		applyConnectionSettingsIfPossible()
		reportMetadataOutputRectIfNeeded()
		reportMetadataToLayerTransformIfNeeded()
	}

	private func applyConnectionSettingsIfPossible() {
		guard let connection = previewLayer.connection else { return }

		if let rotationCoordinator {
			let angle = rotationCoordinator.videoRotationAngleForHorizonLevelPreview
			let snapped = (angle / 90).rounded() * 90
			if connection.isVideoRotationAngleSupported(snapped) {
				connection.videoRotationAngle = snapped
			}
		} else {
			// Fallback: portrait interface.
			let portraitAngle: CGFloat = 90
			if connection.isVideoRotationAngleSupported(portraitAngle) {
				connection.videoRotationAngle = portraitAngle
			}
		}
		if connection.isVideoMirroringSupported {
			connection.automaticallyAdjustsVideoMirroring = false
			connection.isVideoMirrored = isMirrored
		}
	}

	private func updateRotationCoordinatorIfPossible() {
		guard let session = previewLayer.session else { return }
		guard let deviceInput = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first else { return }
		rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: deviceInput.device, previewLayer: previewLayer)
	}

	private func reportMetadataOutputRectIfNeeded() {
		guard previewLayer.connection != nil else { return }
		guard previewLayer.bounds.width > 0, previewLayer.bounds.height > 0 else { return }

		var rect = previewLayer.metadataOutputRectConverted(fromLayerRect: previewLayer.bounds)

		// `metadataOutputRectConverted` returns coordinates in the metadata output coordinate space.
		// In portrait rotations, this space effectively swaps axes vs our Vision-normalized overlay
		// coordinate space. Transpose the rect so it matches the overlay’s expectation.
		if let connection = previewLayer.connection {
			let rawAngle = connection.videoRotationAngle
			let snapped = (rawAngle / 90).rounded() * 90
			let normalized = snapped.truncatingRemainder(dividingBy: 360)
			let angle = Int((normalized < 0 ? (normalized + 360) : normalized).rounded())
			if angle == 90 || angle == 270 {
				rect = CGRect(x: rect.origin.y, y: rect.origin.x, width: rect.size.height, height: rect.size.width)
			}
		}

		guard rect != lastMetadataOutputRect else { return }
		lastMetadataOutputRect = rect
		onMetadataOutputRectChange?(rect)
	}

	private func reportMetadataToLayerTransformIfNeeded() {
		guard previewLayer.connection != nil else { return }
		guard previewLayer.bounds.width > 0, previewLayer.bounds.height > 0 else { return }

		// Convert the unit square in metadata space into this view’s coordinate space. We do this by
		// sampling how (0,0), (1,0), and (0,1) map to layer points, and building an affine transform.
		let p0 = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 0, height: 0)).origin
		let px = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 1, y: 0, width: 0, height: 0)).origin
		let py = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 1, width: 0, height: 0)).origin

		let transform = CGAffineTransform(
			a: px.x - p0.x,
			b: px.y - p0.y,
			c: py.x - p0.x,
			d: py.y - p0.y,
			tx: p0.x,
			ty: p0.y
		)

		guard transform != lastMetadataToLayerTransform else { return }
		lastMetadataToLayerTransform = transform
		onMetadataToLayerTransformChange?(transform)
	}

	deinit {
		if let sessionDidStartObserver {
			NotificationCenter.default.removeObserver(sessionDidStartObserver)
		}
		if let deviceOrientationObserver {
			NotificationCenter.default.removeObserver(deviceOrientationObserver)
		}
		UIDevice.current.endGeneratingDeviceOrientationNotifications()
	}
}

struct IOSCameraView: UIViewRepresentable {
	let session: AVCaptureSession
	let isMirrored: Bool
	@Binding var metadataOutputRect: CGRect
	@Binding var metadataToLayerTransform: CGAffineTransform

	final class Coordinator {
		private let metadataOutputRect: Binding<CGRect>
		private let metadataToLayerTransform: Binding<CGAffineTransform>

		init(metadataOutputRect: Binding<CGRect>, metadataToLayerTransform: Binding<CGAffineTransform>) {
			self.metadataOutputRect = metadataOutputRect
			self.metadataToLayerTransform = metadataToLayerTransform
		}

		func handleMetadataRect(_ rect: CGRect) {
			// Avoid feedback loops / extra updates.
			if metadataOutputRect.wrappedValue != rect {
				metadataOutputRect.wrappedValue = rect
			}
		}

		func handleMetadataToLayerTransform(_ transform: CGAffineTransform) {
			if metadataToLayerTransform.wrappedValue != transform {
				metadataToLayerTransform.wrappedValue = transform
			}
		}
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(metadataOutputRect: $metadataOutputRect, metadataToLayerTransform: $metadataToLayerTransform)
	}

	func makeUIView(context: Context) -> CameraPreviewUIView {
		let view = CameraPreviewUIView()
		view.onMetadataOutputRectChange = { [weak coordinator = context.coordinator] rect in
			coordinator?.handleMetadataRect(rect)
		}
		view.onMetadataToLayerTransformChange = { [weak coordinator = context.coordinator] transform in
			coordinator?.handleMetadataToLayerTransform(transform)
		}
		view.setSession(session)
		view.setMirrored(isMirrored)
		return view
	}

	func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
		uiView.onMetadataOutputRectChange = { [weak coordinator = context.coordinator] rect in
			coordinator?.handleMetadataRect(rect)
		}
		uiView.onMetadataToLayerTransformChange = { [weak coordinator = context.coordinator] transform in
			coordinator?.handleMetadataToLayerTransform(transform)
		}
		uiView.setSession(session)
		uiView.setMirrored(isMirrored)
	}
}

#endif

