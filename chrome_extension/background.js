const NATIVE_HOST_NAME = "com.refocus.native_host";

let port = null;

function ensurePort() {
  if (port) {
    return port;
  }
  port = chrome.runtime.connectNative(NATIVE_HOST_NAME);
  port.onDisconnect.addListener(() => {
    port = null;
  });
  return port;
}

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

  ensurePort().postMessage(payload);
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
