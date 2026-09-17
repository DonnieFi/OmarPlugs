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
  // list is the dash; map is the letterbox
  property string glanceTab: "list"
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
  property var groups: []
  property var quietLan: []
  property var quietProxies: []
  property var lanMeta: ({})
  property var unifi: ({})
  property var discover: []
  property bool showLan: false
  property bool showProxies: false
  property string actionStatus: ""

  // setup / form state
  property var nodes: []
  property bool inventoryLoading: false
  property bool inventoryReady: false
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
    if (s === "up") return "#6fbf73"
    if (s === "degraded") return "#d4a017"
    if (s === "down") return root.urgent
    return root.muted
  }

  function fmtRate(bps) {
    var v = Number(bps)
    if (!isFinite(v) || v < 0) return ""
    if (v < 1000) return Math.round(v) + "B"
    if (v < 1000000) return Math.round(v / 1000) + "k"
    return (v / 1000000).toFixed(1) + "M"
  }

  function machineMetric(row) {
    if (!row) return "—"
    var bits = []
    var link = row.link
    if (link && link.speed_mbit) {
      var mb = Number(link.speed_mbit)
      if (link.kind === "wifi") bits.push(Math.round(mb) + "M wifi")
      else if (mb >= 1000) bits.push((mb / 1000) + "G")
      else bits.push(Math.round(mb) + "M")
      if (link.grade === "degraded") bits.push("slow")
    }
    if (row.rates && row.rates.rx_bps != null) {
      var r = root.fmtRate(row.rates.rx_bps)
      if (r) bits.push("↓" + r)
    }
    if (row.uptime_s != null) {
      var up = root.uptimeText(row.uptime_s)
      if (up) bits.push(up)
    }
    bits.push(root.rttText(row))
    return bits.join("  ")
  }

  function uptimeText(secs) {
    var n = Number(secs)
    if (!isFinite(n) || n <= 0) return ""
    if (n < 3600) return Math.round(n / 60) + "m up"
    if (n < 86400) return Math.round(n / 3600) + "h up"
    return (Math.round(n / 86400 * 10) / 10) + "d up"
  }

  function displayStatus(row) {
    if (!row) return "unknown"
    if (String(row.status) === "up" && row.link && row.link.grade === "degraded")
      return "degraded"
    return String(row.status || "unknown")
  }

  function sshHostFor(row) {
    if (row && row.host) return String(row.host)
    var inv = row ? root.invNodeById(row.id) : null
    if (inv && inv.dns) return String(inv.dns)
    return ""
  }

  function openSsh(row) {
    var host = root.sshHostFor(row)
    if (!host) return
    Quickshell.execDetached(["uwsm-app", "--", "xdg-terminal-exec", "--app-id=org.omarchy.terminal", "-e", "ssh", host])
  }

  function wakeNode(row) {
    if (!row) return
    var target = String(row.mac || row.id || "")
    if (!target) return
    root.actionStatus = "Waking " + String(row.label || row.id)
    actionProc.command = ["python3", root.pluginDir + "/probe.py", "wol", target]
    actionProc.running = true
  }

  function serviceMetric(row) {
    if (!row) return "—"
    var frac = String(row.up || 0) + "/" + String(row.total || 0)
    var ms = root.rttText(row)
    return ms === "—" ? frac : frac + "  " + ms
  }

  function serviceLights(row) {
    if (!row || !row.members) return []
    var out = []
    for (var i = 0; i < row.members.length; i++) out.push(String(row.members[i].status || "unknown"))
    return out
  }

  function hubGroup() {
    var i
    for (i = 0; i < root.groups.length; i++) {
      if (String(root.groups[i].key || "") === "caddy") return root.groups[i]
    }
    return root.groups.length ? root.groups[0] : null
  }

  function lanClusterRow() {
    var rows = root.quietLan
    var up = 0
    var down = 0
    var lights = []
    var i, s
    for (i = 0; i < rows.length; i++) {
      s = String(rows[i].status || "unknown")
      if (i < 8) lights.push(s)
      if (s === "up") up++
      else if (s === "down") down++
    }
    var status = "unknown"
    if (down && !up && down === rows.length)
      status = "down"
    else if (down || (up && up < rows.length))
      status = "degraded"
    else if (up)
      status = "up"
    return {
      id: "__lan__",
      label: "LAN",
      kind: "lan",
      status: status,
      up: up,
      total: rows.length,
      lights: lights,
      members: rows,
      metric: root.lanClusterMetric(up, rows.length)
    }
  }

  function lanClusterMetric(up, total) {
    var bits = [(up + "/" + total) + (total ? " leftover" : "")]
    var meta = root.lanMeta || {}
    if (meta.dns_ms != null) bits.push("dns " + Math.round(Number(meta.dns_ms)) + "ms")
    if (meta.neighbors != null) bits.push(meta.neighbors + " neigh")
    if (root.discover.length) bits.push(root.discover.length + " new")
    var u = root.unifi || {}
    if (u.model) bits.push(u.model)
    var nCli = (u.clients instanceof Array) ? u.clients.length : 0
    if (nCli) bits.push(nCli + " unifi")
    return bits.join(" · ")
  }

  function unifiMetric() {
    var u = root.unifi || {}
    var bits = []
    if (u.model) bits.push(String(u.model))
    var nDev = (u.devices instanceof Array) ? u.devices.length : 0
    if (nDev) bits.push(nDev + (nDev === 1 ? " device" : " devices"))
    var nCli = (u.clients instanceof Array) ? u.clients.length : 0
    if (nCli) bits.push(nCli + (nCli === 1 ? " client" : " clients"))
    var nNew = (u.discover instanceof Array) ? u.discover.length : 0
    if (nNew) bits.push(nNew + " new")
    if (u.auth === "none" && u.ok) bits.push("no key")
    if (u.error && u.auth !== "none") bits.push(String(u.error))
    return bits.join(" · ") || "controller"
  }

  function unifiLights() {
    var u = root.unifi || {}
    var devs = u.devices instanceof Array ? u.devices : []
    if (!devs.length) return [u.ok ? "up" : "down"]
    var out = []
    var i
    for (i = 0; i < devs.length; i++) {
      var s = String(devs[i].state || devs[i].status || "")
      out.push(s === "up" || s === "1" ? "up" : "down")
    }
    return out
  }

  function unifiVisible() {
    var u = root.unifi || {}
    if (u.ok) return true
    if (u.devices instanceof Array && u.devices.length) return true
    if (u.url) return true
    return false
  }

  function rebuildMapEdges() {
    var hubRow = root.hubGroup()
    var hub = hubRow ? String(hubRow.id) : (root.machines.length ? String(root.machines[0].id || "") : "")
    var edges = []
    var i
    for (i = 0; i < root.machines.length; i++)
      edges.push({ from: String(root.machines[i].id || ""), to: hub, kind: "hub" })
    for (i = 0; i < root.groups.length; i++) {
      if (String(root.groups[i].id) === hub) continue
      edges.push({ from: hub, to: String(root.groups[i].id), kind: "service" })
    }
    if (root.quietLan.length)
      edges.push({ from: hub, to: "__lan__", kind: "lan" })
    root.mapEdges = edges
  }

  function glanceRowById(id) {
    var sid = String(id || "")
    if (sid === "__lan__") return root.lanClusterRow()
    var bands = [root.machines, root.groups, root.lan, root.proxies, root.quietLan, root.quietProxies]
    var b, i, row
    for (b = 0; b < bands.length; b++) {
      for (i = 0; i < bands[b].length; i++) {
        row = bands[b][i]
        if (String(row.id || "") === sid) return row
      }
    }
    return null
  }

  function sparklineIdFor(row) {
    if (!row) return ""
    if (String(row.id || "") === "__lan__") return ""
    if (row.members && row.members.length) {
      var m = row.members[0]
      return String((m && m.id) || "")
    }
    return String(row.id || "")
  }

  readonly property int mapLanCap: 12
  readonly property int mapCardH: Style.space(94)

  function rttHot(row) {
    if (!row || String(row.status) !== "up") return false
    var n = Number(row.rtt_ms)
    return isFinite(n) && n > 2
  }

  function edgePulseSec(rowA, rowB) {
    function rx(row) {
      if (!row || !row.rates || row.rates.rx_bps == null) return 0
      var n = Number(row.rates.rx_bps)
      return isFinite(n) ? n : 0
    }
    var bps = Math.max(rx(rowA), rx(rowB))
    if (bps > 500) return Math.max(0.4, Math.min(2.8, 120000 / bps))
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
    var cardW = Style.space(108)
    var cardH = root.mapCardH
    function place(row, subline, x, y, wCard, hCard, kind, metric, lights) {
      layout.push({
        id: String(row.id || ""),
        label: String(row.label || row.id || ""),
        subline: subline,
        status: root.displayStatus(row),
        rtt_ms: row.rtt_ms,
        x: x,
        y: y,
        w: wCard,
        h: hCard,
        kind: kind || subline,
        metric: metric || "",
        lights: lights || [],
        sparklineId: root.sparklineIdFor(row)
      })
    }
    function rowBand(rows, subline, y, kind, metricFn, lightsFn) {
      var n = rows.length
      if (n <= 0) return
      var gap = w / (n + 1)
      var cw = Math.max(Style.space(96), Math.min(cardW, gap - Style.space(8)))
      var i, row
      for (i = 0; i < n; i++) {
        row = rows[i]
        place(row, subline, gap * (i + 1) - cw / 2, y, cw, cardH, kind,
              metricFn ? metricFn(row) : root.rttText(row),
              lightsFn ? lightsFn(row) : [])
      }
    }
    rowBand(root.machines, "machine", Style.space(16), "machine", root.machineMetric, null)
    var hub = root.hubGroup()
    var hubW = Style.space(128)
    var hubH = Style.space(100)
    if (hub) {
      place(hub, "gateway", (w - hubW) / 2, Style.space(120), hubW, hubH, "hub",
            root.serviceMetric(hub), root.serviceLights(hub))
    }
    var svcs = []
    var i
    for (i = 0; i < root.groups.length; i++) {
      if (hub && String(root.groups[i].id) === String(hub.id)) continue
      svcs.push(root.groups[i])
    }
    rowBand(svcs, "service", Style.space(232), "service", root.serviceMetric, root.serviceLights)
    if (root.quietLan.length) {
      var cluster = root.lanClusterRow()
      place(cluster, "leftover", (w - Style.space(300)) / 2, Style.space(338),
            Style.space(300), Style.space(78), "lan", cluster.metric, cluster.lights)
    }
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
    root.groups = data.groups instanceof Array ? data.groups : []
    root.quietLan = data.quiet_lan instanceof Array ? data.quiet_lan : []
    root.quietProxies = data.quiet_proxies instanceof Array ? data.quiet_proxies : []
    root.lanMeta = data.lan_meta && typeof data.lan_meta === "object" ? data.lan_meta : {}
    root.unifi = data.unifi && typeof data.unifi === "object" ? data.unifi : {}
    root.discover = data.discover instanceof Array ? data.discover : []
    root.error = ""
    root.loading = false
    root.rebuildMapEdges()
    root.recalcMapLayout()
  }

  function ensureDaemon() {
    if (daemonProc.running) return
    daemonProc.command = ["python3", root.pluginDir + "/daemon.py"]
    daemonProc.running = true
  }

  function refresh() {
    root.loading = true
    root.ensureDaemon()
    snapshotView.reload()
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

  function groupMemberIds(sid) {
    var row = root.glanceRowById(sid)
    if (row && row.member_ids) return row.member_ids
    if (row && row.members && row.id && String(row.id).indexOf("svc-") === 0) {
      var ids = []
      var i
      for (i = 0; i < row.members.length; i++) ids.push(String(row.members[i].id || ""))
      return ids
    }
    return [String(sid || "")]
  }

  function notifyEnabledForNodeId(sid) {
    if (String(sid) === "__lan__") return true
    var ids = root.groupMemberIds(sid)
    var i, inv
    for (i = 0; i < ids.length; i++) {
      inv = root.invNodeById(ids[i])
      if (inv && inv.notify === false) return false
    }
    return true
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
    if (String(id) === "__lan__") {
      var cluster = root.lanClusterRow()
      var lines = [cluster.metric, "Open List with LAN on for every leftover host"]
      var unknown = (root.lanMeta && root.lanMeta.unknown_hosts) ? root.lanMeta.unknown_hosts : []
      var u
      for (u = 0; u < unknown.length && u < 6; u++)
        lines.push("new " + String(unknown[u].ip || "") + " " + String(unknown[u].mac || ""))
      return lines.join("\n")
    }
    var row = root.glanceRowById(id)
    var tip = root.listRowTooltip(row)
    if (tip) return tip
    return String(label || id) + "\n" + String(status || "unknown").toUpperCase() + "\nNotify " + (notifyOn ? "on" : "off")
  }

  function listRowTooltip(row) {
    if (!row) return ""
    var id = String(row.id || "")
    var lines = [
      String(row.label || id),
      String(row.status || "unknown").toUpperCase() + " · " + root.rttText(row)
    ]
    if (row.members) {
      var i, m, bit
      for (i = 0; i < row.members.length; i++) {
        m = row.members[i]
        bit = String(m.role || m.id) + " " + String(m.status || "")
        if (m.ttfb_ms != null) bit += " " + Math.round(Number(m.ttfb_ms)) + "ms ttfb"
        lines.push(bit)
      }
    }
    if (row.link && row.link.speed_mbit)
      lines.push(String(row.link.iface || "link") + " " + String(row.link.speed_mbit) + " Mbit"
        + (row.link.grade === "degraded" ? " (slow port)" : ""))
    if (row.rates && row.rates.rx_bps != null)
      lines.push("↓" + root.fmtRate(row.rates.rx_bps) + "  ↑" + root.fmtRate(row.rates.tx_bps))
    if (row.uptime_s != null) {
      var up = root.uptimeText(row.uptime_s)
      if (up) lines.push(up)
    }
    if (row.mac) lines.push("mac " + String(row.mac))
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
    if (!id || id === "__lan__") return
    var targets = {}
    var ids = root.groupMemberIds(id)
    var i
    for (i = 0; i < ids.length; i++) targets[String(ids[i])] = true
    var turnOn = !root.notifyEnabledForNodeId(id)
    var next = []
    var n
    for (i = 0; i < root.nodes.length; i++) {
      n = JSON.parse(JSON.stringify(root.nodes[i]))
      if (targets[String(n.id)]) {
        if (turnOn) delete n.notify
        else n.notify = false
      }
      next.push(n)
    }
    root.mapSelectedId = id
    if (!root.writeNodes(next)) {
      if (root.view === "glance")
        root.actionStatus = root.inventoryError || "Save refused"
    }
  }

  function asOfAgeSec() {
    if (!root.asOf) return -1
    var t = Date.parse(String(root.asOf))
    if (!isFinite(t)) return -1
    return Math.max(0, (Date.now() - t) / 1000)
  }

  function snapshotStale() {
    var age = root.asOfAgeSec()
    if (age < 0) return true
    return age > (root.refreshIntervalSec * 2 + 5)
  }

  readonly property string glanceStatusLine: {
    if (root.loading) return "PROBING"
    if (root.error) return "ERROR"
    if (!root.asOf) return "NO DATA"
    if (root.snapshotStale()) return "STALE"
    var total = root.machines.length + root.groups.length
    if (root.showLan) total += root.quietLan.length
    if (root.showProxies) total += root.quietProxies.length
    if (total === 0) return "NO DATA"
    var down = 0
    var bands = [root.machines, root.groups]
    if (root.showLan) bands.push(root.quietLan)
    if (root.showProxies) bands.push(root.quietProxies)
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
    if (glanceStatusLine.indexOf("DOWN") >= 0 || glanceStatusLine === "STALE" || glanceStatusLine === "ERROR")
      return root.urgent
    if (glanceStatusLine === "PROBING" || glanceStatusLine === "NO DATA") return root.inkDim
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
    root.inventoryReady = false
    if (invDumpProc.running) invDumpProc.running = false
    invDumpProc.command = ["python3", root.pluginDir + "/inventory_cli.py", "dump"]
    invDumpProc.running = true
  }

  function applyInventoryDump(text) {
    var data = {}
    try { data = JSON.parse(text || "{}") || {} } catch (e) {
      root.inventoryError = "Bad inventory JSON"
      root.inventoryLoading = false
      root.inventoryReady = false
      return
    }
    if (data.error) {
      root.inventoryError = String(data.error)
      root.inventoryLoading = false
      root.inventoryReady = false
      return
    }
    if (!(data.nodes instanceof Array)) {
      root.inventoryError = "Inventory dump missing nodes"
      root.inventoryLoading = false
      root.inventoryReady = false
      return
    }
    root.nodes = data.nodes
    root.mapEdges = data.edges instanceof Array ? data.edges : []
    if (!root.asOf) {
      var seeded = []
      var i, n
      for (i = 0; i < root.nodes.length; i++) {
        n = root.nodes[i]
        if (String(n.type || "") === "machine")
          seeded.push({ id: String(n.id || ""), label: String(n.label || n.id || ""), status: "unknown" })
      }
      if (seeded.length) root.machines = seeded
      if (data.groups instanceof Array) root.groups = data.groups
    } else if (root.groups.length === 0 && data.groups instanceof Array) {
      root.groups = data.groups
    }
    root.inventoryLoading = false
    root.inventoryReady = true
    root.rebuildMapEdges()
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
    var node
    if (root.formIsNew) {
      node = {}
    } else {
      var existing = root.invNodeById(root.formId)
      if (!existing) return null
      node = JSON.parse(JSON.stringify(existing))
    }
    node.id = root.formIsNew ? root.slugify(label) : String(root.formId || root.slugify(label))
    node.type = String(root.formType || "machine")
    node.label = label
    var dns = String(root.formDns || "").trim()
    var ip = String(root.formIp || "").trim()
    if (node.type === "machine" || node.type === "host") {
      delete node.check
      delete node.url
      delete node.port
      if (dns) node.dns = dns
      else delete node.dns
      node.ip = ip ? ip : null
      if (!dns && !ip) return null
      if (root.formNotify) delete node.notify
      else node.notify = false
      return node
    }
    node.check = String(root.formCheck || "tcp")
    if (node.check === "http") {
      var url = String(root.formUrl || "").trim()
      if (!url) return null
      node.url = url
      delete node.dns
      delete node.ip
      delete node.port
      if (root.formNotify) delete node.notify
      else node.notify = false
      return node
    }
    if (dns) node.dns = dns
    else delete node.dns
    if (ip) node.ip = ip
    else node.ip = null
    delete node.url
    var port = parseInt(String(root.formPort || ""), 10)
    if (!isFinite(port)) return null
    if (!dns && !ip) return null
    node.port = port
    if (root.formNotify) delete node.notify
    else node.notify = false
    return node
  }

  function saveForm() {
    var node = root.buildFormNode()
    if (!node) {
      root.inventoryError = root.formIsNew || root.invNodeById(root.formId)
          ? "Fill required fields"
          : "Node missing from inventory"
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

  function discoveredNode(c) {
    if (!c) return null
    var label = String(c.label || c.host || c.ip || "").trim()
    if (!label) return null
    var node = { type: String(c.type || "") === "machine" ? "machine" : "host", label: label, ip: c.ip ? String(c.ip) : null }
    if (c.host) node.dns = String(c.host) + ".local"
    if (!node.dns && !node.ip) return null
    var id = root.slugify(label)
    if (root.invNodeById(id)) id = id + "-" + String(c.ip || c.mac || "").split(/[.:]/).pop()
    node.id = id
    return node
  }

  function addDiscovered(c) {
    var node = root.discoveredNode(c)
    if (!node) {
      root.inventoryError = "Nothing to add"
      return
    }
    var next = root.nodes.slice()
    next.push(node)
    root.writeNodes(next)
    // Discover list refreshes from the next snapshot merge (known hosts drop out).
  }

  function writeNodes(nextNodes) {
    if (!root.inventoryReady || root.inventoryLoading) {
      root.inventoryError = "Inventory not loaded"
      return false
    }
    if (!(nextNodes instanceof Array) || nextNodes.length === 0) {
      root.inventoryError = "Refusing empty inventory write"
      return false
    }
    root.nodes = nextNodes
    root.inventoryError = ""
    var payload = JSON.stringify({ schemaVersion: 2, nodes: nextNodes })
    invWriteProc.command = [
      "bash", "-c",
      "f=$(mktemp /tmp/homelab-mesh-inv.XXXXXX.json) && printf '%s' '" + payload.replace(/'/g, "'\\''") + "' > \"$f\" && python3 \"" + root.pluginDir + "/inventory_cli.py\" write \"$f\"; ec=$?; rm -f \"$f\"; exit $ec"
    ]
    invWriteProc.running = true
    return true
  }

  onOpenedChanged: {
    if (opened) {
      root.view = "glance"
      root.mapSelectedId = ""
      root.loading = true
      root.ensureDaemon()
      loadInventory()
      refresh()
    } else {
      root.view = "glance"
      root.formFieldFocused = false
    }
  }

  FileView {
    id: snapshotView
    path: root.pluginDir + "/snapshot.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      if (!root.opened) return
      root.applyPayload(text())
    }
  }

  Process {
    id: daemonProc
    stdout: StdioCollector { waitForEnd: false }
    stderr: StdioCollector { waitForEnd: false }
    onExited: function(exitCode) {
      if (!root.opened) return
      restartDaemon.restart()
    }
  }

  Timer {
    id: restartDaemon
    interval: 750
    repeat: false
    onTriggered: {
      if (!root.opened) return
      root.ensureDaemon()
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = {}
        try { data = JSON.parse(text || "{}") || {} } catch (e) { data = {} }
        if (data.ok) root.actionStatus = "Magic packet sent" + (data.mac ? " · " + data.mac : "")
        else if (data.error) root.actionStatus = String(data.error)
        else if (String(text || "").length) root.actionStatus = String(text).trim()
      }
    }
    stderr: StdioCollector { waitForEnd: true }
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
    interval: 2000
    running: root.opened && root.view === "glance"
    repeat: true
    onTriggered: if (root.opened) snapshotView.reload()
  }

  // Compact dash row: colour light + label + optional member lights + metric.
  component MeshRow: Item {
    property string label: ""
    property string status: "unknown"
    property string metric: ""
    property bool showMetric: true
    property var lights: []
    property string hoverTip: ""
    property string nodeId: ""

    width: ListView.view ? ListView.view.width : (parent ? parent.width : 0)
    height: Style.space(22)

    PanelToolTip {
      visible: rowMa.containsMouse && hoverTip !== "" && rowSpark.hoverIndex < 0
      text: hoverTip
      fontFamily: root.fontFamily
    }

    MouseArea {
      id: rowMa
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton

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
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        Layout.fillWidth: true
      }
      Sparkline {
        id: rowSpark
        visible: nodeId !== ""
        Layout.preferredWidth: 56
        Layout.preferredHeight: 14
        Layout.alignment: Qt.AlignVCenter
        nodeId: nodeId
        pluginDir: root.pluginDir
        live: root.opened && root.view === "glance" && root.glanceTab === "list" && nodeId !== ""
        stroke: root.ink
        rateStroke: Color.accent
        muted: root.inkDim
        fontFamily: root.fontFamily
      }
      Row {
        spacing: 3
        visible: lights && lights.length > 1
        Repeater {
          model: lights
          Rectangle {
            required property var modelData
            width: 6
            height: 6
            radius: 3
            anchors.verticalCenter: parent.verticalCenter
            color: root.statusColor(String(modelData || "unknown"))
          }
        }
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
    }
  }

  component SetupRow: Item {
    property var node: ({})
    property string trailing: ""
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
      Text {
        visible: trailing !== ""
        text: trailing
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
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
    property string kind: ""
    property string metric: ""
    property var lights: []
    property var rttRow: null
    property string sparklineId: ""
    property bool selected: false
    property bool notifyOn: true
    readonly property bool isLan: nodeId === "__lan__"
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
    border.width: selected || status === "down" || kind === "hub" ? 2 : 1
    border.color: kind === "hub" && status !== "down"
        ? Qt.alpha(Color.accent, selected ? 0.9 : 0.55)
        : Qt.alpha(root.statusColor(status), selected ? 0.9 : (status === "unknown" ? 0.5 : 0.65))

    Rectangle {
      visible: !mapBox.isLan
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(8)
      width: notifyLab.implicitWidth + Style.space(14)
      height: Style.space(18)
      radius: Style.space(9)
      color: mapBox.notifyOn ? Qt.alpha(root.ink, 0.08) : Qt.alpha(root.urgent, 0.14)
      border.width: 1
      border.color: mapBox.notifyOn ? Qt.alpha(root.ink, 0.22) : Qt.alpha(root.urgent, 0.45)
      z: 2
      Text {
        id: notifyLab
        anchors.centerIn: parent
        text: mapBox.notifyOn ? "ALERT" : "MUTE"
        color: mapBox.notifyOn ? root.inkDim : root.urgent
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
      visible: cardMa.containsMouse && cardSpark.hoverIndex < 0
      text: root.mapCardTooltip(mapBox.nodeId, mapBox.label, mapBox.status, mapBox.notifyOn)
      fontFamily: root.fontFamily
    }

    MouseArea {
      id: cardMa
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: mapBox.activated()

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(8)
      spacing: Style.space(3)

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
        text: mapBox.metric !== "" ? mapBox.metric : root.rttText(rttRow)
        color: hot ? root.urgent : ((mapBox.metric === "—" || mapBox.metric === "") ? root.inkDim : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Row {
        spacing: 4
        visible: lights && lights.length > 0
        Repeater {
          model: lights
          Rectangle {
            required property var modelData
            width: 7
            height: 7
            radius: 4
            color: root.statusColor(String(modelData || "unknown"))
          }
        }
      }

      Sparkline {
        id: cardSpark
        width: parent.width
        height: Style.space(16)
        nodeId: mapBox.sparklineId
        pluginDir: root.pluginDir
        live: root.opened && root.view === "glance" && root.glanceTab === "map" && mapBox.sparklineId !== ""
        stroke: root.ink
        rateStroke: Color.accent
        muted: root.inkDim
        fontFamily: root.fontFamily
      }
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

  readonly property int glanceDownCount: {
    var n = 0
    var i
    for (i = 0; i < root.machines.length; i++)
      if (String(root.machines[i].status) === "down") n++
    for (i = 0; i < root.groups.length; i++)
      if (String(root.groups[i].status) === "down") n++
    return n
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    tooltipText: "Lanarchy"
    active: root.opened
    iconComponent: Component {
      Item {
        LanarchyIcon {
          anchors.centerIn: parent
          iconSize: Style.space(14)
          color: button.foreground
          alert: root.urgent
          alarmed: root.glanceDownCount > 0
          active: root.opened || root.glanceDownCount > 0
        }
      }
    }
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
        ? Style.space(1120) : Style.space(560))
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
        if (k === "m" || k === "l") root.glanceTab = root.glanceTab === "map" ? "list" : "map"
        if (k === "n") { root.showLan = !root.showLan; root.recalcMapLayout() }
        if (k === "p") root.showProxies = !root.showProxies
        if (k === "s") root.goSetup()
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
              Row {
                spacing: Style.space(8)
                LanarchyIcon {
                  iconSize: Style.space(22)
                  color: root.ink
                  alert: root.urgent
                  alarmed: root.glanceDownCount > 0
                  active: true
                }
                Text {
                  text: "LANARCHY"
                  color: root.ink
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  font.letterSpacing: 2.5
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              Text {
                width: parent.width
                text: root.glanceTab === "map" ? "Machines → Caddy → services · leftover LAN clustered" : "Dash · colour lights · toggle the noise"
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
            SegBtn {
              label: "LAN" + (root.quietLan.length ? " " + root.quietLan.length : "")
              active: root.showLan
              onTapped: {
                root.showLan = !root.showLan
                root.recalcMapLayout()
              }
            }
            SegBtn {
              label: "PROXIES" + (root.quietProxies.length ? " " + root.quietProxies.length : "")
              active: root.showProxies
              onTapped: root.showProxies = !root.showProxies
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
                height: modelData.h
                nodeId: String(modelData.id || "")
                label: String(modelData.label || "")
                subline: String(modelData.subline || "")
                status: String(modelData.status || "unknown")
                kind: String(modelData.kind || "")
                metric: String(modelData.metric || "")
                lights: modelData.lights || []
                rttRow: modelData
                sparklineId: String(modelData.sparklineId || "")
                selected: root.mapSelectedId === String(modelData.id || "")
                notifyOn: root.notifyEnabledForNodeId(nodeId)
                onActivated: {
                  root.mapSelectedId = nodeId
                  if (nodeId === "__lan__") {
                    root.showLan = true
                    root.glanceTab = "list"
                  }
                }
                onNotifyClicked: root.toggleNotifyForNodeId(nodeId)
              }
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
                  if (!root.mapSelectedId) return "Click a machine, the Caddy hub, a service, or the LAN cluster"
                  var row = root.glanceRowById(root.mapSelectedId)
                  if (!row) return root.mapSelectedId
                  if (row.id === "__lan__") return row.metric + " · click the cluster to open leftovers in List"
                  var metric = row.members ? root.serviceMetric(row) : root.machineMetric(row)
                  return String(row.label || row.id) + " · " + String(row.status) + " · " + metric
                }
              }
              Row {
                visible: root.mapSelectedId !== "" && root.mapSelectedId !== "__lan__"
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
                    var ids = root.groupMemberIds(root.mapSelectedId)
                    if (!node && ids.length) node = root.invNodeById(ids[0])
                    root.goSetup()
                    if (node) root.goFormEdit(node)
                  }
                }
                SegBtn {
                  visible: {
                    var row = root.glanceRowById(root.mapSelectedId)
                    return !!(row && !row.members && root.sshHostFor(row))
                  }
                  label: "SSH"
                  active: false
                  onTapped: root.openSsh(root.glanceRowById(root.mapSelectedId))
                }
                SegBtn {
                  visible: {
                    var row = root.glanceRowById(root.mapSelectedId)
                    return !!(row && row.status === "down" && row.mac)
                  }
                  label: "Wake"
                  active: false
                  onTapped: root.wakeNode(root.glanceRowById(root.mapSelectedId))
                }
              }
              Text {
                visible: root.actionStatus !== ""
                width: parent.width
                text: root.actionStatus
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Flickable {
            id: listScroll
            width: parent.width
            height: Math.min(Style.space(420), listCol.implicitHeight)
            visible: root.glanceTab === "list"
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: listCol.implicitHeight
            Column {
              id: listCol
              width: listScroll.width
              spacing: Style.space(6)

              BandCap { title: "MACHINES"; width: parent.width }
              Repeater {
                model: root.machines
                MeshRow {
                  required property var modelData
                  width: parent.width
                  nodeId: root.sparklineIdFor(modelData)
                  label: String(modelData.label || modelData.id || "")
                  status: root.displayStatus(modelData)
                  metric: root.machineMetric(modelData)
                  hoverTip: root.listRowTooltip(modelData)
                }
              }

              BandCap {
                visible: root.unifiVisible()
                title: "UNIFI"
                width: parent.width
              }
              MeshRow {
                visible: root.unifiVisible()
                width: parent.width
                label: String((root.unifi && root.unifi.name) || "UniFi")
                status: (root.unifi && root.unifi.ok) ? "up" : "down"
                metric: root.unifiMetric()
                lights: root.unifiLights()
                hoverTip: {
                  var u = root.unifi || {}
                  var bits = [u.model || "UniFi OS", u.auth === "none" ? "local /api/system · drop API key in unifi-secrets.json" : ("auth " + u.auth)]
                  if (u.mac) bits.push(u.mac)
                  if (u.url) bits.push(u.url)
                  return bits.join(" · ")
                }
              }

              BandCap { title: "SERVICES"; width: parent.width }
              Repeater {
                model: root.groups
                MeshRow {
                  required property var modelData
                  width: parent.width
                  nodeId: root.sparklineIdFor(modelData)
                  label: String(modelData.label || modelData.id || "")
                  status: String(modelData.status || "unknown")
                  metric: root.serviceMetric(modelData)
                  lights: root.serviceLights(modelData)
                  hoverTip: root.listRowTooltip(modelData)
                }
              }

              BandCap {
                visible: root.showLan
                title: "LAN"
                width: parent.width
              }
              Repeater {
                model: root.showLan ? root.quietLan : []
                MeshRow {
                  required property var modelData
                  width: parent.width
                  nodeId: root.sparklineIdFor(modelData)
                  label: String(modelData.label || modelData.id || "")
                  status: String(modelData.status || "unknown")
                  metric: root.rttText(modelData)
                  hoverTip: root.listRowTooltip(modelData)
                }
              }

              BandCap {
                visible: root.showProxies
                title: "PROXIES"
                width: parent.width
              }
              Repeater {
                model: root.showProxies ? root.quietProxies : []
                MeshRow {
                  required property var modelData
                  width: parent.width
                  nodeId: root.sparklineIdFor(modelData)
                  label: String(modelData.label || modelData.id || "")
                  status: String(modelData.status || "unknown")
                  metric: root.rttText(modelData)
                  hoverTip: root.listRowTooltip(modelData)
                }
              }
            }
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.glanceTab === "map"
                ? "click LAN cluster for leftovers · arrows select · Enter notify · m list"
                : "LAN / PROXIES toggle leftovers · m map · r refresh · s setup"
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

          BandCap {
            visible: !root.inventoryLoading && root.discover.length > 0
            title: "DISCOVERED · click to add"
            width: parent.width
          }
          Column {
            width: parent.width
            spacing: 0
            visible: !root.inventoryLoading && root.discover.length > 0
            Repeater {
              model: root.discover
              SetupRow {
                required property var modelData
                width: parent.width
                node: root.discoveredNode(modelData) || {}
                trailing: "+ add"
                onActivated: root.addDiscovered(modelData)
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
