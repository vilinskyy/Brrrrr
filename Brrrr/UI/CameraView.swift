//
//  CameraView.swift
//  Brrrr
//

#if os(macOS)
import AVFoundation
import SwiftUI

final class CameraPreviewNSView: NSView {
	private let previewLayer = AVCaptureVideoPreviewLayer()
	private var isMirrored: Bool = true

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		wantsLayer = true
		layer = CALayer()

		previewLayer.videoGravity = .resizeAspectFill
		layer?.addSublayer(previewLayer)
	}

	func setSession(_ session: AVCaptureSession) {
		previewLayer.session = session
		applyMirroringIfPossible()
	}

	func setMirrored(_ mirrored: Bool) {
		isMirrored = mirrored
		applyMirroringIfPossible()
	}

	override func layout() {
		super.layout()
		previewLayer.frame = bounds
	}

	private func applyMirroringIfPossible() {
		guard let connection = previewLayer.connection else { return }
		guard connection.isVideoMirroringSupported else { return }
		connection.automaticallyAdjustsVideoMirroring = false
		connection.isVideoMirrored = isMirrored
	}
}

struct CameraView: NSViewRepresentable {
	let session: AVCaptureSession
	let isMirrored: Bool

	func makeNSView(context: Context) -> CameraPreviewNSView {
		let view = CameraPreviewNSView()
		view.setSession(session)
		view.setMirrored(isMirrored)
		return view
	}

	func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
		nsView.setSession(session)
		nsView.setMirrored(isMirrored)
	}
}

#endif