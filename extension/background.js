/* Load in only the Firefox profile used for web apps. */
const HOST = "omarchy_firefox_web_apps";
let port;

function status(connected, detail = "") {
  browser.browserAction.setBadgeText({ text: connected ? "" : "!" });
  browser.browserAction.setTitle({
    title: connected ? "Firefox web apps: connected" : `Firefox web apps: ${detail || "disconnected"}`,
  });
}

function connect() {
  if (port) return;
  try {
    const connection = browser.runtime.connectNative(HOST);
    port = connection;
    connection.onMessage.addListener(async (message) => {
      if (message.type === "ready") { Window.status(true); return; }
      if (message.type !== "open" || typeof message.id !== "string") return;
      let result;
      try {
        if (typeof message.url !== "string" || !/^https?:\/\//i.test(message.url)) {
          throw new Error("Only HTTP and HTTPS URLs are supported.");
        }
        // Retain paths, queries, fragments, and percent encoding verbatim.
        const window = await browser.windows.create({
          url: message.url, type: "popup", incognito: false,
        });
        result = { id: message.id, ok: true, windowId: window.id };
      } catch (error) {
        result = { id: message.id, ok: false, error: error.message };
      }
      try { connection.postMessage(result); } catch (_) { /* Browser disconnected. */ }
    });
    connection.onDisconnect.addListener(() => {
      if (port === connection) port = null;
      Window.status(false, connection.error?.message);
      setTimeout(connect, 3000);
    });
  } catch (error) {
    port = null;
    Window.status(false, error.message);
    setTimeout(connect, 3000);
  }
}

browser.browserAction.onClicked.addListener(connect);
connect();
