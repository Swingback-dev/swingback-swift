import Testing

@testable import Swingback

// The title of the widget's sheet (ADR 0034, decision 17): the portal's word for the widget, the app's own, or
// none.

@Suite struct TitleTests {
    @Test func titlesTheSheetInThePortalsWordsTheAppsOrNone() {
        let labels = WidgetSettings.Labels(open: "Suggestions", close: "Fermer", loading: "Chargement")
        #expect(SwingbackTitle.portal.shown(labels) == "Suggestions")
        #expect(SwingbackTitle.text("Ideas").shown(labels) == "Ideas")
        #expect(SwingbackTitle.hidden.shown(labels) == nil)
    }
}
