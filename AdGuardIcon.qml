import QtQuick
import QtQuick.Shapes
import qs.Commons

// The checkmark is knocked out of the shield rather than drawn in white, so the mark
// stays one colour and inherits the theme the way the OEM tailscale mark does.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  // AdGuard's official mark is drawn on a 128 grid, but the shield itself occupies only
  // this box; scaling to the box rather than the grid keeps the bar mark from rendering
  // smaller than its neighbours.
  readonly property real boxXUnits: 11.4
  readonly property real boxYUnits: 10.7
  readonly property real boxWidthUnits: 105.3
  readonly property real boxHeightUnits: 106.7

  readonly property real unit: iconSize / boxHeightUnits
  readonly property real drawnWidth: boxWidthUnits * unit
  readonly property real centeringOffset: (iconSize - drawnWidth) / 2

  readonly property string shieldPath: "M64 10.7a95.4 95.4 0 0 0-52.5 15.6 95.4 95.4 0 0 0 52.4 90.9l.1.1.1-.1c16-8.1 30-20.9 39.7-37.7a95.4 95.4 0 0 0 12.7-53.2c-15-9.9-33-15.6-52.5-15.6Z"
  readonly property string checkPath: "M80.6 49.4a5 5 0 0 1 0 6.5L68.2 69.5c-4.2 5.2-6.9 5.2-11.3 0L49.2 61a5 5 0 0 1 0-6.5 3.8 3.8 0 0 1 5.8 0l7.6 8.3 12.1-13.5a3.8 3.8 0 0 1 5.9 0Z"

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    transform: [
      Scale { xScale: root.unit; yScale: root.unit },
      Translate { x: -root.boxXUnits * root.unit + root.centeringOffset; y: -root.boxYUnits * root.unit }
    ]

    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      // Even-odd turns the second subpath into a hole instead of a second filled shape.
      fillRule: ShapePath.OddEvenFill

      PathSvg { path: root.shieldPath + " " + root.checkPath }
    }
  }
}
