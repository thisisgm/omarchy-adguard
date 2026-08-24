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

  readonly property int millisecondsPerSecond: 1000
  readonly property int actionStatusDurationMs: 2200
  readonly property int startupRampIntervalMs: 2000
  readonly property int startupRampMaxTicks: 15
  readonly property int settleIntervalMs: 1500
  readonly property int settleTicks: 3

  property int _rampTicks: 0
  property int _settleRemaining: 0

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
    root.polled = true
    // Reality has spoken, so stop overriding it.
    root._desiredRunning = -1
  }

  function refresh() {
    if (statusProcess.running || actionProcess.running) return
    statusProcess.running = true
  }

  function run(args, note) {
    if (statusProcess.running || actionProcess.running) return
    root.actionStatus = note
    actionProcess.command = [root.helperPath].concat(args)
    actionProcess.running = true
  }

  function toggleProtection() {
    var turningOn = !root.effectiveRunning
    root._desiredRunning = turningOn ? 1 : 0
    run(["protection", turningOn ? "on" : "off"], turningOn ? "Starting" : "Stopping")
  }

  function toggleHttpsFiltering() {
    run(["https", root.httpsFiltering ? "off" : "on"],
        root.httpsFiltering ? "Turning HTTPS filtering off" : "Turning HTTPS filtering on")
  }

  function toggleFilter(id, enabled) {
    run(["filter", enabled ? "disable" : "enable", String(id)], "Updating filters")
  }

  function updateFilters() {
    run(["update"], "Checking for updates")
  }

  Process {
    id: statusProcess
    command: [root.helperPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
  }

  Process {
    id: actionProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.apply(text)
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
    onTriggered: root.actionStatus = ""
  }
}
