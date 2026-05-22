#if canImport(AppIntents)
import AppIntents
import BlueSkyTemplatesApp

@available(iOS 17.0, *)
struct BlueSkyTemplatesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateTemplateIntent(),
            phrases: [
                "Create a template in \(.applicationName)",
                "Add a template to \(.applicationName)",
            ],
            shortTitle: "Create Template",
            systemImageName: "doc.badge.plus"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .blue }
}
#endif
