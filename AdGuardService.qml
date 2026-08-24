import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool ok: false
  property bool installed: false
  property bool running: false
  property bool httpsFiltering: false
  property int blockedToday: 0
  property var filters: []
  property bool exitNodeActive: false
  property string lastError: ""
  property string actionStatus: ""
  property string updateSummary: ""
  property int lastUpdateTs: 0
  // Which action is in flight, so the Update control can show its own progress rather
  // than every control going busy at once.
  property string actionKind: ""
  readonly property bool updating: actionKind === "update" && actionProcess.running
  // Nothing is known before the first poll answers, so the widget must not self-hide on the
  // starting value of `installed` and flicker out of the bar on every shell start.
  property bool polled: false
  readonly property bool busy: statusProcess.running || actionProcess.running

  // -1 follows reality; 0 and 1 hold a click's intent until the next poll agrees with it.
  property int _desiredRunning: -1
  readonly property bool effectiveRunning: _desiredRunning === -1 ? running : _desiredRunning === 1

  readonly property string helperPath: Qt.resolvedUrl("bin/omarchy-adguard").toString().replace("file://", "")

  // Re-clamped on read so a hand-edited shell.json cannot poison the timer.
  function intSetting(name, fallback, minValue, maxValue) {
    var raw = settings ? settings[name] : undefined
    var n = parseInt(raw, 10)
    if (!isFinite(n)) n = fallback
    if (n < minValue) n = minValue
    if (n > maxValue) n = maxValue
    return n
  }

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  // 0 turns the automatic refresh off; filter lists publish a few times a day, so six
  // hours keeps them current without making the box chatty.
  readonly property int filterUpdateHours: intSetting("filterUpdateHours", 6, 0, 168)

  readonly property int millisecondsPerSecond: 1000
  readonly property int actionStatusDurationMs: 2200
  readonly property int startupRampIntervalMs: 2000
  readonly property int startupRampMaxTicks: 15
  readonly property int settleIntervalMs: 1500
  readonly property int settleTicks: 3

  property int _rampTicks: 0
  property int _settleRemaining: 0
  // A refresh that fails leaves the timestamp where it was, so without this the next poll
  // would try again immediately and keep trying every thirty seconds.
  readonly property int autoRetryMs: 1800000
  property double _lastAutoAttemptMs: 0

  function apply(raw) {
    var s = Model.parseStatus(raw)
    root.ok = s.ok
    root.installed = s.installed
    root.running = s.running
    root.httpsFiltering = s.httpsFiltering
    root.blockedToday = s.blockedToday
    root.filters = s.filters
    root.exitNodeActive = s.exitNodeActive
    root.lastError = s.error
    if (s.updateSummary !== "") root.updateSummary = s.updateSummary
    root.lastUpdateTs = s.lastUpdateTs
    root.polled = true
    // Reality has spoken, so stop overriding it.
    root._desiredRunning = -1
  }

  function refresh() {
    if (statusProcess.running || actionProcess.running) return
    statusProcess.running = true
  }

  function run(args, note, kind) {
    if (statusProcess.running || actionProcess.running) return
    root.actionStatus = note
    root.actionKind = kind || ""
    root.updateSummary = ""
    actionProcess.command = [root.helperPath].concat(args)
    actionProcess.running = true
  }

  function toggleProtection() {
    var turningOn = !root.effectiveRunning
    root._desiredRunning = turningOn ? 1 : 0
    run(["protection", turningOn ? "on" : "off"], turningOn ? "Starting" : "Stopping", "protection")
  }

  function updateFilters() {
    run(["update"], "", "update")
  }

  // Driven off the filters' own timestamps rather than a stored clock, so a shell restart
  // neither loses the schedule nor triggers a fresh download.
  function maybeAutoUpdate() {
    if (root.filterUpdateHours <= 0) return
    if (root.busy || !root.installed || root.lastUpdateTs <= 0) return
    var nowMs = Date.now()
    if (nowMs - root._lastAutoAttemptMs < root.autoRetryMs) return
    var ageSec = (nowMs / 1000) - root.lastUpdateTs
    if (ageSec < root.filterUpdateHours * 3600) return
    root._lastAutoAttemptMs = nowMs
    root.updateFilters()
  }

  Process {
    id: statusProcess
    command: [root.helperPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.apply(text)
        root.maybeAutoUpdate()
      }
    }
  }

  Process {
    id: actionProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.apply(text)
        root.actionKind = ""
        if (root.lastError !== "") root.actionStatus = ""
        actionStatusTimer.restart()
        // A start or stop settles over a few seconds, so re-read until it stops moving.
        root._settleRemaining = root.settleTicks
        settleTimer.restart()
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * root.millisecondsPerSecond
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // The shell can start before the daemon does, so poll quickly until it appears and
  // then give up rather than keeping a fast timer alive for the whole session.
  Timer {
    id: startupRamp
    interval: root.startupRampIntervalMs
    repeat: true
    running: true
    onTriggered: {
      root._rampTicks++
      if (root.running || root._rampTicks >= root.startupRampMaxTicks) {
        startupRamp.running = false
        return
      }
      root.refresh()
    }
  }

  Timer {
    id: settleTimer
    interval: root.settleIntervalMs
    repeat: true
    onTriggered: {
      root._settleRemaining--
      if (root._settleRemaining <= 0) settleTimer.running = false
      root.refresh()
    }
  }

  Timer {
    id: actionStatusTimer
    interval: root.actionStatusDurationMs
    onTriggered: {
      root.actionStatus = ""
      root.updateSummary = ""
    }
  }
}
