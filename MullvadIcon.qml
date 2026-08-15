import QtQuick
import QtQuick.Shapes
import qs.Commons

// Natively drawn shield, in the spirit of TailscaleIcon and DropboxIcon: vector
// rather than SVG or glyph, because the bar slot has a 16px optical canvas and
// both Qt SVG and Nerd Font glyphs render unevenly at that size.
//
// Filled = tunnel up. Outlined = idle. The diagonal bar marks disconnected, the
// badge marks attention (no account, or traffic outside the tunnel).
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color badgeColor: Color.urgent
  property bool filled: false
  property bool crossed: false
  property bool warning: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real outlineWidth: Math.max(1, root.iconSize * 0.1)

  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      fillColor: root.filled ? root.color : "transparent"
      strokeColor: root.filled ? "transparent" : root.color
      strokeWidth: root.filled ? 0 : root.outlineWidth
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap

      // Shield: straight shoulders on top, straight flanks down to the middle,
      // then two curves meeting at the bottom point.
      startX: root.width * 0.5
      startY: root.height * 0.08
      PathLine { x: root.width * 0.88; y: root.height * 0.21 }
      PathLine { x: root.width * 0.88; y: root.height * 0.50 }
      PathQuad {
        x: root.width * 0.5;  y: root.height * 0.94
        controlX: root.width * 0.88; controlY: root.height * 0.79
      }
      PathQuad {
        x: root.width * 0.12; y: root.height * 0.50
        controlX: root.width * 0.12; controlY: root.height * 0.79
      }
      PathLine { x: root.width * 0.12; y: root.height * 0.21 }
      PathLine { x: root.width * 0.5;  y: root.height * 0.08 }
    }
  }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.2
    height: Math.max(2, parent.height * 0.13)
    radius: height / 2
    color: root.color
    rotation: -45
  }

  Rectangle {
    visible: root.warning
    width: Math.max(7, parent.width * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom

    Text {
      anchors.centerIn: parent
      text: "!"
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Math.max(6, parent.height * 0.72)
      font.bold: true
    }
  }
}
