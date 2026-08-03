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

async function ackCommand(id) {
  try {
    await fetch(`${BRIDGE}/ack?id=${encodeURIComponent(id)}`, { cache: "no-store" });
  } catch (_) {
    // MeetBar may have stopped after the command was handled.
  }
}

async function sendCommandToMeetTabs(command) {
  const tabs = await chrome.tabs.query({ url: "https://meet.google.com/*" });
  if (command.action === "bringToFront") {
    const tab = tabs[0];
    if (!tab?.id || !tab.windowId) return false;
    await chrome.tabs.update(tab.id, { active: true });
    await chrome.windows.update(tab.windowId, { focused: true });
    return true;
  }

  let handled = false;
  for (const tab of tabs) {
    if (!tab.id) continue;
    try {
      const response = await chrome.tabs.sendMessage(tab.id, command);
      handled = handled || response?.handled === true;
    } catch (_) {
      // The content script may not be ready on prejoin or special pages.
    }
  }
  return handled;
}

async function pollCommand() {
  try {
    const response = await fetch(`${BRIDGE}/command?last=${lastCommandId}`, { cache: "no-store" });
    const command = await response.json();
    if (!command || !command.action || command.id === lastCommandId) return;
    const handled = await sendCommandToMeetTabs({ type: "meetbar-command", action: command.action });
    if (handled) {
      lastCommandId = command.id;
      await ackCommand(command.id);
    }
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

setInterval(pollCommand, 250);
pollCommand();
