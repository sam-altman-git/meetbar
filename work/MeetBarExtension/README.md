# MeetBar Bridge Chrome Extension

This extension lets MeetBar control Google Meet in the background.

## Install for local testing

1. Open `chrome://extensions`.
2. Turn on `Developer mode`.
3. Click `Load unpacked`.
4. Select this folder: `work/MeetBarExtension`.
5. Start MeetBar.
6. Join a Google Meet call.

The extension reports call and mute state to `http://127.0.0.1:17654`, which is served by the MeetBar app.
