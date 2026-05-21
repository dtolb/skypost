// HomeAction routing — covers the pure helper that maps a HomeView
// quick-action tap onto parent-owned state (the TabView selection and
// the New-Template sheet binding). The helper is extracted so action
// routing is unit-testable without standing up a SwiftUI host.

import Testing
@testable import BlueSkyTemplatesApp

@Suite("HomeAction routing")
@MainActor
struct HomeActionRoutingTests {

    @Test
    func composeActionFlipsTabToCompose() {
        var tab: AppTab = .home
        var sheet = false

        handleHomeAction(.compose, selectedTab: &tab, newTemplateSheetPresented: &sheet)

        #expect(tab == .compose)
        #expect(sheet == false)
    }

    @Test
    func templatesActionFlipsTabToTemplates() {
        var tab: AppTab = .home
        var sheet = false

        handleHomeAction(.templates, selectedTab: &tab, newTemplateSheetPresented: &sheet)

        #expect(tab == .templates)
        #expect(sheet == false)
    }

    @Test
    func settingsActionFlipsTabToSettings() {
        var tab: AppTab = .home
        var sheet = false

        handleHomeAction(.settings, selectedTab: &tab, newTemplateSheetPresented: &sheet)

        #expect(tab == .settings)
        #expect(sheet == false)
    }

    @Test
    func newTemplateActionFlipsSheetWithoutTabChange() {
        var tab: AppTab = .home
        var sheet = false

        handleHomeAction(.newTemplate, selectedTab: &tab, newTemplateSheetPresented: &sheet)

        #expect(sheet == true)
        #expect(tab == .home)
    }
}
