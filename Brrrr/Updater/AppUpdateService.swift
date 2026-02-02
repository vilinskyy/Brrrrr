//
//  AppUpdateService.swift
//  Brrrr
//

#if os(macOS)
import AppKit
import Combine
import Foundation
import StoreKit

@MainActor
final class AppUpdateService: ObservableObject {
	static let shared = AppUpdateService()

	enum State: Equatable {
		case idle
		case checking
		case upToDate
		case updateAvailable(latestVersion: String)
		case downloading
		case downloaded(fileName: String)
		case error(message: String)
	}

	@Published private(set) var state: State = .idle
	@Published private(set) var isDirectDistribution: Bool = true

	// Direct distribution uses GitHub Releases (see README).
	private let owner = "vilinskyy"
	private let repo = "Brrrr"

	private init() {
		refreshDistributionStatus()
	}

	// MARK: - Public

	func checkForUpdates() {
		NSApp.activate(ignoringOtherApps: true)

		guard isDirectDistribution else {
			showInfoAlert(
				title: "Updates",
				message: "This copy of Brrrrr was installed from the Mac App Store. Updates are delivered by the App Store."
			)
			return
		}

		Task { @MainActor [weak self] in
			await self?.checkForUpdatesAndOfferDownload()
		}
	}

	// MARK: - Private

	private func refreshDistributionStatus() {
		Task { @MainActor [weak self] in
			self?.isDirectDistribution = await Self.isDirectDistributionUsingStoreKit()
		}
	}

	private static func isDirectDistributionUsingStoreKit() async -> Bool {
		if #available(macOS 15.0, *) {
			do {
				let result = try await AppTransaction.shared
				switch result {
				case .verified(_):
					return false
				case .unverified(_, _):
					return false
				}
			} catch {
				return true
			}
		} else {
			// Fallback for macOS 13–14: use deprecated appStoreReceiptURL
			guard let receiptURL = Bundle.main.appStoreReceiptURL else { return true }
			return !FileManager.default.fileExists(atPath: receiptURL.path)
		}
	}

	private func checkForUpdatesAndOfferDownload() async {
		state = .checking

		do {
			let latest = try await fetchLatestRelease()
			let current = currentAppVersion

			guard let currentVer = SemanticVersion(current), let latestVer = SemanticVersion(latest.version) else {
				state = .error(message: "Couldn't parse version numbers (current: \(current), latest: \(latest.version)).")
				if showErrorAlertAndOfferReleases(message: "Couldn't parse version numbers.") {
					NSWorkspace.shared.open(latest.releasePageURL)
				}
				return
			}

			guard latestVer > currentVer else {
				state = .upToDate
				showInfoAlert(title: "You're up to date", message: "Brrrrr \(current) is the latest version.")
				return
			}

			state = .updateAvailable(latestVersion: latest.version)
			let choice = showUpdateAvailableAlert(current: current, latest: latest.version)

			switch choice {
			case .download:
				guard let asset = latest.preferredDownloadAsset else {
					if showErrorAlertAndOfferReleases(message: "No downloadable asset found for the latest release.") {
						NSWorkspace.shared.open(latest.releasePageURL)
					}
					return
				}
				await downloadAndReveal(asset: asset, releasePageURL: latest.releasePageURL)

			case .openReleasePage:
				NSWorkspace.shared.open(latest.releasePageURL)

			case .cancel:
				state = .idle
			}
		} catch {
			state = .error(message: error.localizedDescription)
			if showErrorAlertAndOfferReleases(message: "Update check failed: \(error.localizedDescription)") {
				NSWorkspace.shared.open(releasesLatestURL)
			}
		}
	}

	private func downloadAndReveal(asset: GitHubRelease.Asset, releasePageURL: URL) async {
		state = .downloading

		do {
			let (tempURL, _) = try await URLSession.shared.download(from: asset.downloadURL)
			let fileURL = try moveDownloadedFile(tempURL: tempURL, fileName: asset.name)

			state = .downloaded(fileName: asset.name)

			// Open the downloaded DMG/ZIP and also reveal it in Finder.
			NSWorkspace.shared.open(fileURL)
			NSWorkspace.shared.activateFileViewerSelecting([fileURL])

			showInfoAlert(title: "Download complete", message: "Downloaded \(asset.name).")
		} catch {
			state = .error(message: error.localizedDescription)
			if showErrorAlertAndOfferReleases(message: "Download failed: \(error.localizedDescription)") {
				NSWorkspace.shared.open(releasePageURL)
			}
		}
	}

	private func moveDownloadedFile(tempURL: URL, fileName: String) throws -> URL {
		let fm = FileManager.default

		let appSupport = try fm.url(
			for: .applicationSupportDirectory,
			in: .userDomainMask,
			appropriateFor: nil,
			create: true
		)

		let updatesDir = appSupport
			.appendingPathComponent("Brrrrr", isDirectory: true)
			.appendingPathComponent("Updates", isDirectory: true)

		try fm.createDirectory(at: updatesDir, withIntermediateDirectories: true)

		let destination = updatesDir.appendingPathComponent(fileName, isDirectory: false)
		if fm.fileExists(atPath: destination.path) {
			try? fm.removeItem(at: destination)
		}

		try fm.moveItem(at: tempURL, to: destination)
		return destination
	}

	private var currentAppVersion: String {
		Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
	}

	private var releasesLatestURL: URL {
		URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!
	}

	// MARK: - Alerts

	private enum UpdateChoice {
		case download
		case openReleasePage
		case cancel
	}

	private func showUpdateAvailableAlert(current: String, latest: String) -> UpdateChoice {
		let alert = NSAlert()
		alert.alertStyle = .informational
		alert.messageText = "Update Available"
		alert.informativeText = "Brrrrr \(latest) is available (you have \(current))."
		alert.addButton(withTitle: "Download")
		alert.addButton(withTitle: "View Releases")
		alert.addButton(withTitle: "Cancel")

		switch alert.runModal() {
		case .alertFirstButtonReturn: return .download
		case .alertSecondButtonReturn: return .openReleasePage
		default: return .cancel
		}
	}

	private func showInfoAlert(title: String, message: String) {
		let alert = NSAlert()
		alert.alertStyle = .informational
		alert.messageText = title
		alert.informativeText = message
		alert.addButton(withTitle: "OK")
		_ = alert.runModal()
	}

	private func showErrorAlert(message: String) {
		let alert = NSAlert()
		alert.alertStyle = .warning
		alert.messageText = "Updater"
		alert.informativeText = message
		alert.addButton(withTitle: "OK")
		_ = alert.runModal()
	}

	private func showErrorAlertAndOfferReleases(message: String) -> Bool {
		let alert = NSAlert()
		alert.alertStyle = .warning
		alert.messageText = "Updater"
		alert.informativeText = message
		alert.addButton(withTitle: "Open Releases")
		alert.addButton(withTitle: "Cancel")
		return alert.runModal() == .alertFirstButtonReturn
	}
}

