# Shortcuts and guest scenarios

Open Settings → Automations once to refresh the installed app catalog. On iOS 16+, Shortcuts exposes **Launch container app** and **Run container automation**. The metadata is compiled into the main executable. Launching uses the normal LiveContainer URL route and preserves app authentication/JIT requirements; opening the URL does not report that the guest has finished launching or that a scenario has completed.

Scenarios are off by default. Create a named scenario, choose its app, and add/reorder waits, named button activations or button activations at a percentage position. Save it and enable scenarios. A copied launch link can also be used with Shortcuts' Open URLs action, including on iOS 15. Only a saved profile ID crosses the URL boundary; URLs do not accept inline scripts or arbitrary step payloads.

The guest runner uses UIControl target/action or accessibilityActivate within the visible guest window. This is not synthetic touch injection: custom renderers, most games, unsupported accessibility surfaces and system interfaces cannot be controlled. Matching multiple buttons stops execution rather than choosing arbitrarily. Coordinates include the app's safe areas and depend on its current layout/orientation.

The runner requires TweakLoader, a normal fullscreen guest and foreground execution; SideStore and LiveProcess are excluded. A floating stop button is displayed while running. Leaving the foreground stops execution; scenarios are never automatically resumed. Maximum 60 steps, 60 seconds per delay and 300 seconds total delay. A new run replaces the prior run. The most recent result appears in Settings.

Profiles and app options are stored locally in Documents/LCOSAutomations.json. Hidden/locked applications are excluded from the launch options catalog. The ordinary app authentication still applies to URL launches. Pending cold-launch requests are one-shot, scoped to the guest bundle folder and expire after 90 seconds. Disabling scenarios prevents execution, including from previously created shortcuts.

Tests cover bounded profile persistence/URL encoding and use a controlled iOS simulator app to exercise the actual Objective-C runner's UIKit button actions, foreground cancellation and disabled behavior. Physical-device Siri/Shortcuts discovery and compatibility with arbitrary guest apps require device verification.

Apple references: [App Intents](https://developer.apple.com/documentation/AppIntents), [UIControl target/action](https://developer.apple.com/documentation/uikit/uicontrol). The integration uses a foreground intent and the existing custom URL route; [OpenURLIntent](https://developer.apple.com/documentation/appintents/openurlintent) requires universal links and is not used for custom schemes.
