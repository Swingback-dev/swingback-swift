import Foundation

// The title of the widget's sheet (ADR 0034, decision 14): the portal's word for the widget by default, the app's
// own words, or none (the close button stays). The other SDKs take the same three.

/// The title of the widget's sheet: the portal's word for the widget, your own words, or none.
public enum SwingbackTitle: Hashable, Sendable {
    /// The portal's own word for the widget, in the reader's language (the default).
    case portal
    /// Your own words.
    case text(String)
    /// No title: the close button stays.
    case hidden

    /// The words the sheet shows, the portal's labels given; nil for none.
    func shown(_ labels: WidgetSettings.Labels) -> String? {
        switch self {
        case .portal: labels.open
        case .text(let text): text
        case .hidden: nil
        }
    }
}