// MARK: - GitHub API

private struct GitHubRelease: Decodable, Sendable {
	struct Asset: Decodable, Sendable {
		let name: String
		let downloadURL: URL

		private enum CodingKeys: String, CodingKey {
			case name
			case downloadURL = "browser_download_url"
		}
	}

	let tagName: String
	let releasePageURL: URL
	let assets: [Asset]

	var version: String {
		tagName.trimmingCharacters(in: .whitespacesAndNewlines)
			.trimmingPrefix("v")
			.trimmingPrefix("V")
	}

	var preferredDownloadAsset: Asset? {
		// Prefer a DMG for direct installs; fall back to ZIP.
		if let dmg = assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) { return dmg }
		if let zip = assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) { return zip }
		return nil
	}

	private enum CodingKeys: String, CodingKey {
		case tagName = "tag_name"
		case releasePageURL = "html_url"
		case assets
	}
}

private extension AppUpdateService {
	func fetchLatestRelease() async throws -> GitHubRelease {
		let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
		let (data, response) = try await URLSession.shared.data(from: url)

		if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
			throw NSError(domain: "Updater", code: http.statusCode, userInfo: [
				NSLocalizedDescriptionKey: "GitHub returned HTTP \(http.statusCode).",
			])
		}

		return try JSONDecoder().decode(GitHubRelease.self, from: data)
	}
}

// MARK: - Version comparison

private struct SemanticVersion: Comparable, Sendable {
	let parts: [Int]

	init?(_ raw: String) {
		let cleaned = raw
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true).first
			.map(String.init) ?? ""

		let pieces = cleaned.split(separator: ".").map(String.init)
		guard !pieces.isEmpty else { return nil }

		var numbers: [Int] = []
		numbers.reserveCapacity(pieces.count)
		for p in pieces {
			guard let n = Int(p) else { return nil }
			numbers.append(n)
		}
		self.parts = numbers
	}

	static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
		let maxCount = max(lhs.parts.count, rhs.parts.count)
		for i in 0..<maxCount {
			let l = i < lhs.parts.count ? lhs.parts[i] : 0
			let r = i < rhs.parts.count ? rhs.parts[i] : 0
			if l != r { return l < r }
		}
		return false
	}
}

private extension String {
	func trimmingPrefix(_ prefix: String) -> String {
		guard hasPrefix(prefix) else { return self }
		return String(dropFirst(prefix.count))
	}
}

#endif