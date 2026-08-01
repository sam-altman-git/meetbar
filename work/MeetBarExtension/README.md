# MeetBar Bridge Chrome Extension

This extension lets MeetBar read and control Google Meet in the background.

It reports:

- Active call state
- Microphone mute state
- Camera on/off state

It handles commands from the MeetBar app to:

- Toggle microphone
- Toggle camera
- End the call
- Bring the Meet tab/window to the front

## Install for local testing

1. Open `chrome://extensions`.
2. Turn on `Developer mode`.
3. Click `Load unpacked`.
4. Select this folder: `work/MeetBarExtension`.
5. Start MeetBar.
6. Join a Google Meet call.

The extension reports call, microphone, and camera state to `http://127.0.0.1:17654`, which is served by the MeetBar app. It polls the same local bridge for commands.
