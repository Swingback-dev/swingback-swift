import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

// The widget in SwiftUI: `SwingbackWidget` in a view of the app, `.swingbackFeedback(isPresented:)` in a
// sheet. On iOS both are the UIKit controllers (the sheet keeps the system's close button); on macOS, a view
// holding the web view, and a sheet with a close button in the portal's word for it.

/// The widget in a view of your app, filling it: give it a size, or a place that gives it one.
public struct SwingbackWidget: View {
    private let page: SwingbackPage

    /// - Parameter page: The page of the widget to show (the feedback by default).
    public init(page: SwingbackPage = .feedback) {
        self.page = page
    }

    public var body: some View {
        WidgetRepresentable(page: page, onSettings: nil)
    }
}

extension View {
    /// Shows the widget in a sheet while `isPresented` is true, on one of its pages.
    ///
    /// - Parameters:
    ///   - title: The sheet's title: the portal's word for the widget by default, your own words, or none.
    ///   - showsBar: Whether the sheet has its bar, the title and the close button: without it, a swipe down closes
    ///     the sheet. On macOS the bar stays, since a sheet there closes by its button.
    public func swingbackFeedback(
        isPresented: Binding<Bool>,
        page: SwingbackPage = .feedback,
        title: SwingbackTitle = .portal,
        showsBar: Bool = true
    ) -> some View {
        modifier(SwingbackSheetModifier(isPresented: isPresented, page: page, title: title, showsBar: showsBar))
    }
}

private struct SwingbackSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let page: SwingbackPage
    let title: SwingbackTitle
    let showsBar: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: { Widgets.shared.emit(.close) }) {
                SwingbackSheet(page: page, title: title, showsBar: showsBar, close: { isPresented = false })
            }
            // Not the sheet's appearing, which comes again when what covered it (Safari's view) goes.
            .onChange(of: isPresented) { presented in
                if presented { Widgets.shared.emit(.open) }
            }
    }
}

#if canImport(UIKit)
    private struct SwingbackSheet: UIViewControllerRepresentable {
        let page: SwingbackPage
        let title: SwingbackTitle
        let showsBar: Bool
        let close: @MainActor () -> Void

        func makeUIViewController(context: Context) -> SwingbackSheetController {
            SwingbackSheetController(page: page, title: title, showsBar: showsBar, onClose: close)
        }

        func updateUIViewController(_ controller: SwingbackSheetController, context: Context) {
            controller.onClose = close
            controller.show(page)
        }

        static func dismantleUIViewController(_ controller: SwingbackSheetController, coordinator: ()) {
            (controller.viewControllers.first as? SwingbackViewController)?.close()
        }
    }

    private struct WidgetRepresentable: UIViewControllerRepresentable {
        let page: SwingbackPage
        let onSettings: (@MainActor (WidgetSettings) -> Void)?

        func makeUIViewController(context: Context) -> SwingbackViewController {
            let controller = SwingbackViewController(page: page)
            controller.onSettings = onSettings
            return controller
        }

        func updateUIViewController(_ controller: SwingbackViewController, context: Context) {
            controller.show(page)
        }

        static func dismantleUIViewController(_ controller: SwingbackViewController, coordinator: ()) {
            controller.close()
        }
    }
#elseif canImport(AppKit)
    private struct SwingbackSheet: View {
        let page: SwingbackPage
        let title: SwingbackTitle
        /// macOS keeps the bar: a sheet there closes by its button.
        let showsBar: Bool
        let close: @MainActor () -> Void
        @State private var settings = WidgetSettings.defaults(origin: "")

        var body: some View {
            NavigationStack {
                WidgetRepresentable(page: page, onSettings: { settings = $0 })
                    .navigationTitle(title.shown(settings.labels) ?? "")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(settings.labels.close, action: close)
                        }
                    }
            }
            .frame(minWidth: 420, idealWidth: 480, minHeight: 540, idealHeight: 720)
            .preferredColorScheme(settings.theme == .light ? .light : settings.theme == .dark ? .dark : nil)
        }
    }

    private struct WidgetRepresentable: NSViewRepresentable {
        let page: SwingbackPage
        let onSettings: (@MainActor (WidgetSettings) -> Void)?

        func makeNSView(context: Context) -> WidgetContainerView {
            WidgetContainerView(page: page, onSettings: onSettings)
        }

        func updateNSView(_ view: WidgetContainerView, context: Context) {
            view.show(page)
        }

        static func dismantleNSView(_ view: WidgetContainerView, coordinator: ()) {
            view.close()
        }
    }

    /// The widget in a view, filling it, with a spinner until its first page is there.
    @MainActor
    final class WidgetContainerView: NSView {
        private var page: SwingbackPage
        private var widget: WidgetWebView?
        private let spinner = NSProgressIndicator()

        init(page: SwingbackPage, onSettings: (@MainActor (WidgetSettings) -> Void)?) {
            self.page = page
            super.init(frame: .zero)
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.translatesAutoresizingMaskIntoConstraints = false
            addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            spinner.startAnimation(nil)
            Task { await start(onSettings: onSettings) }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not available")
        }

        func show(_ page: SwingbackPage) {
            guard page != self.page else { return }
            self.page = page
            widget?.show(page)
        }

        func close() {
            widget?.close()
        }

        private func start(onSettings: (@MainActor (WidgetSettings) -> Void)?) async {
            guard let configuration = Widgets.shared.configuration else {
                assertionFailure("Swingback: call Swingback.configure(portal:token:) before showing the widget")
                return
            }
            let settings = await SettingsCache.shared.settings(of: configuration.origin)
            onSettings?(settings)
            spinner.setAccessibilityLabel(settings.labels.loading)
            let widget = Widgets.shared.make(settings: settings)
            self.widget = widget
            widget.onLoaded = { [weak self] in
                self?.spinner.stopAnimation(nil)
                self?.spinner.isHidden = true
            }
            let webView = widget.webView
            webView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(webView, positioned: .below, relativeTo: spinner)
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: topAnchor),
                webView.bottomAnchor.constraint(equalTo: bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
            widget.load(page)
        }
    }
#endif
