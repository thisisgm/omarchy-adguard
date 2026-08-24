.pragma library

function defaultStatus() {
  return { ok: false, installed: false, running: false, httpsFiltering: false,
           blockedToday: 0, filters: [], exitNodeActive: false, error: "" }
}

function nonnegativeInteger(raw) {
  return typeof raw === "number" && isFinite(raw) && raw >= 0 && Math.floor(raw) === raw
}

function validFilter(row) {
  return row && typeof row === "object"
    && nonnegativeInteger(row.id)
    && typeof row.title === "string"
    && typeof row.enabled === "boolean"
}

function validStatusShape(doc) {
  return doc && typeof doc === "object"
    && typeof doc.ok === "boolean"
    && typeof doc.installed === "boolean"
    && typeof doc.running === "boolean"
    && typeof doc.httpsFiltering === "boolean"
    && nonnegativeInteger(doc.blockedToday)
    && Array.isArray(doc.filters)
    && typeof doc.exitNodeActive === "boolean"
    && typeof doc.error === "string"
}

// helper sample: {"ok":true,"installed":true,"running":true,"httpsFiltering":true,"blockedToday":70,"filters":[{"id":2,"title":"AdGuard Base filter","enabled":true}],"exitNodeActive":false,"error":""}
function parseStatus(raw) {
  var out = defaultStatus()
  if (!raw) { out.error = "Could not read the helper's output."; return out }
  var doc
  try { doc = JSON.parse(String(raw)) } catch (e) { out.error = "Could not read the helper's output."; return out }
  if (!validStatusShape(doc)) { out.error = "Could not read the helper's output."; return out }

  out.ok = doc.ok === true
  out.installed = doc.installed === true
  out.running = doc.running === true
  out.httpsFiltering = doc.httpsFiltering === true
  out.blockedToday = doc.blockedToday
  out.exitNodeActive = doc.exitNodeActive === true
  out.error = String(doc.error || "")

  var rows = []
  for (var i = 0; i < doc.filters.length; i++) {
    var row = doc.filters[i]
    if (!validFilter(row)) continue
    rows.push({ id: row.id, title: String(row.title), enabled: row.enabled === true })
  }
  out.filters = rows
  return out
}

// 1247 reads as 1,247 rather than 1.2k, because the exact number is the point of the panel.
function formatCount(value) {
  var n = parseInt(value, 10)
  if (!isFinite(n) || n < 0) n = 0
  var digits = String(n)
  var out = ""
  var seen = 0
  for (var i = digits.length - 1; i >= 0; i--) {
    out = digits.charAt(i) + out
    seen++
    if (seen % 3 === 0 && i > 0) out = "," + out
  }
  return out
}

function enabledCount(filters) {
  if (!Array.isArray(filters)) return 0
  var n = 0
  for (var i = 0; i < filters.length; i++) if (filters[i].enabled) n++
  return n
}

function stateTitle(s) {
  if (!s.installed) return "Not installed"
  if (s.running) return "Protecting"
  return "Not filtering"
}

function stateMeta(s) {
  if (!s.installed) return "adguard-cli is not on this machine"
  if (!s.running) return "AdGuard is stopped"
  if (s.httpsFiltering) return "System-wide, HTTPS filtering on"
  return "System-wide, HTTPS filtering off"
}

function filtersMeta(filters) {
  var on = enabledCount(filters)
  var total = Array.isArray(filters) ? filters.length : 0
  if (total === 0) return "none added"
  if (on === total) return on + " on"
  return on + " of " + total + " on"
}
