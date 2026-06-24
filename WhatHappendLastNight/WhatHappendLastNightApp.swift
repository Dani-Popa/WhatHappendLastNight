import SwiftUI

@main
struct WhatHappenedLastNightApp: App {
    @StateObject private var theme = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(theme)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            // macOS-native: View > Appearance > System / Light / Dark
            // Matches Mail / Safari rather than putting a toggle in the toolbar.
            CommandGroup(after: .toolbar) {
                Menu("Appearance") {
                    ForEach(AppearancePreference.allCases) { pref in
                        Button {
                            theme.preference = pref
                        } label: {
                            HStack {
                                Image(systemName: pref.sfSymbol)
                                Text(pref.label)
                                if theme.preference == pref {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .keyboardShortcut(shortcutKey(for: pref), modifiers: [.command, .option])
                    }
                }
            }
        }
    }

    private func shortcutKey(for pref: AppearancePreference) -> KeyEquivalent {
        switch pref {
        case .system: return "0"
        case .light:  return "1"
        case .dark:   return "2"
        }
    }
}
