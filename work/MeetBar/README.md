# MeetBar

MeetBar is a tiny macOS menu bar app for controlling an active Google Meet call through the MeetBar Bridge Chrome extension.

The menu bar icon reflects the current microphone state:

- Green background with white mic when unmuted
- Red background with white muted mic when muted
- Gray background when no active call is reported

Left click the icon to mute or unmute. Right click the icon to open status/settings utilities. Meeting controls other than the default left-click mic toggle live in the configurable expanded controls.

The right-click menu provides:

- Settings
- Refresh
- Bridge status
- Quit

## Settings

Open settings from the right-click menu.

Settings include:

- Expand options trigger: `NONE`, `HOVER`, or `CLICK`
- Expand options type: `POPOVER` or `STRIP`
- Hover open delay and hover close delay in milliseconds when trigger is `HOVER`, editable with numeric fields and steppers
- Visible expand options:
  - End Call
  - Camera Toggle
  - Mic Toggle
  - Bring to Front

When the trigger is `NONE`, the expanded-options settings are disabled and MeetBar keeps the simple left-click mute/unmute behavior. When the trigger is `HOVER` or `CLICK`, MeetBar shows the selected controls from the menu bar icon using the configured layout.

Expanded controls stay open while the pointer is over the icon or controls, rebuild when Meet state changes, and close when clicking outside.

`POPOVER` uses a translucent vertical panel with labeled row tiles. `STRIP` uses a translucent horizontal panel with large icon-only tiles.

## Supported browser in this prototype

- Google Chrome

## Build

```sh
./build_app.sh
open .build/MeetBar.app
```

## Required permissions

MeetBar listens on `127.0.0.1:17654` for the local Chrome extension bridge. Install the Chrome extension before testing meeting controls:

1. Open the browser.
2. Go to `chrome://extensions`.
3. Turn on `Developer mode`.
4. Click `Load unpacked`.
5. Select `work/MeetBarExtension`.
6. Join a Google Meet call.
7. Open MeetBar from the menu bar.

## How it works

MuteDeck uses a browser extension for robust web meeting support. MeetBar uses the same broad shape:

1. A Chrome extension content script runs inside `https://meet.google.com/*`.
2. The extension reads microphone/camera state from Meet controls.
3. The extension posts state to the local MeetBar bridge.
4. MeetBar queues commands through the local bridge.
5. The extension clicks the Meet controls in the background for microphone, camera, and end-call actions.
6. The extension uses Chrome tab/window APIs to bring Meet to the front.

This avoids Chrome AppleScript JavaScript permissions and keeps background control reliable for Google Meet. A production version should package and sign the app/extension together and use a hardened local bridge protocol.
