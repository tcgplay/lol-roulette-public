(function (global) {
  var KEY = "lolRoulette.enabledOverrides";

  function isLocalServer() {
    var h = location.hostname;
    return h === "127.0.0.1" || h === "localhost";
  }

  function readOverrides() {
    try {
      var raw = global.localStorage.getItem(KEY);
      if (!raw) { return {}; }
      var obj = JSON.parse(raw);
      return obj && typeof obj === "object" ? obj : {};
    } catch (e) {
      return {};
    }
  }

  function writeOverrides(map) {
    global.localStorage.setItem(KEY, JSON.stringify(map));
  }

  function applyToRows(rows) {
    var over = readOverrides();
    var i;
    for (i = 0; i < rows.length; i++) {
      var fn = String(rows[i].filename || "").trim();
      if (Object.prototype.hasOwnProperty.call(over, fn)) {
        rows[i].enabled = over[fn] ? "1" : "0";
      }
    }
    return rows;
  }

  function saveHint() {
    if (isLocalServer()) {
      return "ローカルでは parties/config.csv に保存します。";
    }
    return "公開ページでは、このブラウザにだけ保存します（config.csv は変わりません）。";
  }

  function saveEnabled(filename, wantOn) {
    if (isLocalServer()) {
      return fetch("/api/party-enabled", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ filename: filename, enabled: wantOn ? 1 : 0 })
      }).then(function (res) {
        if (!res.ok) {
          return res.text().then(function (t) {
            throw new Error(t || ("HTTP " + res.status));
          });
        }
        return { persisted: "csv" };
      });
    }
    var map = readOverrides();
    map[filename] = wantOn ? 1 : 0;
    writeOverrides(map);
    return Promise.resolve({ persisted: "local" });
  }

  global.LolEnabledStore = {
    isLocalServer: isLocalServer,
    applyToRows: applyToRows,
    saveEnabled: saveEnabled,
    saveHint: saveHint
  };
})(window);
