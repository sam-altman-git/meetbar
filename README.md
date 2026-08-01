# MeetBar

MeetBar is a macOS menu bar app plus Chrome extension for controlling Google Meet.

The Chrome extension reads Google Meet state from the page and performs background actions. The macOS app shows the current mute state in the menu bar and sends commands through a local bridge on `127.0.0.1:17654`.

## Features

- Left click the menu bar icon to mute or unmute Google Meet.
- Right click the icon to open the menu.
- Menu shows current microphone and camera state.
- Toggle camera from the menu.
- End the active Google Meet call from the menu.
- Bring the active Google Meet tab/window to the front from the menu.
- Settings panel for expanded controls trigger, layout, and visible actions.
- Background control through the Chrome extension.

## Expanded Controls

MeetBar can show a compact expanded controls surface from the menu bar icon.

- Trigger: `NONE`, `HOVER`, or `CLICK`
- Type: `POPOVER` or `STRIP`
- Hover open and close delays in milliseconds when trigger is `HOVER`
- Visible options: End Call, Camera Toggle, Mic Toggle, Bring to Front

When the trigger is `NONE`, the app keeps the simple behavior: left click mutes/unmutes and right click opens the menu. When the trigger is `HOVER` or `CLICK`, the selected expanded controls appear according to the configured type.

## Project Layout

- `work/MeetBar`: Swift/AppKit menu bar app.
- `work/MeetBarExtension`: Chrome extension.

## Build App

```sh
cd work/MeetBar
./build_app.sh
open .build/MeetBar.app
```

## Install Extension

1. Open `chrome://extensions`.
2. Enable `Developer mode`.
3. Click `Load unpacked`.
4. Select `work/MeetBarExtension`.
5. Launch MeetBar and join a Google Meet call.
