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
- Background control through the Chrome extension.

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
