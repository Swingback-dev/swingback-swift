# Swingback for iOS and macOS

Your Swingback portal's feedback widget in your app: in a sheet, or in a screen of your own, with your user already
signed in. Every feature of the widget (posts, votes, comments, the roadmap, the changelog, translations) comes with it,
the day it ships.

```swift
import Swingback

// Once, when your app starts: your portal, and your server's identity token for the signed-in user.
Swingback.configure(portal: URL(string: "https://acme.example.com")!) {
    try await AcmeAPI.shared.feedbackToken()
}

// In SwiftUI
Button("Send feedback") { feedback = true }
    .swingbackFeedback(isPresented: $feedback)

// From UIKit
Swingback.present(from: self, page: .changelog)
```

iOS 16 and macOS 13 or later, Swift 6. The guide is [swingback.dev/docs/ios](https://swingback.dev/docs/ios).

## Install

In Xcode, **File → Add Package Dependencies…**, with this repository's address, and add the `Swingback` library to your
app's target. In a `Package.swift`, depend on the same address from version 0.1.0.

The widget's settings, look and words are your portal's; your server signs the identity token with your identity secret,
which never goes in your app ([Signing in your users](https://swingback.dev/docs/identify)).

## Licence

MIT.
