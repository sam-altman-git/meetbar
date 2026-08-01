const BRIDGE = "http://127.0.0.1:17654";

let lastCommandId = 0;

async function postState(state) {
  try {
    await fetch(`${BRIDGE}/state`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(state),
    });
  } catch (_) {
    // MeetBar is probably not running. The next heartbeat will try again.
  }
}

async function sendCommandToMeetTabs(command) {
  const tabs = await chrome.tabs.query({ url: "https://meet.google.com/*" });
  for (const tab of tabs) {
    if (!tab.id) continue;
    try {
      await chrome.tabs.sendMessage(tab.id, command);
    } catch (_) {
      // The content script may not be ready on prejoin or special pages.
    }
  }
}

async function pollCommand() {
  try {
    const response = await fetch(`${BRIDGE}/command?last=${lastCommandId}`, { cache: "no-store" });
    const command = await response.json();
    if (!command || !command.action || command.id === lastCommandId) return;
    lastCommandId = command.id;
    await sendCommandToMeetTabs({ type: "meetbar-command", action: command.action });
  } catch (_) {
    // MeetBar is probably not running. Keep polling quietly.
  }
}

chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === "meetbar-state") {
    postState(message.state);
  }
});

chrome.alarms?.create?.("meetbar-poll", { periodInMinutes: 1 / 60 });
chrome.alarms?.onAlarm?.addListener((alarm) => {
  if (alarm.name === "meetbar-poll") pollCommand();
});

setInterval(pollCommand, 1000);
pollCommand();
