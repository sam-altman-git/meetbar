# MeetBar

MeetBar is a tiny macOS menu bar app for controlling an active Google Meet call.

It detects Google Meet tabs in Chromium-style browsers and enables the menu bar icon when Meet is open. The menu provides:

- Mute or unmute microphone
- End call
- Refresh

## Supported browsers in this prototype

- Google Chrome
- Microsoft Edge
- Brave Browser
- Arc
- Vivaldi

## Build

```sh
./build_app.sh
open .build/MeetBar.app
```

## Required permissions

The first time MeetBar talks to your browser, macOS will ask for Automation permission. Allow it.

Chromium browsers may also require:

1. Open the browser.
2. Join a Google Meet call.
3. Open MeetBar from the menu bar.
4. Allow Automation permission when macOS asks.
5. Allow Accessibility permission if macOS asks. You can also enable it manually in `System Settings > Privacy & Security > Accessibility`.

## How it works

MuteDeck uses a browser extension for robust web meeting support. This prototype avoids an extension by using Apple Events and keyboard shortcuts to:

1. Find a browser tab whose URL starts with `https://meet.google.com/`.
2. Bring that tab forward.
3. Send Google Meet's `Command-D` mute shortcut, or close the Meet tab to end the call.

That keeps the app small and avoids Chrome's `Allow JavaScript from Apple Events` setting, but a production version should add a browser extension for accurate mute state, better leave-call behavior, Meet UI changes, and multiple active calls.
