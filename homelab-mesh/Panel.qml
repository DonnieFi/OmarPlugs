import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// OmarPlugs-5oy.1: Quattro KeyboardPanel + inventory setup (view stack).
// Glance JSON unchanged (machines / lan / proxies). Setup edits nodes[] via inventory_cli.
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

  // glance | setup | form
  property string view: "glance"
  property bool loading: false
  property bool expectedStop: false
  property string error: ""
  property string asOf: ""
  property var machines: []
  property var lan: []
  property var proxies: []

  // setup / form state
  property var nodes: []
  property bool inventoryLoading: false
  property string inventoryError: ""
  property bool formIsNew: true
  property string formId: ""
  property string formType: "machine"   // machine | host | proxy
  property string formLabel: ""
  property string formDns: ""
  property string formIp: ""
  property string formCheck: "http"     // http | tcp
  property string formUrl: ""
  property string formPort: ""
  property bool formConfirmDelete: false
  property bool formFieldFocused: false

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

  function slugify(label) {
    var s = String(label || "").toLowerCase().trim()
    s = s.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
    return s || "node"
  }

  function nodeTarget(n) {
    if (!n) return ""
    var t = String(n.type || "")
    if (t === "proxy") {
      if (String(n.check || "") === "http") return String(n.url || "")
      var h = String(n.dns || n.ip || "")
      if (h && n.port !== undefined && n.port !== null) return h + ":" + n.port
      return h
    }
    var parts = []
    if (n.dns) parts.push(String(n.dns))
    if (n.ip) parts.push(String(n.ip))
    return parts.join(" · ")
  }

  function goSetup() {
    root.view = "setup"
    root.formConfirmDelete = false
    loadInventory()
  }

  function goGlance() {
    root.view = "glance"
    root.formConfirmDelete = false
    root.formFieldFocused = false
    if (root.opened) refresh()
  }

  function goFormNew() {
    root.formIsNew = true
    root.formId = ""
    root.formType = "machine"
    root.formLabel = ""
    root.formDns = ""
    root.formIp = ""
    root.formCheck = "http"
    root.formUrl = ""
    root.formPort = ""
    root.formConfirmDelete = false
    root.view = "form"
  }

  function goFormEdit(node) {
    root.formIsNew = false
    root.formId = String(node.id || "")
    root.formType = String(node.type || "machine")
    root.formLabel = String(node.label || "")
    root.formDns = String(node.dns || "")
    root.formIp = (node.ip === null || node.ip === undefined) ? "" : String(node.ip)
    root.formCheck = String(node.check || "http")
    root.formUrl = String(node.url || "")
    root.formPort = (node.port === null || node.port === undefined) ? "" : String(node.port)
    root.formConfirmDelete = false
    root.view = "form"
  }

  function navigateBack() {
    if (root.view === "form") {
      root.view = "setup"
      root.formConfirmDelete = false
      root.formFieldFocused = false
      return
    }
    if (root.view === "setup") {
      goGlance()
      return
    }
    root.close()
  }

  function loadInventory() {
    root.inventoryError = ""
    root.inventoryLoading = true
    if (invDumpProc.running) invDumpProc.running = false
    invDumpProc.command = ["python3", root.pluginDir + "/inventory_cli.py", "dump"]
    invDumpProc.running = true
  }

  function applyInventoryDump(text) {
    var data = {}
    try { data = JSON.parse(text || "{}") || {} } catch (e) {
      root.inventoryError = "Bad inventory JSON"
      root.inventoryLoading = false
      return
    }
    if (data.error) {
      root.inventoryError = String(data.error)
      root.inventoryLoading = false
      return
    }
    root.nodes = data.nodes instanceof Array ? data.nodes : []
    root.inventoryLoading = false
    if (data.migratedFromV1) {
      // migrate once on first setup open when still on v1 file
      if (invMigrateProc.running) invMigrateProc.running = false
      invMigrateProc.command = ["python3", root.pluginDir + "/inventory_cli.py", "migrate"]
      invMigrateProc.running = true
    }
  }

  function buildFormNode() {
    var label = String(root.formLabel || "").trim()
    if (!label) return null
    var node = {
      id: root.formIsNew ? root.slugify(label) : String(root.formId || root.slugify(label)),
      type: String(root.formType || "machine"),
      label: label
    }
    var dns = String(root.formDns || "").trim()
    var ip = String(root.formIp || "").trim()
    if (node.type === "machine" || node.type === "host") {
      if (dns) node.dns = dns
      node.ip = ip ? ip : null
      if (!dns && !ip) return null
      return node
    }
    node.check = String(root.formCheck || "tcp")
    if (node.check === "http") {
      var url = String(root.formUrl || "").trim()
      if (!url) return null
      node.url = url
      return node
    }
    if (dns) node.dns = dns
    if (ip) node.ip = ip
    else node.ip = null
    var port = parseInt(String(root.formPort || ""), 10)
    if (!isFinite(port)) return null
    if (!dns && !ip) return null
    node.port = port
    return node
  }

  function saveForm() {
    var node = root.buildFormNode()
    if (!node) {
      root.inventoryError = "Fill required fields"
      return
    }
    var next = []
    var i
    if (root.formIsNew) {
      for (i = 0; i < root.nodes.length; i++) next.push(root.nodes[i])
      next.push(node)
    } else {
      for (i = 0; i < root.nodes.length; i++) {
        if (String(root.nodes[i].id) === String(root.formId)) next.push(node)
        else next.push(root.nodes[i])
      }
    }
    writeNodes(next)
  }

  function deleteFormNode() {
    if (!root.formConfirmDelete) {
      root.formConfirmDelete = true
      return
    }
    var next = []
    var i
    for (i = 0; i < root.nodes.length; i++) {
      if (String(root.nodes[i].id) !== String(root.formId)) next.push(root.nodes[i])
    }
    writeNodes(next)
  }

  function writeNodes(nextNodes) {
    root.inventoryError = ""
    var payload = JSON.stringify({ schemaVersion: 2, nodes: nextNodes })
    // Write via temp file: JSON has no single-quotes so bash single-quoting is safe.
    invWriteProc.command = [
      "bash", "-c",
      "f=$(mktemp /tmp/homelab-mesh-inv.XXXXXX.json) && printf '%s' '" + payload.replace(/'/g, "'\\''") + "' > \"$f\" && python3 \"" + root.pluginDir + "/inventory_cli.py\" write \"$f\"; ec=$?; rm -f \"$f\"; exit $ec"
    ]
    invWriteProc.running = true
  }

  onOpenedChanged: {
    if (opened) {
      root.view = "glance"
      refresh()
    } else {
      root.view = "glance"
      root.formFieldFocused = false
    }
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

  Process {
    id: invDumpProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyInventoryDump(String(text || ""))
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.inventoryLoading)
        root.inventoryError = "Inventory dump failed"
      root.inventoryLoading = false
    }
  }

  Process {
    id: invMigrateProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  Process {
    id: invWriteProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (String(text || "").length)
          root.inventoryError = String(text).trim()
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        if (!root.inventoryError) root.inventoryError = "Save failed"
        return
      }
      root.view = "setup"
      root.formConfirmDelete = false
      root.formFieldFocused = false
      root.loadInventory()
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: root.opened && root.view === "glance"
    repeat: true
    onTriggered: if (root.opened && root.view === "glance" && !probeProc.running) root.refresh()
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

  component SetupRow: Item {
    property var node: ({})
    signal activated()

    width: parent ? parent.width : 0
    height: Style.space(42)

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(9)
      anchors.rightMargin: Style.space(9)
      spacing: Style.space(8)

      Rectangle {
        Layout.preferredWidth: chipText.implicitWidth + Style.space(12)
        Layout.preferredHeight: Style.space(22)
        radius: Style.space(4)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
        Text {
          id: chipText
          anchors.centerIn: parent
          text: String(node.type || "")
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
      Text {
        text: String(node.label || node.id || "")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
        Layout.fillWidth: true
      }
      Text {
        text: root.nodeTarget(node)
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: Style.space(140)
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

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: activated()
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

  component SegBtn: Rectangle {
    property string label: ""
    property bool active: false
    signal tapped()
    implicitWidth: segLab.implicitWidth + Style.space(16)
    implicitHeight: Style.space(28)
    radius: Style.space(4)
    color: active ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, active ? 0.28 : 0.10)
    Text {
      id: segLab
      anchors.centerIn: parent
      text: label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: active
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tapped() }
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
      // Block Esc/keys while form fields focused — TextField handles input.
      enabled: !(root.view === "form" && root.formFieldFocused)
      onCloseRequested: root.navigateBack()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (root.view !== "glance") return
        if (String(text || "").toLowerCase() === "r") root.refresh()
      }

      Column {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(8)

        // Header: title + gear (Setup) / as-of
        Item {
          width: parent.width
          height: Style.space(28)
          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.view === "glance" ? "Homelab Mesh"
                : (root.view === "setup" ? "Setup" : (root.formIsNew ? "Add node" : "Edit node"))
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            id: gearBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.view === "glance"
            text: "⚙"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(6)
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goSetup()
            }
          }
          Text {
            anchors.right: gearBtn.visible ? gearBtn.left : parent.right
            anchors.rightMargin: gearBtn.visible ? Style.space(12) : 0
            anchors.verticalCenter: parent.verticalCenter
            visible: root.view === "glance"
            text: root.loading ? "probing…" : root.asOfShort()
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          visible: root.view === "glance" && root.error !== ""
          width: parent.width
          text: root.error
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Text {
          visible: (root.view === "setup" || root.view === "form") && root.inventoryError !== ""
          width: parent.width
          text: root.inventoryError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        // ——— GLANCE ———
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.view === "glance"

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
            text: "Esc · r refresh · ⚙ Setup"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ——— SETUP LIST ———
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.view === "setup"

          Text {
            visible: root.inventoryLoading
            width: parent.width
            text: "Loading…"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Column {
            width: parent.width
            spacing: 0
            visible: !root.inventoryLoading && root.nodes.length > 0
            Repeater {
              model: root.nodes
              SetupRow {
                required property var modelData
                width: parent.width
                node: modelData
                onActivated: root.goFormEdit(modelData)
              }
            }
          }

          Rectangle {
            visible: !root.inventoryLoading && root.nodes.length === 0
            width: parent.width
            height: Style.space(64)
            radius: Style.space(6)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            Text {
              anchors.centerIn: parent
              text: "Add a node"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goFormNew()
            }
          }

          Row {
            spacing: Style.space(8)
            visible: !root.inventoryLoading
            Rectangle {
              implicitWidth: addLab.implicitWidth + Style.space(20)
              implicitHeight: Style.space(32)
              radius: Style.space(4)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
              Text {
                id: addLab
                anchors.centerIn: parent
                text: "Add node"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.goFormNew()
              }
            }
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Esc back to glance"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ——— FORM ———
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.view === "form"

          Text {
            text: "Type"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Row {
            spacing: Style.space(6)
            SegBtn { label: "machine"; active: root.formType === "machine"; onTapped: root.formType = "machine" }
            SegBtn { label: "host"; active: root.formType === "host"; onTapped: root.formType = "host" }
            SegBtn { label: "proxy"; active: root.formType === "proxy"; onTapped: root.formType = "proxy" }
          }

          Text {
            text: "Label"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          TextField {
            id: labelField
            width: parent.width
            text: root.formLabel
            placeholderText: "required"
            onTextChanged: root.formLabel = text
            onActiveFocusChanged: root.formFieldFocused = activeFocus || dnsField.activeFocus || ipField.activeFocus || urlField.activeFocus || portField.activeFocus
          }

          Text {
            visible: root.formType !== "proxy" || root.formCheck === "tcp"
            text: "DNS"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          TextField {
            id: dnsField
            width: parent.width
            visible: root.formType !== "proxy" || root.formCheck === "tcp"
            text: root.formDns
            placeholderText: "hostname.lan"
            onTextChanged: root.formDns = text
            onActiveFocusChanged: root.formFieldFocused = activeFocus || labelField.activeFocus || ipField.activeFocus || urlField.activeFocus || portField.activeFocus
          }

          Text {
            visible: root.formType !== "proxy" || root.formCheck === "tcp"
            text: "IP"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          TextField {
            id: ipField
            width: parent.width
            visible: root.formType !== "proxy" || root.formCheck === "tcp"
            text: root.formIp
            placeholderText: "optional if DNS set"
            onTextChanged: root.formIp = text
            onActiveFocusChanged: root.formFieldFocused = activeFocus || labelField.activeFocus || dnsField.activeFocus || urlField.activeFocus || portField.activeFocus
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.formType === "proxy"
            Text {
              text: "Check"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Row {
              spacing: Style.space(6)
              SegBtn { label: "http"; active: root.formCheck === "http"; onTapped: root.formCheck = "http" }
              SegBtn { label: "tcp"; active: root.formCheck === "tcp"; onTapped: root.formCheck = "tcp" }
            }
            Text {
              visible: root.formCheck === "http"
              text: "URL"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            TextField {
              id: urlField
              width: parent.width
              visible: root.formCheck === "http"
              text: root.formUrl
              placeholderText: "http://…"
              onTextChanged: root.formUrl = text
              onActiveFocusChanged: root.formFieldFocused = activeFocus || labelField.activeFocus || dnsField.activeFocus || ipField.activeFocus || portField.activeFocus
            }
            Text {
              visible: root.formCheck === "tcp"
              text: "Port"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            TextField {
              id: portField
              width: parent.width
              visible: root.formCheck === "tcp"
              text: root.formPort
              placeholderText: "443"
              onTextChanged: root.formPort = text
              onActiveFocusChanged: root.formFieldFocused = activeFocus || labelField.activeFocus || dnsField.activeFocus || ipField.activeFocus || urlField.activeFocus
            }
          }

          Row {
            spacing: Style.space(8)
            Rectangle {
              implicitWidth: saveLab.implicitWidth + Style.space(20)
              implicitHeight: Style.space(32)
              radius: Style.space(4)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
              Text {
                id: saveLab
                anchors.centerIn: parent
                text: "Save"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.saveForm() }
            }
            Rectangle {
              implicitWidth: cancelLab.implicitWidth + Style.space(20)
              implicitHeight: Style.space(32)
              radius: Style.space(4)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
              Text {
                id: cancelLab
                anchors.centerIn: parent
                text: "Cancel"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.view = "setup"; root.formConfirmDelete = false; root.formFieldFocused = false }
              }
            }
            Rectangle {
              visible: !root.formIsNew
              implicitWidth: delLab.implicitWidth + Style.space(20)
              implicitHeight: Style.space(32)
              radius: Style.space(4)
              color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, root.formConfirmDelete ? 0.35 : 0.12)
              Text {
                id: delLab
                anchors.centerIn: parent
                text: root.formConfirmDelete ? "Confirm delete" : "Delete"
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.deleteFormNode() }
            }
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Esc back"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
