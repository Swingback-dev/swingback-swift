#if canImport(UIKit)
    import UIKit

    // The widget on iOS: a view controller holding its web view (an app's own container may hold it too), and
    // the sheet around it (a navigation controller with the system's close button, its title the portal's word for
    // the widget, the app's own or none, or no bar at all), which `Swingback.present(from:)` shows and SwiftUI's
    // `.swingbackFeedback(isPresented:)` wraps. The portal's settings come first: its canonical address, its look
    // and its words; a spinner shows until the widget's first page is there.

    /// The widget in a view controller, filling its view: for a container of your own, a navigation stack's
    /// screen or a sheet of your making.
    @MainActor
    public final class SwingbackViewController: UIViewController {
        private(set) var page: SwingbackPage
        private var widget: WidgetWebView?
        private let spinner = UIActivityIndicatorView(style: .medium)
        /// The portal's settings, once read: the sheet takes its title and its look from them.
        var onSettings: (@MainActor (WidgetSettings) -> Void)?

        /// - Parameter page: The page of the widget to show (the feedback by default).
        public init(page: SwingbackPage = .feedback) {
            self.page = page
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) is not available")
        }

        override public func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            spinner.translatesAutoresizingMaskIntoConstraints = false
            spinner.hidesWhenStopped = true
            view.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            spinner.startAnimating()
            Task { await start() }
        }

        /// Shows another page of the widget, in its document when it can.
        public func show(_ page: SwingbackPage) {
            guard page != self.page else { return }
            self.page = page
            widget?.show(page)
        }

        /// The widget leaves for good.
        func close() {
            widget?.close()
        }

        private func start() async {
            guard let configuration = Widgets.shared.configuration else {
                assertionFailure("Swingback: call Swingback.configure(portal:token:) before showing the widget")
                return
            }
            let settings = await SettingsCache.shared.settings(of: configuration.origin)
            onSettings?(settings)
            spinner.accessibilityLabel = settings.labels.loading
            let widget = Widgets.shared.make(settings: settings)
            self.widget = widget
            widget.onLoaded = { [weak self] in self?.spinner.stopAnimating() }
            let webView = widget.webView
            webView.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(webView, belowSubview: spinner)
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: view.topAnchor),
                webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            widget.load(page)
        }
    }

    /// The widget's sheet: a navigation bar with its title (the portal's word for it by default) and the system's
    /// close button, or no bar where the app leaves it out (a swipe down closes the sheet).
    @MainActor
    final class SwingbackSheetController: UINavigationController, UIAdaptivePresentationControllerDelegate {
        private let content: SwingbackViewController
        private let heading: SwingbackTitle
        /// What closing does: SwiftUI's binding, or nil when the sheet dismisses itself (`present(from:)`).
        var onClose: (@MainActor () -> Void)?

        init(
            page: SwingbackPage,
            title: SwingbackTitle = .portal,
            showsBar: Bool = true,
            onClose: (@MainActor () -> Void)? = nil
        ) {
            content = SwingbackViewController(page: page)
            heading = title
            self.onClose = onClose
            super.init(rootViewController: content)
            modalPresentationStyle = .pageSheet
            setNavigationBarHidden(!showsBar, animated: false)
            content.navigationItem.title = title.shown(WidgetSettings.defaults(origin: "").labels)
            content.navigationItem.largeTitleDisplayMode = .never
            content.navigationItem.rightBarButtonItem = UIBarButtonItem(
                systemItem: .close,
                primaryAction: UIAction { [weak self] _ in self?.close() }
            )
            content.onSettings = { [weak self] settings in self?.apply(settings) }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not available")
        }

        func show(_ page: SwingbackPage) {
            content.show(page)
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            // Swiping the sheet away is a close too, when it presents itself.
            if onClose == nil { presentationController?.delegate = self }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if onClose == nil, isBeingPresented { Widgets.shared.emit(.open) }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            content.close()
            Widgets.shared.emit(.close)
        }

        private func close() {
            if let onClose {
                onClose()
                return
            }
            content.close()
            dismiss(animated: true) { Widgets.shared.emit(.close) }
        }

        /// The title (the portal's word for the widget by default), and its look when the workspace chose one.
        private func apply(_ settings: WidgetSettings) {
            content.navigationItem.title = heading.shown(settings.labels)
            switch settings.theme {
            case .light: overrideUserInterfaceStyle = .light
            case .dark: overrideUserInterfaceStyle = .dark
            case .system: overrideUserInterfaceStyle = .unspecified
            }
        }
    }
#endif
