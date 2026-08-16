import QtQuick
import qs.Commons
import "MapData.js" as MapData
import "Model.js" as Model

// Equirectangular world drawn as a dot grid, with one marker on the relay the
// tunnel exits through.
//
// Everything is painted on a single Canvas, markers included. The grid alone is
// 2160 cells; as scene-graph items that would be a lot of nodes inside the
// process that also draws the bar and the lock screen, for a backdrop that
// barely changes.
//
// Modelled on the WorldMap in artemisa81/omarchy-ivpn-plugin, which solved the
// same problem for IVPN.
Item {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  // {lat, lon}, or null to draw the map with no marker on it.
  property var server: null

  implicitHeight: Math.round(width * MapData.HEIGHT / MapData.WIDTH)

  // Canvas paints imperatively, so every input it reads needs an explicit
  // repaint — a binding would not reach inside onPaint.
  onForegroundChanged: canvas.requestPaint()
  onAccentChanged: canvas.requestPaint()
  onServerChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()

      var w = width
      var h = height
      if (w <= 0 || h <= 0) return

      var cellW = w / MapData.WIDTH
      var cellH = h / MapData.HEIGHT
      var dot = Math.max(0.7, Math.min(cellW, cellH) * 0.34)

      // Land is a texture, not content: the marker is what the eye should find.
      ctx.fillStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.34)
      for (var row = 0; row < MapData.rows.length; row++) {
        var line = MapData.rows[row]
        for (var col = 0; col < line.length; col++) {
          if (line.charAt(col) !== "1") continue
          ctx.beginPath()
          ctx.arc((col + 0.5) * cellW, (row + 0.5) * cellH, dot, 0, Math.PI * 2)
          ctx.fill()
        }
      }

      if (!root.server) return
      var point = Model.projectToMap(root.server.lat, root.server.lon)
      if (!point) return

      var x = point.x * w
      var y = point.y * h
      var radius = Math.max(2, h * 0.045)

      ctx.strokeStyle = Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
      ctx.lineWidth = Math.max(1, h * 0.01)
      ctx.beginPath()
      ctx.arc(x, y, radius * 1.9, 0, Math.PI * 2)
      ctx.stroke()

      ctx.fillStyle = root.accent
      ctx.beginPath()
      ctx.arc(x, y, radius, 0, Math.PI * 2)
      ctx.fill()
    }
  }
}
