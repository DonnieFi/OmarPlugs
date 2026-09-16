import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// v1 polish: Pulse-density rows + weather-muted secondaries.
// Bands: Machines → LAN (scroll) → Proxies. unknown/null rtt → muted "—".
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool loading: false
  property string error: ""
  property string asOf: ""
  property var machines: []
  property var lan: []
  property var proxies: []
  property bool expectedStop: false

  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/homelab-mesh"
  readonly property string fontFamily: Style.font.family
  readonly property color fg: Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.42)
  readonly property color upColor: fg
  readonly property color downColor: Color.urgent
  readonly property color cardBg: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.94)
  readonly property color rowLine: Qt.rgba(fg.r, fg.g, fg.b, 0.08)

  function open(payloadJson) {
    root.opened = true
    refresh()
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
    if (probeProc.running) {
      root.expectedStop = true
      probeProc.running = false
    }
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "donnie.homelab-mesh")
    else
      close()
  }

  function refresh() {
    root.error = ""
    root.loading = true
    root.expectedStop = false
    if (probeProc.running) {
      root.expectedStop = true
      probeProc.running = false
    }
    probeProc.command = ["python3", root.pluginDir + "/probe.py"]
    probeProc.running = true
  }

  function applyPayload(text) {
    var data = {}
    try { data = JSON.parse(text || "{}") || {} } catch (e) {
      root.error = "Bad probe JSON"
      root.loading = false
      return
    }
    if (data.error) {
      root.error = String(data.error)
      root.loading = false
      return
    }
    root.asOf = String(data.as_of || "")
    root.machines = data.machines instanceof Array ? data.machines : []
    root.lan = data.lan instanceof Array ? data.lan : []
    root.proxies = data.proxies instanceof Array ? data.proxies : []
    root.loading = false
  }

  function statusGlyph(status) {
    var s = String(status || "unknown")
    if (s === "up" || s === "down") return "●"
    return "○"
  }

  function statusColor(status) {
    var s = String(status || "unknown")
    if (s === "up") return root.upColor
    if (s === "down") return root.downColor
    return root.muted
  }

  function rttText(row) {
    if (!row || row.status === "unknown" || row.status === "down") return "—"
    if (row.rtt_ms === null || row.rtt_ms === undefined) return "—"
    var n = Number(row.rtt_ms)
    if (!isFinite(n)) return "—"
    if (n < 10) return (Math.round(n * 10) / 10) + " ms"
    return Math.round(n) + " ms"
  }

  function asOfShort() {
    if (!root.asOf) return ""
    // Prefer local clock fragment after T if ISO-ish
    var s = root.asOf
    var t = s.indexOf("T")
    if (t >= 0 && s.length >= t + 9) return s.substring(t + 1, t + 9)
    return s
  }

  Process {
    id: probeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.opened || root.expectedStop) return
        root.applyPayload(String(text || ""))
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (root.expectedStop) {
        root.expectedStop = false
        if (root.opened && root.loading) {
          probeProc.command = ["python3", root.pluginDir + "/probe.py"]
          probeProc.running = true
        }
        return
      }
      if (!root.opened) return
      if (exitCode !== 0 && root.machines.length === 0 && !root.error)
        root.error = "Probe failed"
      root.loading = false
    }
  }

  Timer {
    interval: 15000
    running: root.opened
    repeat: true
    onTriggered: if (root.opened && !probeProc.running) root.refresh()
  }

  // Pulse-style one-line row: glyph + label left, muted metric right
  component StatusRow: Item {
    property string label: ""
    property string status: "unknown"
    property string metric: ""
    property bool showMetric: true

    height: Style.space(22)
    width: parent ? parent.width : 0

    RowLayout {
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        text: root.statusGlyph(status)
        color: root.statusColor(status)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.preferredWidth: Style.space(12)
      }
      Text {
        text: label
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        Layout.fillWidth: true
      }
      Text {
        visible: showMetric
        text: metric
        color: (metric === "—") ? root.muted : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignRight
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: root.rowLine
    }
  }

  component BandHeader: Text {
    property string title: ""
    text: title
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
  }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "donnie-homelab-mesh"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.5)
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()

      Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(Style.space(420), keyCatcher.width - Style.space(48))
        height: Math.min(cardCol.implicitHeight + Style.space(28), keyCatcher.height - Style.space(48))
        radius: Style.cornerRadius
        color: root.cardBg
        border.width: 1
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
        clip: true

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
          id: cardCol
          anchors.fill: parent
          anchors.margins: Style.space(14)
          spacing: Style.space(10)

          RowLayout {
            Layout.fillWidth: true
            Text {
              text: "HOMELAB MESH"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.5
              Layout.fillWidth: true
            }
            Text {
              text: root.loading ? "probing…" : root.asOfShort()
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            visible: root.error !== ""
            text: root.error
            color: root.downColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            Layout.fillWidth: true
            wrapMode: Text.Wrap
          }

          BandHeader { title: "MACHINES" }
          Column {
            Layout.fillWidth: true
            spacing: 0
            Repeater {
              model: root.machines
              StatusRow {
                required property var modelData
                width: parent.width
                label: String(modelData.label || modelData.id || "")
                status: String(modelData.status || "unknown")
                metric: root.rttText(modelData)
              }
            }
          }

          BandHeader { title: "LAN" }
          // Clip/scroll — don't grow panel for ~17 hosts
          Flickable {
            id: lanFlick
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Style.space(22) * 8, Style.space(22) * Math.max(1, root.lan.length))
            contentWidth: width
            contentHeight: lanCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Column {
              id: lanCol
              width: lanFlick.width
              spacing: 0
              Repeater {
                model: root.lan
                StatusRow {
                  required property var modelData
                  width: parent.width
                  label: String(modelData.label || modelData.id || "")
                  status: String(modelData.status || "unknown")
                  metric: root.rttText(modelData)
                }
              }
            }
          }

          BandHeader { title: "PROXIES" }
          Column {
            Layout.fillWidth: true
            spacing: 0
            Repeater {
              model: root.proxies
              StatusRow {
                required property var modelData
                width: parent.width
                label: String(modelData.label || modelData.id || "")
                status: String(modelData.status || "unknown")
                metric: ""
                showMetric: false
              }
            }
          }

          Text {
            text: "Esc · glance only"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            Layout.alignment: Qt.AlignHCenter
          }
        }
      }
    }
  }
}
