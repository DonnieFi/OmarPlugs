import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// v1: glance-only mesh overview. Probe is live projection (arch shape).
// Bands: Machines → LAN → Proxies. unknown/null rtt → muted "—".
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

  // Third-party install path (omarchy clones here). Absolute so Process finds probe.py.
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/homelab-mesh"
  readonly property string fontFamily: Style.font.family
  readonly property color fg: Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.45)
  readonly property color upColor: fg
  readonly property color downColor: Color.urgent
  readonly property color cardBg: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.92)

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
    if (s === "up") return "●"
    if (s === "down") return "●"
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
    return (Math.round(n * 10) / 10) + " ms"
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

  component NodeChip: Rectangle {
    property string label: ""
    property string status: "unknown"
    property string detail: ""
    property bool showDetail: true

    implicitWidth: chipCol.implicitWidth + Style.space(20)
    implicitHeight: chipCol.implicitHeight + Style.space(14)
    radius: Style.cornerRadius
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
    border.width: 1
    border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

    Column {
      id: chipCol
      anchors.centerIn: parent
      spacing: Style.space(2)

      Row {
        spacing: Style.space(8)
        anchors.horizontalCenter: parent.horizontalCenter
        Text {
          text: root.statusGlyph(status)
          color: root.statusColor(status)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          text: label
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }
      Text {
        visible: showDetail
        text: detail
        color: (detail === "—") ? root.muted : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.horizontalCenter: parent.horizontalCenter
      }
    }
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
      color: Qt.rgba(0, 0, 0, 0.55)
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
        width: Math.min(Style.space(560), keyCatcher.width - Style.space(48))
        height: Math.min(cardCol.implicitHeight + Style.space(32), keyCatcher.height - Style.space(48))
        radius: Style.cornerRadius
        color: root.cardBg
        border.width: 1
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
        clip: true

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
          id: cardCol
          anchors.fill: parent
          anchors.margins: Style.space(16)
          spacing: Style.space(14)

          RowLayout {
            Layout.fillWidth: true
            Text {
              text: "HOMELAB MESH"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.5
              Layout.fillWidth: true
            }
            Text {
              text: root.loading ? "probing…" : (root.asOf || "")
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

          Text {
            text: "Machines"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Flow {
            Layout.fillWidth: true
            spacing: Style.space(8)
            Repeater {
              model: root.machines
              NodeChip {
                required property var modelData
                label: String(modelData.label || modelData.id || "")
                status: String(modelData.status || "unknown")
                detail: root.rttText(modelData)
              }
            }
          }

          Text {
            text: "LAN"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Flow {
            Layout.fillWidth: true
            spacing: Style.space(8)
            Repeater {
              model: root.lan
              NodeChip {
                required property var modelData
                label: String(modelData.label || modelData.id || "")
                status: String(modelData.status || "unknown")
                detail: root.rttText(modelData)
              }
            }
          }

          Text {
            text: "Proxies"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Flow {
            Layout.fillWidth: true
            spacing: Style.space(8)
            Repeater {
              model: root.proxies
              NodeChip {
                required property var modelData
                label: String(modelData.label || modelData.id || "")
                status: String(modelData.status || "unknown")
                detail: "—"
                showDetail: false
              }
            }
          }

          Item { Layout.fillHeight: true; Layout.preferredHeight: Style.space(4) }

          Text {
            text: "Esc to close · glance only"
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
