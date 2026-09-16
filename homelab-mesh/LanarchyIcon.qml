import QtQuick

// Circled-A mesh: LAN ring + three nodes that read as an anarchy A.
// Drawn, not a Nerd Font stand-in. Recolors with the theme; alarmed node is urgent.
Item {
  id: root
  property real iconSize: width > 0 ? width : 16
  property color color: "#c0caf5"
  property color alert: "#f7768e"
  property bool alarmed: false
  property bool active: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Canvas {
    id: mark
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var c = getContext("2d")
      var s = Math.min(width, height)
      c.reset()
      c.clearRect(0, 0, width, height)
      if (s < 4) return

      var ink = root.color
      var bad = root.alarmed ? root.alert : ink
      var cx = width / 2
      var cy = height / 2
      var ringR = s * 0.42
      var lw = Math.max(1.15, s * 0.075)

      c.strokeStyle = ink
      c.globalAlpha = root.active ? 1 : 0.88
      c.lineWidth = lw
      c.lineCap = "round"
      c.lineJoin = "round"
      c.beginPath()
      c.arc(cx, cy, ringR, 0, Math.PI * 2)
      c.stroke()

      var apex = { x: cx, y: cy - s * 0.18 }
      var left = { x: cx - s * 0.20, y: cy + s * 0.18 }
      var right = { x: cx + s * 0.20, y: cy + s * 0.18 }
      var t = 0.52
      var barL = { x: left.x + (apex.x - left.x) * t, y: left.y + (apex.y - left.y) * t }
      var barR = { x: right.x + (apex.x - right.x) * t, y: right.y + (apex.y - right.y) * t }

      c.beginPath()
      c.moveTo(left.x, left.y)
      c.lineTo(apex.x, apex.y)
      c.lineTo(right.x, right.y)
      c.stroke()
      c.beginPath()
      c.moveTo(barL.x, barL.y)
      c.lineTo(barR.x, barR.y)
      c.stroke()

      function dot(p, fill) {
        c.fillStyle = fill
        c.beginPath()
        c.arc(p.x, p.y, Math.max(1.35, s * 0.085), 0, Math.PI * 2)
        c.fill()
      }
      dot(apex, bad)
      dot(left, ink)
      dot(right, ink)
      c.globalAlpha = 1
    }
  }

  Connections {
    target: root
    function onColorChanged() { mark.requestPaint() }
    function onAlertChanged() { mark.requestPaint() }
    function onAlarmedChanged() { mark.requestPaint() }
    function onActiveChanged() { mark.requestPaint() }
  }

  SequentialAnimation on opacity {
    running: root.active && !root.alarmed
    loops: Animation.Infinite
    NumberAnimation { to: 0.7; duration: 1100; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1; duration: 1100; easing.type: Easing.InOutSine }
  }
}
