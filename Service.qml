import QtQuick
import Quickshell
import Quickshell.Io

// Singleton rotator. One Timer, no polling: the shell sleeps until the next
// rotation is due, then runs bin/wallrotate-next once. Every per-monitor bar
// copy reads state from here instead of keeping its own clock.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  readonly property string pluginId: "contra.wallrotate"
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string pluginDir: {
    if (manifest && manifest.__sourceDir)
      return String(manifest.__sourceDir).replace(/\/$/, "")
    var u = Qt.resolvedUrl(".").toString()
    if (u.indexOf("file://") === 0) u = u.slice(7)
    return u.replace(/\/$/, "")
  }
  readonly property string nextBin: root.pluginDir + "/bin/wallrotate-next"
  readonly property string stateDir: {
    var stateHome = Quickshell.env("XDG_STATE_HOME")
    return ((stateHome && stateHome !== "") ? stateHome : root.home + "/.local/state") + "/contra-wallrotate"
  }

  // Settings live inline on this plugin's shell.json entry, wherever it is:
  // a bar layout slot or a top-level plugins[] entry.
  property var config: ({})
  readonly property real intervalMinutes: Math.max(1, Number(config.intervalMinutes || 30))
  readonly property bool shuffle: config.shuffle === true
  readonly property bool skipOnBattery: config.skipOnBattery === true

  property bool paused: false
  property double lastRotated: Date.now()
  readonly property double nextAt: lastRotated + intervalMinutes * 60000
  property string lastResult: ""

  function findEntry(cfg) {
    if (!cfg || typeof cfg !== "object") return null
    var lists = []
    if (Array.isArray(cfg.plugins)) lists.push(cfg.plugins)
    var layout = cfg.bar && cfg.bar.layout
    if (layout) ["left", "center", "right"].forEach(function(side) {
      if (Array.isArray(layout[side])) lists.push(layout[side])
    })
    for (var i = 0; i < lists.length; i++)
      for (var j = 0; j < lists[i].length; j++) {
        var entry = lists[i][j]
        if (entry && typeof entry === "object" && entry.id === root.pluginId) return entry
      }
    return null
  }

  function rotate(mode) {
    if (rotateProc.running) return
    var args = [root.nextBin]
    if (mode === "prev") args.push("--prev")
    else if (mode === "shuffle" || (mode !== "next" && root.shuffle)) args.push("--shuffle")
    if (mode === "auto") {
      args.push("--auto")
      if (root.skipOnBattery) args.push("--skip-on-battery")
    }
    rotateProc.command = args
    rotateProc.running = true
    root.lastRotated = Date.now()
    timer.restart()
  }

  function next() { rotate("manual") }
  function previous() { rotate("prev") }

  function setPaused(value) {
    root.paused = value === true
    if (root.paused) timer.stop()
    else {
      root.lastRotated = Date.now()
      timer.restart()
    }
    stateFile.setText(JSON.stringify({ paused: root.paused }))
  }

  function togglePause() { setPaused(!root.paused) }

  function minutesLeft() {
    return Math.max(0, Math.ceil((root.nextAt - Date.now()) / 60000))
  }

  Timer {
    id: timer
    interval: root.intervalMinutes * 60000
    repeat: true
    running: !root.paused
    onTriggered: root.rotate("auto")
  }

  // A new interval takes effect from now rather than from the last rotation.
  onIntervalMinutesChanged: {
    root.lastRotated = Date.now()
    if (!root.paused) timer.restart()
  }

  Process {
    id: rotateProc
    stdout: StdioCollector {
      onStreamFinished: root.lastResult = String(text || "").trim()
    }
  }

  FileView {
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        root.config = root.findEntry(JSON.parse(text())) || ({})
      } catch (e) {
        console.warn("contra.wallrotate: cannot parse shell.json:", e)
      }
    }
  }

  Process {
    id: mkStateDir
    command: ["mkdir", "-p", root.stateDir]
    running: true
  }

  FileView {
    id: stateFile
    path: root.stateDir + "/state.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        if (JSON.parse(text()).paused === true) {
          root.paused = true
          timer.stop()
        }
      } catch (e) {}
    }
  }

  IpcHandler {
    target: "contra.wallrotate"
    function next(): string { root.next(); return "ok" }
    function previous(): string { root.previous(); return "ok" }
    function shuffle(): string { root.rotate("shuffle"); return "ok" }
    function pause(): string { root.setPaused(true); return "paused" }
    function resume(): string { root.setPaused(false); return "running" }
    function togglePause(): string { root.togglePause(); return root.paused ? "paused" : "running" }
    function status(): string {
      return JSON.stringify({
        paused: root.paused,
        intervalMinutes: root.intervalMinutes,
        shuffle: root.shuffle,
        skipOnBattery: root.skipOnBattery,
        minutesLeft: root.paused ? null : root.minutesLeft(),
        lastResult: root.lastResult
      })
    }
  }
}
