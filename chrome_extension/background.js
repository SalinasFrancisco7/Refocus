const NATIVE_HOST_NAME = "com.refocus.native_host";

let port = null;
let heartbeatStarted = false;
let nativeHostHealthy = false;
let lastNativeError = "";

// Icon states: "active" (green), "error" (red), "idle" (gray)
function createIconImageData(state) {
  const size = 32;
  const canvas = new OffscreenCanvas(size, size);
  const ctx = canvas.getContext("2d");

  // Colors based on state
  const colors = {
    active: { fill: "#22c55e", stroke: "#16a34a" },   // Green
    error: { fill: "#ef4444", stroke: "#dc2626" },     // Red
    idle: { fill: "#9ca3af", stroke: "#6b7280" }       // Gray
  };
  const { fill, stroke } = colors[state] || colors.idle;

  // Draw circle with border
  ctx.beginPath();
  ctx.arc(size / 2, size / 2, size / 2 - 2, 0, Math.PI * 2);
  ctx.fillStyle = fill;
  ctx.fill();
  ctx.strokeStyle = stroke;
  ctx.lineWidth = 2;
  ctx.stroke();

  // Draw inner symbol
  ctx.fillStyle = "#ffffff";
  ctx.strokeStyle = "#ffffff";
  ctx.lineWidth = 2.5;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  if (state === "active") {
    // Checkmark
    ctx.beginPath();
    ctx.moveTo(9, 16);
    ctx.lineTo(14, 21);
    ctx.lineTo(23, 11);
    ctx.stroke();
  } else if (state === "error") {
    // X mark
    ctx.beginPath();
    ctx.moveTo(11, 11);
    ctx.lineTo(21, 21);
    ctx.moveTo(21, 11);
    ctx.lineTo(11, 21);
    ctx.stroke();
  } else {
    // Pause bars for idle
    ctx.fillRect(11, 10, 4, 12);
    ctx.fillRect(17, 10, 4, 12);
  }

  return ctx.getImageData(0, 0, size, size);
}

async function setIconState(state) {
  if (!chrome.action) return;
  try {
    const imageData = createIconImageData(state);
    await chrome.action.setIcon({ imageData: { 32: imageData } });
  } catch (e) {
    console.warn("Failed to set icon:", e);
  }
}

function handleNativeSuccess() {
  if (!nativeHostHealthy) {
    console.info("Refocus extension connected to native host.");
  }
  nativeHostHealthy = true;
  lastNativeError = "";
  if (chrome.action) {
    chrome.action.setBadgeText({ text: "" });
    chrome.action.setTitle({ title: "Refocus: Connected to macOS app" });
  }
  setIconState("active");
}

function handleNativeFailure(message) {
  if (lastNativeError !== message) {
    console.warn("Refocus native host unavailable:", message);
    lastNativeError = message;
  }
  nativeHostHealthy = false;
  if (chrome.action) {
    chrome.action.setBadgeBackgroundColor({ color: "#dc2626" });
    chrome.action.setBadgeText({ text: "!" });
    chrome.action.setTitle({
      title: `Refocus: Disconnected - ${message}`
    });
  }
  setIconState("error");
}

function ensurePort() {
  if (port) {
    return port;
  }
  try {
    port = chrome.runtime.connectNative(NATIVE_HOST_NAME);
  } catch (error) {
    handleNativeFailure(error.message);
    return null;
  }
  port.onDisconnect.addListener(() => {
    const message = chrome.runtime.lastError?.message || "Native host disconnected.";
    handleNativeFailure(message);
    port = null;
  });
  port.onMessage.addListener(() => {
    handleNativeSuccess();
  });
  handleNativeSuccess();
  return port;
}

function checkNativeHost() {
  return new Promise((resolve) => {
    chrome.runtime.sendNativeMessage(
      NATIVE_HOST_NAME,
      { type: "PING", timestamp: Math.floor(Date.now() / 1000) },
      (response) => {
        if (chrome.runtime.lastError) {
          handleNativeFailure(chrome.runtime.lastError.message);
          resolve(false);
          return;
        }
        // Check if native host returned an error (app not running)
        if (response && response.error) {
          handleNativeFailure(response.error);
          resolve(false);
          return;
        }
        handleNativeSuccess();
        resolve(true);
      }
    );
  });
}

function startHeartbeat() {
  if (heartbeatStarted) return;
  heartbeatStarted = true;
  setInterval(() => {
    checkNativeHost();
  }, 1000);
}

// Start heartbeat immediately when service worker loads
setIconState("idle");
checkNativeHost();
startHeartbeat();

chrome.runtime.onStartup.addListener(() => {
  checkNativeHost();
});

chrome.runtime.onInstalled.addListener(() => {
  checkNativeHost();
});

function sendTabEvent(tab) {
  if (!tab || !tab.url) {
    return;
  }

  const payload = {
    type: "TAB_EVENT",
    url: tab.url,
    title: tab.title || "",
    tabId: tab.id,
    windowId: tab.windowId,
    timestamp: Math.floor(Date.now() / 1000)
  };

  const nativePort = ensurePort();
  if (!nativePort) {
    return;
  }
  nativePort.postMessage(payload);
}

chrome.tabs.onActivated.addListener(async (activeInfo) => {
  try {
    const tab = await chrome.tabs.get(activeInfo.tabId);
    sendTabEvent(tab);
  } catch (error) {
    // Ignore when tab is missing.
  }
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === "complete" || changeInfo.url) {
    sendTabEvent(tab);
  }
});

chrome.windows.onFocusChanged.addListener(async (windowId) => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) {
    return;
  }

  try {
    const tabs = await chrome.tabs.query({ active: true, windowId });
    sendTabEvent(tabs[0]);
  } catch (error) {
    // Ignore when window is unavailable.
  }
});
