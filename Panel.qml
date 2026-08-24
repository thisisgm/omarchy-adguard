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

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var filterRows: adguard.filters
  readonly property int filterCount: filterRows ? filterRows.length : 0
  // The hero switch owns protection, then the HTTPS row, the filter rows, then the button.
  readonly property int protectionIndex: 0
  readonly property int httpsIndex: 1
  readonly property int firstFilterIndex: 2
  readonly property int updateIndex: firstFilterIndex + filterCount
  readonly property int selectableCount: updateIndex + 1

  readonly property var adguardStatus: ({
    ok: adguard.ok, installed: adguard.installed, running: adguard.running,
    httpsFiltering: adguard.httpsFiltering, blockedToday: adguard.blockedToday,
    filters: adguard.filters, exitNodeActive: adguard.exitNodeActive,
    error: adguard.lastError
  })

  readonly property string heroMeta: adguard.installed
    ? Model.formatCount(adguard.blockedToday) + " blocked today"
    : Model.stateMeta(root.adguardStatus)

  // The mark matches its neighbours at rest and only takes a colour when something is
  // wrong, which is the OEM habit of saying nothing while it works.
  readonly property color markColor: adguard.exitNodeActive ? root.urgent : root.barForeground
  readonly property real markOpacity: adguard.effectiveRunning ? 1.0 : 0.35

  function resetPresentation() {
    root.cursorIndex = 0
    root.cursorActive = false
  }

  function moveCursor(dx, dy) {
    if (root.selectableCount === 0) return
    root.cursorActive = true
    if (dy === 0) return
    root.cursorIndex = Math.max(0, Math.min(root.selectableCount - 1,
                                            root.cursorIndex + (dy > 0 ? 1 : -1)))
    root.revealCursor()
  }

  // The filter list scrolls, so a cursor moved past its edge has to bring the list along.
  function revealCursor() {
    var row = root.cursorIndex - root.firstFilterIndex
    if (row < 0 || row >= root.filterCount) return
    filterList.positionViewAtIndex(row, ListView.Contain)
  }

  function focusRow(index) {
    root.cursorActive = true
    root.cursorIndex = index
  }

  function activateCursor() {
    if (!root.cursorActive || adguard.busy) return
    if (root.cursorIndex === root.protectionIndex) adguard.toggleProtection()
    else if (root.cursorIndex === root.httpsIndex) adguard.toggleHttpsFiltering()
    else if (root.cursorIndex === root.updateIndex) adguard.updateFilters()
    else {
      var row = root.filterRows[root.cursorIndex - root.firstFilterIndex]
      if (row) adguard.toggleFilter(row.id, row.enabled)
    }
  }

  onOpenedChanged: root.resetPresentation()

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
    function refresh(): string { adguard.refresh(); return "ok" }
    function protection(): string { adguard.toggleProtection(); return "ok" }
    function update(): string { adguard.updateFilters(); return "ok" }
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
        else if (key === "s") adguard.toggleHttpsFiltering()
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
            title: Model.stateTitle(root.adguardStatus)
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
                visible: adguard.installed
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
          visible: adguard.actionStatus !== "" || adguard.lastError !== ""
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: adguard.actionStatus !== "" ? adguard.actionStatus : adguard.lastError
          color: adguard.lastError !== "" && adguard.actionStatus === "" ? root.urgent : root.dim
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

        StateRow {
          width: parent.width
          rowIndex: root.httpsIndex
          label: "HTTPS filtering"
          on: adguard.httpsFiltering
          onTriggered: adguard.toggleHttpsFiltering()
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        PanelSectionHeader {
          width: parent.width
          text: "FILTERS"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          visible: root.filterCount === 0
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "No filter lists added."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // A ListView rather than a Repeater because the list length is the user's to choose:
        // AdGuard offers about sixty lists, and a tall enough Column would outgrow the screen.
        ListView {
          id: filterList
          width: parent.width
          height: Math.min(contentHeight, Style.space(280))
          visible: root.filterCount > 0
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          model: root.filterRows

          delegate: StateRow {
            required property var modelData
            required property int index

            width: filterList.width
            rowIndex: root.firstFilterIndex + index
            label: modelData.title
            on: modelData.enabled
            onTriggered: adguard.toggleFilter(modelData.id, modelData.enabled)
          }
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        Button {
          width: parent.width
          text: "Update filters"
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

  // One row shape for every on/off line, so a filter list and the HTTPS mode read alike.
  // State is a leading check and a dimmed label, the way the OEM audio rows mark a device,
  // rather than a switch on every row.
  component StateRow: CursorSurface {
    id: stateRow
    required property int rowIndex
    required property string label
    required property bool on
    signal triggered()

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    Row {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.spacing.controlGap

      Text {
        width: Style.space(16)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: stateRow.on ? "󰄲" : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        width: parent.width - Style.space(16) - Style.spacing.controlGap
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: stateRow.label
        color: stateRow.on ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      enabled: !adguard.busy
      onContainsMouseChanged: if (containsMouse) root.focusRow(stateRow.rowIndex)
      onClicked: stateRow.triggered()
    }
  }
}
