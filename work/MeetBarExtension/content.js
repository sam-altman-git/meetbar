function meetButton(regex) {
  const candidates = document.querySelectorAll('button[aria-label], div[role="button"][aria-label]');
  return [...candidates].find((element) => regex.test(element.getAttribute("aria-label") || ""));
}

function readState() {
  const muteButton = meetButton(/Turn on microphone|Turn off microphone|Mute|Unmute|microphone/i);
  const leaveButton = meetButton(/^(Leave call|Leave meeting|Leave)$|Leave call/i);
  const label = muteButton?.getAttribute("aria-label") || "";

  let muted = null;
  if (/Turn on microphone|Unmute|microphone is off/i.test(label)) muted = true;
  if (/Turn off microphone|Mute|microphone is on/i.test(label)) muted = false;

  return {
    inCall: Boolean(leaveButton),
    muted,
    title: document.title || "Google Meet",
    url: location.href,
    at: Date.now(),
  };
}

function sendState() {
  chrome.runtime.sendMessage({ type: "meetbar-state", state: readState() });
}

function clickButton(regex) {
  const button = meetButton(regex);
  if (!button) return false;
  button.click();
  setTimeout(sendState, 250);
  setTimeout(sendState, 900);
  return true;
}

chrome.runtime.onMessage.addListener((message) => {
  if (message?.type !== "meetbar-command") return;

  if (message.action === "toggleMute") {
    clickButton(/Turn on microphone|Turn off microphone|Mute|Unmute|microphone/i);
  }

  if (message.action === "leave") {
    clickButton(/^(Leave call|Leave meeting|Leave)$|Leave call/i);
  }
});

setInterval(sendState, 1000);
sendState();
