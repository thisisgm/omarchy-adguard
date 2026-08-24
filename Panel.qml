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
  // protection, HTTPS filtering, one row per filter, then the update button.
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

  // The mark matches its neighbours at rest and only takes a colour when something is wrong,
  // which is the OEM habit of saying nothing while it works.
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

        PanelHero {
          width: parent.width
          title: adguard.installed ? Model.formatCount(adguard.blockedToday) : "AdGuard"
          meta: adguard.installed ? "blocked today" : Model.stateMeta(root.adguardStatus)
          detail: adguard.installed ? Model.stateTitle(root.adguardStatus) : ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: adguard.effectiveRunning ? 1.0 : 0.5
          iconComponent: Component {
            AdGuardIcon {
              iconSize: Style.font.display
              color: root.foreground
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

        PanelSeparator { width: parent.width; foreground: root.foreground }

        Toggle {
          width: parent.width
          label: "Protection"
          description: Model.stateMeta(root.adguardStatus)
          titleSize: Style.font.body
          checked: adguard.effectiveRunning
          hasCursor: root.cursorActive && root.cursorIndex === root.protectionIndex
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: if (!adguard.busy) adguard.toggleProtection()
          onHovered: function(isHovered) {
            if (!isHovered) return
            root.cursorActive = true
            root.cursorIndex = root.protectionIndex
          }
        }

        Toggle {
          width: parent.width
          label: "HTTPS filtering"
          description: "Filters inside encrypted browser traffic"
          titleSize: Style.font.body
          checked: adguard.httpsFiltering
          hasCursor: root.cursorActive && root.cursorIndex === root.httpsIndex
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: if (!adguard.busy) adguard.toggleHttpsFiltering()
          onHovered: function(isHovered) {
            if (!isHovered) return
            root.cursorActive = true
            root.cursorIndex = root.httpsIndex
          }
        }

        // Both features work alone and cannot work together: AdGuard's proxy opens its own
        // outbound connection and the exit node's default route sends it back into the tunnel.
        Column {
          visible: adguard.exitNodeActive
          width: parent.width
          spacing: Style.spacing.hairline

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Tailscale exit node is active"
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Internet stays blocked while both are on. Stop AdGuard or turn the exit node off."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
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
          text: "No filter lists added. Add one with adguard-cli filters add <id>."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // A ListView rather than a Repeater because the list length is the user's to choose:
        // AdGuard offers about sixty lists, and a tall enough Column would outgrow the screen.
        ListView {
          id: filterList
          width: parent.width
          height: Math.min(contentHeight, Style.space(400))
          visible: root.filterCount > 0
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          spacing: Style.spacing.md
          model: root.filterRows

          delegate: Toggle {
            required property var modelData
            required property int index
            readonly property int rowIndex: root.firstFilterIndex + index

            width: filterList.width
            label: modelData.title
            titleSize: Style.font.body
            checked: modelData.enabled
            hasCursor: root.cursorActive && root.cursorIndex === rowIndex
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (!adguard.busy) adguard.toggleFilter(modelData.id, modelData.enabled)
            onHovered: function(isHovered) {
              if (!isHovered) return
              root.cursorActive = true
              root.cursorIndex = rowIndex
            }
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
}
