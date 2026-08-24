import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.thisisgm.adguard"
  ipcTarget: "adguard"
  manageIpc: false

  // Without these the bar allocates a zero-width slot and the widget never draws or logs.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property int cursorIndex: 0
  property bool cursorActive: false
  // Only ticks while the panel is open, so a closed panel costs nothing to keep "1h ago" true.
  property double nowSec: 0

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The hero switch and the update button are the only two things to land on.
  readonly property int protectionIndex: 0
  readonly property int updateIndex: 1
  readonly property int selectableCount: 2

  readonly property var adguardStatus: ({
    ok: adguard.ok, installed: adguard.installed, running: adguard.running,
    httpsFiltering: adguard.httpsFiltering, blockedToday: adguard.blockedToday,
    filters: adguard.filters, exitNodeActive: adguard.exitNodeActive,
    error: adguard.lastError
  })

  readonly property var statRows: Model.categoryRows(adguard.filters)

  // Nothing is known until the first poll answers, so the panel must not assert a state.
  readonly property string heroTitle: adguard.polled ? Model.stateTitle(root.adguardStatus) : "AdGuard"
  readonly property string heroMeta: !adguard.polled
    ? ""
    : (adguard.installed
       ? Model.formatCount(adguard.blockedToday) + " blocked today"
       : Model.stateMeta(root.adguardStatus))

  // The update control speaks for itself, so its outcome never reaches the shared line.
  readonly property string transientText: adguard.lastError

  readonly property string updateLabel: adguard.updating
    ? "Checking for updates"
    : (adguard.updateSummary !== "" ? adguard.updateSummary : "Update filters")

  readonly property color markColor: adguard.exitNodeActive ? root.urgent : root.barForeground
  readonly property real markOpacity: adguard.effectiveRunning ? 1.0 : 0.35

  function resetPresentation() {
    root.cursorIndex = 0
    root.cursorActive = false
  }

  function moveCursor(dx, dy) {
    root.cursorActive = true
    if (dy === 0) return
    root.cursorIndex = Math.max(0, Math.min(root.selectableCount - 1,
                                            root.cursorIndex + (dy > 0 ? 1 : -1)))
  }

  function focusRow(index) {
    root.cursorActive = true
    root.cursorIndex = index
  }

  function activateCursor() {
    if (!root.cursorActive || adguard.busy) return
    if (root.cursorIndex === root.protectionIndex) adguard.toggleProtection()
    else if (root.cursorIndex === root.updateIndex) adguard.updateFilters()
  }

  onOpenedChanged: {
    root.resetPresentation()
    if (root.opened) root.nowSec = Date.now() / 1000
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.nowSec = Date.now() / 1000
  }

  AdGuardService {
    id: adguard
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Only reads are exposed: any local process can reach this socket, and starting or
    // stopping filtering is the panel's own confirmed action rather than an IPC verb.
    function refresh(): string { adguard.refresh(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The widget leaves the bar entirely when AdGuard is absent rather than sitting there
    // with nothing to say, but only once a poll has actually answered.
    visible: !adguard.polled || adguard.installed
    tooltipText: adguard.exitNodeActive
      ? "Exit node conflict"
      : (adguard.effectiveRunning ? "AdGuard is filtering" : "AdGuard is stopped")
    iconComponent: Component {
      Item {
        AdGuardIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.markColor
          opacity: root.markOpacity
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) adguard.toggleProtection()
      else if (buttonCode === Qt.MiddleButton) adguard.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      // j, k, l, h and x never arrive here: PanelKeyCatcher consumes them first.
      onTextKey: function(t) {
        var key = String(t).toLowerCase()
        if (key === "r") adguard.refresh()
        else if (adguard.busy) return
        else if (key === "t") adguard.toggleProtection()
        else if (key === "u") adguard.updateFilters()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.spacing.md

        Item {
          id: header
          width: parent.width
          implicitHeight: hero.implicitHeight
          // Exposed for the hero's trailingControl, whose `root` resolves to PanelHero
          // rather than this Panel.
          readonly property bool ringVisible: root.cursorActive && root.cursorIndex === root.protectionIndex
          function focusHero() { root.focusRow(root.protectionIndex) }

          PanelHero {
            id: hero
            width: parent.width
            title: root.heroTitle
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: adguard.effectiveRunning ? 1.0 : 0.5
            // Status only, the switch owns toggling for mouse and keyboard alike.
            iconComponent: Component {
              AdGuardIcon {
                iconSize: Style.font.display
                color: root.foreground
              }
            }

            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                visible: adguard.polled && adguard.installed
                checked: adguard.effectiveRunning
                busy: adguard.busy
                hasCursor: header.ringVisible
                foreground: hero.foreground
                onHovered: function(on) { if (on) header.focusHero() }
                onToggled: adguard.toggleProtection()

                PanelToolTip {
                  visible: powerSwitch.containsMouse
                  text: adguard.effectiveRunning ? "Stop filtering" : "Start filtering"
                  fontFamily: hero.fontFamily
                }
              }
            }
          }
        }

        Text {
          visible: !adguard.hasAnswer
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Waiting for AdGuard."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: root.transientText !== ""
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.transientText
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // Both features work alone and cannot work together: AdGuard's proxy opens its own
        // outbound connection and the exit node default route sends it back into the tunnel.
        Text {
          visible: adguard.exitNodeActive
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Tailscale exit node is on, so nothing reaches the internet while AdGuard filters."
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        Repeater {
          model: adguard.hasAnswer ? root.statRows : []
          delegate: StatRow {
            required property var modelData
            width: column.width
            label: modelData.label
            value: Model.formatCount(modelData.blocked)
          }
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        StatRow {
          visible: adguard.hasAnswer
          width: parent.width
          label: "Filters"
          value: Model.filtersMeta(adguard.filters)
        }

        StatRow {
          visible: adguard.hasAnswer
          width: parent.width
          label: "HTTPS filtering"
          value: adguard.httpsFiltering ? "on" : "off"
        }

        StatRow {
          visible: adguard.hasAnswer && adguard.lastUpdateTs > 0
          width: parent.width
          label: "Last updated"
          value: Model.updatedAgo(adguard.lastUpdateTs, root.nowSec).replace("updated ", "")
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        Button {
          visible: adguard.hasAnswer
          width: parent.width
          // The control reports its own progress and outcome, so neither needs a line of
          // its own above the numbers.
          text: root.updateLabel
          bordered: true
          enabled: !adguard.busy
          selected: root.cursorActive && root.cursorIndex === root.updateIndex
          hasCursor: root.cursorActive && root.cursorIndex === root.updateIndex
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: adguard.updateFilters()
        }
      }
    }
  }

  // Every line in the body is a label on the left and its value on the right, the rhythm
  // AdGuard's own desktop panel uses.
  component StatRow: Item {
    id: statRow
    required property string label
    required property string value

    implicitHeight: visible ? statLabel.implicitHeight + Style.spacing.controlPaddingY : 0

    Text {
      id: statLabel
      anchors.left: parent.left
      anchors.right: statValue.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.controlGap
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: statRow.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: statValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.rightMargin: Style.spacing.rowPaddingX
      textFormat: Text.PlainText
      text: statRow.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
