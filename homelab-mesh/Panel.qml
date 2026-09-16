import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// OmarPlugs-vcy: Quattro KeyboardPanel + Pulse WatchlistRow density.
// Probe JSON unchanged (machines / lan / proxies).
Panel {
  id: root
  moduleName: "donnie.homelab-mesh"
  ipcTarget: "donnie.homelab-mesh"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.72)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/homelab-mesh"
  readonly property int refreshIntervalSec: {
    var n = parseInt(String(setting("refreshIntervalSec", 15)), 10)
    if (!isFinite(n)) n = 15
    return Math.max(5, Math.min(120, n))
  }

  property bool loading: false
  property bool expectedStop: false
  property string error: ""
  property string asOf: ""
  property var machines: []
  property var lan: []
  property var proxies: []

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function statusGlyph(status) {
    var s = String(status || "unknown")
    if (s === "up" || s === "down") return "●"
    return "○"
  }

  function statusColor(status) {
    var s = String(status || "unknown")
    if (s === "up") return root.foreground
    if (s === "down") return root.urgent
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
    var s = root.asOf
    var t = s.indexOf("T")
    if (t >= 0 && s.length >= t + 9) return s.substring(t + 1, t + 9)
    return s
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
    root.error = ""
    root.loading = false
  }

  function refresh() {
    root.loading = true
    root.expectedStop = false
    if (probeProc.running) {
      root.expectedStop = true
      probeProc.running = false
    }
    probeProc.command = ["python3", root.pluginDir + "/probe.py"]
    probeProc.running = true
  }

  onOpenedChanged: {
    if (opened) refresh()
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
    interval: root.refreshIntervalSec * 1000
    running: root.opened
    repeat: true
    onTriggered: if (root.opened && !probeProc.running) root.refresh()
  }

  // Pulse WatchlistRow height family (~42) without sparkline/edit chrome.
  component MeshRow: Item {
    property string label: ""
    property string status: "unknown"
    property string metric: ""
    property bool showMetric: true

    width: ListView.view ? ListView.view.width : (parent ? parent.width : 0)
    height: Style.space(42)

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(9)
      anchors.rightMargin: Style.space(9)
      spacing: Style.space(8)

      Text {
        text: root.statusGlyph(status)
        color: root.statusColor(status)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.preferredWidth: Style.space(14)
      }
      Text {
        text: label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
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
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
    }
  }

  component BandCap: Text {
    property string title: ""
    text: title
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.1
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌘"
    tooltipText: "Homelab Mesh"
    active: root.opened
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) root.refresh()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (String(text || "").toLowerCase() === "r") root.refresh()
      }

      Column {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(8)

        Item {
          width: parent.width
          height: Style.space(28)
          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Homelab Mesh"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.loading ? "probing…" : root.asOfShort()
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          visible: root.error !== ""
          width: parent.width
          text: root.error
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        BandCap { title: "MACHINES"; width: parent.width }
        Column {
          width: parent.width
          spacing: 0
          Repeater {
            model: root.machines
            MeshRow {
              required property var modelData
              width: parent.width
              label: String(modelData.label || modelData.id || "")
              status: String(modelData.status || "unknown")
              metric: root.rttText(modelData)
            }
          }
        }

        BandCap { title: "LAN"; width: parent.width }
        ListView {
          id: lanList
          width: parent.width
          height: Math.min(Style.space(42) * 10, Style.space(42) * Math.max(1, root.lan.length))
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.lan
          delegate: MeshRow {
            required property var modelData
            label: String(modelData.label || modelData.id || "")
            status: String(modelData.status || "unknown")
            metric: root.rttText(modelData)
          }
        }

        BandCap { title: "PROXIES"; width: parent.width }
        Column {
          width: parent.width
          spacing: 0
          Repeater {
            model: root.proxies
            MeshRow {
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
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Esc · r refresh · glance only"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
