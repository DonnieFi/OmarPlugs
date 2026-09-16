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
  readonly property color ink: Color.popups.text
  readonly property color inkDim: Util.alpha(ink, 0.66)
  readonly property color card: Util.alpha(ink, 0.05)
  readonly property color rule: Util.alpha(ink, 0.14)
  readonly property color muted: inkDim
  readonly property color dim: Util.alpha(ink, 0.72)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/homelab-mesh"
  readonly property int refreshIntervalSec: {
    var n = parseInt(String(setting("refreshIntervalSec", 15)), 10)
    if (!isFinite(n)) n = 15
    return Math.max(5, Math.min(120, n))
  }

  // glance | setup | form
  property string view: "glance"
  // map (default) | list within glance
  property string glanceTab: "map"
  property var mapEdges: []
  property var mapLayout: []
  property string mapSelectedId: ""
  property real edgePhase: 0
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
  property bool formNotify: true
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

  function glanceRowById(id) {
    var sid = String(id || "")
    var bands = [root.machines, root.lan, root.proxies]
    var b, i, row
    for (b = 0; b < bands.length; b++) {
      for (i = 0; i < bands[b].length; i++) {
        row = bands[b][i]
        if (String(row.id || "") === sid) return row
      }
    }
    return null
  }

  readonly property int mapLanCap: 12
  readonly property int mapCardH: Style.space(76)

  function rttHot(row) {
    if (!row || String(row.status) !== "up") return false
    var n = Number(row.rtt_ms)
    return isFinite(n) && n > 2
  }

  function edgePulseSec(rowA, rowB) {
    var ms = 0
    if (rowA && rowA.rtt_ms != null) ms = Math.max(ms, Number(rowA.rtt_ms))
    if (rowB && rowB.rtt_ms != null) ms = Math.max(ms, Number(rowB.rtt_ms))
    if (!isFinite(ms) || ms <= 0) return 2.5
    return Math.max(0.6, Math.min(3.5, ms / 40))
  }

  function recalcMapLayout() {
    if (!mapArea || mapArea.width <= 0) return
    var w = mapArea.width
    var layout = []
    function band(rows, subline, y, cap) {
      var n = cap > 0 ? Math.min(rows.length, cap) : rows.length
      if (n <= 0) return
      var gap = w / (n + 1)
      var cardW = Math.max(Style.space(72), Math.min(Style.space(108), gap - Style.space(6)))
      for (var i = 0; i < n; i++) {
        var row = rows[i]
        layout.push({
          id: String(row.id || ""),
          label: String(row.label || row.id || ""),
          subline: subline || String(row.check || "proxy"),
          status: String(row.status || "unknown"),
          rtt_ms: row.rtt_ms,
          x: gap * (i + 1) - cardW / 2,
          y: y,
          w: cardW,
          h: root.mapCardH
        })
      }
    }
    band(root.machines, "machine", Style.space(28), 0)
    band(root.lan, "host", Style.space(172), root.mapLanCap)
    band(root.proxies, "", Style.space(316), 0)
    root.mapLayout = layout
    if (edgeCanvas) edgeCanvas.requestPaint()
  }

  function moveMapSelection(dx, dy) {
    var cards = root.mapLayout
    if (cards.length === 0) return
    var cur = -1
    for (var i = 0; i < cards.length; i++) {
      if (cards[i].id === root.mapSelectedId) { cur = i; break }
    }
    if (cur < 0) {
      root.mapSelectedId = cards[0].id
      return
    }
    var next = cur
    if (dx !== 0) {
      next = Math.max(0, Math.min(cards.length - 1, cur + dx))
    } else if (dy !== 0) {
      var fromY = cards[cur].y
      var fromX = cards[cur].x + cards[cur].w / 2
      var bestDist = Infinity
      for (var j = 0; j < cards.length; j++) {
        var c = cards[j]
        if (dy > 0 ? c.y <= fromY : c.y >= fromY) continue
        var dist = Math.abs(c.y - fromY) * 10000 + Math.abs(c.x + c.w / 2 - fromX)
        if (dist < bestDist) { bestDist = dist; next = j }
      }
    }
    root.mapSelectedId = cards[next].id
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
    root.recalcMapLayout()
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

  function notifyEnabledForNodeId(sid) {
    var inv = root.invNodeById(sid)
    return !inv || inv.notify !== false
  }

  function invNodeById(sid) {
    var id = String(sid || "")
    var i
    for (i = 0; i < root.nodes.length; i++) {
      if (String(root.nodes[i].id || "") === id) return root.nodes[i]
    }
    return null
  }

  function mapCardTooltip(id, label, status, notifyOn) {
    var row = root.glanceRowById(id)
    var lines = [
      String(label || id),
      String(status || "unknown").toUpperCase() + " · " + root.rttText(row)
    ]
    var inv = root.invNodeById(id)
    if (inv) {
      var tgt = root.nodeTarget(inv)
      if (tgt) lines.push(tgt)
    }
    lines.push("Notify " + (notifyOn ? "on" : "off"))
    return lines.join("\n")
  }

  function listRowTooltip(row) {
    if (!row) return ""
    var id = String(row.id || "")
    var lines = [
      String(row.label || id),
      String(row.status || "unknown").toUpperCase() + " · " + root.rttText(row)
    ]
    var inv = root.invNodeById(id)
    if (inv) {
      var tgt = root.nodeTarget(inv)
      if (tgt) lines.push(tgt)
      lines.push("Notify " + (inv.notify === false ? "off" : "on"))
    }
    return lines.join("\n")
  }

  function toggleNotifyForNodeId(sid) {
    var id = String(sid || "")
    if (!id) return
    var next = []
    var i, n
    for (i = 0; i < root.nodes.length; i++) {
      n = JSON.parse(JSON.stringify(root.nodes[i]))
      if (String(n.id) === id) {
        if (n.notify === false) delete n.notify
        else n.notify = false
      }
      next.push(n)
    }
    root.mapSelectedId = id
    root.writeNodes(next)
  }

  readonly property string glanceStatusLine: {
    if (root.loading) return "PROBING"
    if (root.error) return "ERROR"
    var down = 0
    var bands = [root.machines, root.lan, root.proxies]
    var b, i
    for (b = 0; b < bands.length; b++) {
      for (i = 0; i < bands[b].length; i++) {
        if (String(bands[b][i].status) === "down") down++
      }
    }
    if (down > 0) return "LIVE · " + down + " DOWN"
    return "LIVE · ALL CLEAR"
  }

  readonly property color glanceStatusTint: {
    if (root.error) return root.urgent
    if (glanceStatusLine.indexOf("DOWN") >= 0) return root.urgent
    return root.ink
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
    root.formNotify = true
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
    root.formNotify = node.notify !== false
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
    root.mapEdges = data.edges instanceof Array ? data.edges : []
    root.inventoryLoading = false
    root.recalcMapLayout()
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
      if (!root.formNotify) node.notify = false
      return node
    }
    node.check = String(root.formCheck || "tcp")
    if (node.check === "http") {
      var url = String(root.formUrl || "").trim()
      if (!url) return null
      node.url = url
      if (!root.formNotify) node.notify = false
      return node
    }
    if (dns) node.dns = dns
    if (ip) node.ip = ip
    else node.ip = null
    var port = parseInt(String(root.formPort || ""), 10)
    if (!isFinite(port)) return null
    if (!dns && !ip) return null
    node.port = port
    if (!root.formNotify) node.notify = false
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
      root.glanceTab = "map"
      root.mapSelectedId = ""
      loadInventory()
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
      if (root.view === "form") root.view = "setup"
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
    property string hoverTip: ""

    width: ListView.view ? ListView.view.width : (parent ? parent.width : 0)
    height: Style.space(42)

    PanelToolTip {
      visible: rowMa.containsMouse && hoverTip !== ""
      text: hoverTip
      fontFamily: root.fontFamily
    }

    MouseArea {
      id: rowMa
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

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

  component MapCard: Rectangle {
    id: mapBox
    property string nodeId: ""
    property string label: ""
    property string subline: ""
    property string status: "unknown"
    property var rttRow: null
    property bool selected: false
    property bool notifyOn: true
    readonly property bool hot: root.rttHot(rttRow)
    signal activated()
    signal notifyClicked()

    width: Style.space(108)
    height: root.mapCardH
    radius: Style.space(14)
    color: {
      if (cardMa.containsMouse) return Qt.alpha(root.ink, 0.08)
      if (hot) return Qt.alpha(root.urgent, 0.07)
      return root.card
    }
    border.width: selected || status === "down" ? 2 : 1
    border.color: Qt.alpha(root.statusColor(status), selected ? 0.9 : (status === "unknown" ? 0.5 : 0.65))

    Rectangle {
      visible: !mapBox.notifyOn
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(8)
      width: notifyLab.implicitWidth + Style.space(14)
      height: Style.space(18)
      radius: Style.space(9)
      color: Qt.alpha(root.urgent, 0.14)
      border.width: 1
      border.color: Qt.alpha(root.urgent, 0.45)
      z: 2
      Text {
        id: notifyLab
        anchors.centerIn: parent
        text: "MUTED"
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: 8
        font.bold: true
        font.letterSpacing: 0.6
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: mapBox.notifyClicked()
      }
    }

    PanelToolTip {
      visible: cardMa.containsMouse
      text: root.mapCardTooltip(mapBox.nodeId, mapBox.label, mapBox.status, mapBox.notifyOn)
      fontFamily: root.fontFamily
    }

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(8)
      spacing: Style.space(4)

      Text {
        width: parent.width
        text: subline.toUpperCase()
        color: root.inkDim
        font.family: root.fontFamily
        font.pixelSize: 10
        font.letterSpacing: 1.2
        elide: Text.ElideRight
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(6)
        Text {
          text: root.statusGlyph(status)
          color: root.statusColor(status)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          Layout.preferredWidth: Style.space(12)
        }
        Text {
          text: label
          color: root.ink
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      Text {
        width: parent.width
        text: root.rttText(rttRow)
        color: hot ? root.urgent : (root.rttText(rttRow) === "—" ? root.inkDim : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: root.rule
      opacity: selected ? 0.5 : 0.25
    }

    MouseArea {
      id: cardMa
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: mapBox.activated()
    }
  }

  // Pulse Panel.qml Action — page/tab pills
  component TabAction: Rectangle {
    id: act
    property string text: ""
    property bool selected: false
    signal clicked()
    implicitWidth: caption.implicitWidth + Style.space(26)
    implicitHeight: Style.space(34)
    radius: Style.space(9)
    color: act.selected ? Qt.alpha(root.ink, Style.selectedFillAlpha)
                        : tabMa.containsMouse ? Style.hoverFill : Style.normalFill
    border.color: act.selected ? root.ink
                               : tabMa.containsMouse ? Style.hoverBorderColor : Style.normalBorderColor
    Behavior on color { ColorAnimation { duration: 120 } }
    Text {
      id: caption
      anchors.centerIn: parent
      text: act.text
      color: act.selected ? root.ink : root.inkDim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: act.selected
    }
    MouseArea {
      id: tabMa
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: act.clicked()
    }
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
    tooltipText: "Lanarchy"
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
    padding: root.view === "glance" && root.glanceTab === "map" ? Style.space(12) : Style.space(8)
    borderSpec: root.view === "glance" && root.glanceTab === "map"
        ? Border.flat(Color.accent, 2) : Border.none()
    contentWidth: panel.fittedContentWidth(root.view === "glance" && root.glanceTab === "map"
        ? Style.space(1120) : Style.space(390))
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
        var k = String(text || "").toLowerCase()
        if (k === "r") root.refresh()
        if (k === "m") root.glanceTab = root.glanceTab === "map" ? "list" : "map"
      }
      onMoveRequested: function(dx, dy) {
        if (root.view === "glance" && root.glanceTab === "map") root.moveMapSelection(dx, dy)
      }
      onActivateRequested: {
        if (root.view === "glance" && root.glanceTab === "map") root.toggleNotifyForNodeId(root.mapSelectedId)
      }

      Item {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        implicitHeight: glanceBody.implicitHeight

        Rectangle {
          anchors.fill: parent
          anchors.margins: -Style.space(10)
          radius: Style.space(14)
          color: Color.popups.background
          z: -1
        }

        Column {
          id: glanceBody
          width: parent.width
          spacing: Style.space(10)

        // Header — Pulse heading + Omastorm status strip
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.view === "glance"
          Row {
            width: parent.width
            spacing: Style.space(10)
            Column {
              width: Math.max(Style.space(120), parent.width - Style.space(200))
              spacing: Style.space(3)
              Text {
                text: "LANARCHY"
                color: root.ink
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                font.letterSpacing: 2.5
              }
              Text {
                width: parent.width
                text: root.glanceTab === "map" ? "Homelab topology map" : "Machines, LAN, and proxies"
                color: root.inkDim
                font.family: root.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
              }
            }
            Rectangle {
              id: statusPill
              height: Style.space(32)
              width: statusRow.implicitWidth + Style.space(20)
              radius: Style.space(16)
              color: Qt.alpha(root.glanceStatusTint, 0.14)
              border.color: Qt.alpha(root.glanceStatusTint, 0.5)
              border.width: 1
              Row {
                id: statusRow
                anchors.centerIn: parent
                spacing: Style.space(7)
                Rectangle {
                  width: 6
                  height: 6
                  radius: 3
                  color: root.glanceStatusTint
                  anchors.verticalCenter: parent.verticalCenter
                  SequentialAnimation on opacity {
                    running: root.opened && !root.loading && !root.error
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 900 }
                    NumberAnimation { to: 1; duration: 900 }
                  }
                }
                Text {
                  text: root.glanceStatusLine + (root.asOfShort() ? " · " + root.asOfShort() : "")
                  color: root.ink
                  font.family: root.fontFamily
                  font.pixelSize: 9
                  font.bold: true
                }
              }
            }
          }
          Row {
            width: parent.width
            spacing: Style.space(8)
            TabAction {
              text: "Map"
              selected: root.glanceTab === "map"
              onClicked: root.glanceTab = "map"
            }
            TabAction {
              text: "List"
              selected: root.glanceTab === "list"
              onClicked: root.glanceTab = "list"
            }
            Item { width: Style.space(8); height: 1 }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "⚙ Setup"
              color: root.inkDim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(8)
                cursorShape: Qt.PointingHandCursor
                onClicked: root.goSetup()
              }
            }
          }
        }

        Item {
          width: parent.width
          height: Style.space(28)
          visible: root.view !== "glance"
          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.view === "setup" ? "Setup" : (root.formIsNew ? "Add node" : "Edit node")
            color: root.ink
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
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

          Rectangle {
            id: mapArea
            width: parent.width
            height: Style.space(420)
            visible: root.glanceTab === "map"
            radius: Style.space(14)
            color: Color.popups.background
            border.width: 1
            border.color: Qt.alpha(root.ink, 0.17)
            onWidthChanged: root.recalcMapLayout()

            Timer {
              interval: 50
              running: root.opened && root.view === "glance" && root.glanceTab === "map"
              repeat: true
              onTriggered: {
                root.edgePhase = (root.edgePhase + 0.05) % 1000
                edgeCanvas.requestPaint()
              }
            }

            Canvas {
              id: edgeCanvas
              anchors.fill: parent
              onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var pos = {}
                var i, box
                for (i = 0; i < root.mapLayout.length; i++) {
                  box = root.mapLayout[i]
                  pos[box.id] = {
                    x: box.x + box.w / 2,
                    y: box.y + box.h / 2
                  }
                }
                var calm = Qt.alpha(root.ink, 0.35)
                var hot = Qt.alpha(root.urgent, 0.6)
                for (i = 0; i < root.mapEdges.length; i++) {
                  var e = root.mapEdges[i]
                  var a = pos[String(e.from || "")]
                  var b = pos[String(e.to || "")]
                  if (!a || !b) continue
                  var rowA = root.glanceRowById(e.from)
                  var rowB = root.glanceRowById(e.to)
                  var period = root.edgePulseSec(rowA, rowB)
                  ctx.strokeStyle = (root.rttHot(rowA) || root.rttHot(rowB)) ? hot : calm
                  ctx.lineWidth = 1.5
                  ctx.setLineDash([6, 10])
                  ctx.lineDashOffset = -root.edgePhase * (40 / period)
                  ctx.beginPath()
                  var mx = (a.x + b.x) / 2
                  ctx.moveTo(a.x, a.y)
                  ctx.bezierCurveTo(mx, a.y, mx, b.y, b.x, b.y)
                  ctx.stroke()
                }
              }
            }

            Repeater {
              model: root.mapLayout
              delegate: MapCard {
                required property var modelData
                x: modelData.x
                y: modelData.y
                width: modelData.w
                nodeId: String(modelData.id || "")
                label: String(modelData.label || "")
                subline: String(modelData.subline || "")
                status: String(modelData.status || "unknown")
                rttRow: modelData
                selected: root.mapSelectedId === String(modelData.id || "")
                notifyOn: root.notifyEnabledForNodeId(nodeId)
                onActivated: root.mapSelectedId = nodeId
                onNotifyClicked: root.toggleNotifyForNodeId(nodeId)
              }
            }

            Text {
              visible: root.lan.length > root.mapLanCap
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              y: Style.space(172) + root.mapCardH + Style.space(4)
              text: "+" + (root.lan.length - root.mapLanCap) + " more LAN hosts in List"
              color: root.inkDim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Rectangle {
            width: parent.width
            visible: root.glanceTab === "map"
            radius: Style.space(4)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            implicitHeight: mapDetail.implicitHeight + Style.space(16)
            Column {
              id: mapDetail
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(6)
              Text {
                width: parent.width
                color: root.mapSelectedId ? root.foreground : root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.Wrap
                text: {
                  if (!root.mapSelectedId) return "Click or arrow to a node"
                  var row = root.glanceRowById(root.mapSelectedId)
                  return String(row ? row.label : root.mapSelectedId) + " · "
                    + String(row ? row.status : "unknown") + " · "
                    + root.rttText(row)
                }
              }
              Row {
                visible: root.mapSelectedId !== ""
                spacing: Style.space(8)
                SegBtn {
                  label: root.notifyEnabledForNodeId(root.mapSelectedId) ? "Notify on" : "Notify off"
                  active: root.notifyEnabledForNodeId(root.mapSelectedId)
                  onTapped: root.toggleNotifyForNodeId(root.mapSelectedId)
                }
                SegBtn {
                  label: "Edit in Setup"
                  active: false
                  onTapped: {
                    var node = root.invNodeById(root.mapSelectedId)
                    root.goSetup()
                    if (node) root.goFormEdit(node)
                  }
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.glanceTab === "list"

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
                  hoverTip: root.listRowTooltip(modelData)
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
                hoverTip: root.listRowTooltip(modelData)
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
                  hoverTip: root.listRowTooltip(modelData)
                }
              }
            }
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.glanceTab === "map"
                ? "arrows select · Enter notify · m list · r refresh · Esc back"
                : "m map · r refresh · Esc back"
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

          Row {
            spacing: Style.space(6)
            SegBtn {
              label: root.formNotify ? "Notify on" : "Notify off"
              active: root.formNotify
              onTapped: root.formNotify = !root.formNotify
            }
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
}
