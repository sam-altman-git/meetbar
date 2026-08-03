const LOCAL_MIC_LABEL = /^(Turn on microphone|Turn off microphone|Microphone on|Microphone off|Mute|Unmute)\b/i;
const LOCAL_CAMERA_LABEL = /^(Turn on camera|Turn off camera|Camera on|Camera off|Camera)\b/i;
const LEAVE_LABEL = /^(Leave call|Leave meeting|Leave)\b/i;
let stateTimer = null;
let observer = null;
let stateSendTimeout = null;

function visibleControl(element) {
  const rect = element.getBoundingClientRect();
  return rect.width > 0 && rect.height > 0;
}

function toolbarScore(element) {
  const rect = element.getBoundingClientRect();
  const centerX = rect.left + rect.width / 2;
  const centerY = rect.top + rect.height / 2;
  const bottomDistance = Math.abs(window.innerHeight - centerY);
  const centerDistance = Math.abs(window.innerWidth / 2 - centerX);
  return bottomDistance * 2 + centerDistance;
}

function compactToolbarContainer(element) {
  const rect = element.getBoundingClientRect();
  return rect.width > 0 && rect.height > 0 && rect.width < window.innerWidth * 0.95 && rect.height < 180;
}

function sharedToolbarButton(regex) {
  const leaveButton = meetButton(LEAVE_LABEL);
  if (!leaveButton) return null;

  const candidates = matchingButtons(regex);
  const ranked = candidates
    .map((button) => {
      let ancestor = button.parentElement;
      let depth = 0;

      while (ancestor && ancestor !== document.body && depth < 12) {
        if (ancestor.contains(leaveButton) && compactToolbarContainer(ancestor)) {
          const rect = ancestor.getBoundingClientRect();
          return {
            button,
            score: rect.width * rect.height + depth * 1000 + toolbarScore(button),
          };
        }

        ancestor = ancestor.parentElement;
        depth += 1;
      }

      return null;
    })
    .filter(Boolean)
    .sort((a, b) => a.score - b.score);

  return ranked[0]?.button || null;
}

function matchingButtons(regex) {
  const candidates = document.querySelectorAll('button[aria-label], div[role="button"][aria-label]');
  return [...candidates].filter((element) => {
    const label = element.getAttribute("aria-label") || "";
    return regex.test(label) && visibleControl(element);
  });
}

function meetButton(regex) {
  return matchingButtons(regex)[0] || null;
}

function readState() {
  const muteButton = sharedToolbarButton(LOCAL_MIC_LABEL);
  const cameraButton = sharedToolbarButton(LOCAL_CAMERA_LABEL);
  const leaveButton = meetButton(LEAVE_LABEL);
  const micLabel = muteButton?.getAttribute("aria-label") || "";
  const cameraLabel = cameraButton?.getAttribute("aria-label") || "";

  let muted = null;
  if (/^(Turn on microphone|Microphone off|Unmute)\b/i.test(micLabel)) muted = true;
  if (/^(Turn off microphone|Microphone on|Mute)\b/i.test(micLabel)) muted = false;

  let cameraOff = null;
  if (/^(Turn on camera|Camera off)\b/i.test(cameraLabel)) cameraOff = true;
  if (/^(Turn off camera|Camera on)\b/i.test(cameraLabel)) cameraOff = false;

  return {
    inCall: Boolean(leaveButton),
    muted,
    cameraOff,
    title: document.title || "Google Meet",
    url: location.href,
    at: Date.now(),
  };
}

function sendState() {
  try {
    if (typeof chrome === "undefined" || !chrome.runtime?.id) {
      stopStatePolling();
      return false;
    }

    chrome.runtime.sendMessage({ type: "meetbar-state", state: readState() }, () => {
      try {
        chrome.runtime.lastError;
      } catch {
        stopStatePolling();
      }
    });
    return true;
  } catch {
    stopStatePolling();
    return false;
  }
}

function stopStatePolling() {
  if (!stateTimer) return;
  clearInterval(stateTimer);
  stateTimer = null;
  observer?.disconnect();
  observer = null;
  if (stateSendTimeout) {
    clearTimeout(stateSendTimeout);
    stateSendTimeout = null;
  }
}

function scheduleStateSend(delay = 75) {
  if (stateSendTimeout) clearTimeout(stateSendTimeout);
  stateSendTimeout = setTimeout(() => {
    stateSendTimeout = null;
    sendState();
  }, delay);
}

function startStateObserver() {
  if (observer || !document.body) return;

  observer = new MutationObserver((mutations) => {
    const relevant = mutations.some((mutation) => {
      if (mutation.type === "attributes") {
        return ["aria-label", "data-is-muted", "data-muted", "disabled"].includes(mutation.attributeName || "");
      }
      return mutation.addedNodes.length > 0 || mutation.removedNodes.length > 0;
    });

    if (relevant) scheduleStateSend();
  });

  observer.observe(document.body, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ["aria-label", "data-is-muted", "data-muted", "disabled"],
  });
}

function clickButton(regex, options = {}) {
  const button = options.preferToolbar ? sharedToolbarButton(regex) : meetButton(regex);
  if (!button) return false;
  button.click();
  setTimeout(sendState, 75);
  setTimeout(sendState, 200);
  setTimeout(sendState, 500);
  return true;
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "meetbar-command") return false;

  let handled = false;

  if (message.action === "toggleMute") {
    handled = clickButton(LOCAL_MIC_LABEL, { preferToolbar: true });
  }

  if (message.action === "leave") {
    handled = clickButton(LEAVE_LABEL);
  }

  if (message.action === "toggleCamera") {
    handled = clickButton(LOCAL_CAMERA_LABEL, { preferToolbar: true });
  }

  sendResponse({ handled });
  return true;
});

stateTimer = setInterval(sendState, 1000);
startStateObserver();
sendState();
