//
//  SystemSoundLibrary.swift
//  Brrrr
//

import Foundation

struct SystemSoundItem: Identifiable, Sendable, Hashable {
	let id: String
	let name: String
	let url: URL
}

enum SystemSoundLibrary {
	/// Known locations for built-in and user-installed sounds.
	static let soundDirectories: [URL] = [
		URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true),
		URL(fileURLWithPath: "/Library/Sounds", isDirectory: true),
	]

	static func availableSounds(fileManager: FileManager = .default) -> [SystemSoundItem] {
		var items: [SystemSoundItem] = []

		for dir in soundDirectories {
			guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
				continue
			}
			for case let url as URL in enumerator {
				guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
				guard ["aiff", "aif", "wav", "caf", "mp3", "m4a"].contains(url.pathExtension.lowercased()) else { continue }
				let name = url.deletingPathExtension().lastPathComponent
				items.append(SystemSoundItem(id: url.path, name: name, url: url))
			}
		}

		// Deduplicate by id (path) and sort by display name.
		return Array(Set(items)).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}
}

