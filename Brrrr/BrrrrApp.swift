//
//  BrrrrApp.swift
//  Brrrr
//
//  Created by Oleksandr Vilinskyi on 18/01/2026.
//

import SwiftUI

@main
struct BrrrrrApp: App {
	@StateObject private var model: TouchStateModel
	@State private var menuBarController: MenuBarController?

	private var isRunningUnitTests: Bool {
		ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
	}

	init() {
		let model = TouchStateModel()
		_model = StateObject(wrappedValue: model)

		if !isRunningUnitTests {
			_menuBarController = State(initialValue: MenuBarController(model: model))
			// Do not auto-start camera monitoring on first launch.
			if UserDefaults.standard.bool(forKey: AppSettingsKey.hasUserStartedMonitoring) {
				model.startMonitoring()
			}
		} else {
			_menuBarController = State(initialValue: nil)
		}
	}

	var body: some Scene {
		Settings {
			if isRunningUnitTests {
				EmptyView()
			} else {
				SettingsView()
					.environmentObject(model)
			}
		}
		.windowResizability(.contentSize)
		.defaultSize(width: 560, height: 840)
	}
}
