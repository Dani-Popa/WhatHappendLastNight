import SwiftUI

@main
struct WhatHappenedLastNightApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark) // Lock to eye-soothing night/midnight mode
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}

