# SwiftUI tunnel-flow mock

`DeveloperTunnelDemoView.swift` is a standalone SwiftUI view that demonstrates a developer-connection screen and its visual states. It deliberately does not connect to a phone or implement Apple's pairing/tunnel services.

## Use in an existing SwiftUI app

Add `DeveloperTunnelDemoView.swift` to the app target, then present it from a navigation destination or the app root:

```swift
WindowGroup {
    DeveloperTunnelDemoView()
}
```

The view requires SwiftUI and an iOS 16-or-newer deployment target because it uses `NavigationStack`. Build and preview it with Xcode on macOS. This Windows workspace has no Swift compiler or Xcode, so compilation could not be verified here.