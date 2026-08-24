.pragma library

function defaultStatus() {
  return { ok: false, installed: false, running: false, httpsFiltering: false,
           blockedToday: 0, filters: [], exitNodeActive: false,
           updateSummary: "", lastUpdateTs: 0, error: "", parsed: false }
}

function nonnegativeInteger(raw) {
  return typeof raw === "number" && isFinite(raw) && raw >= 0 && Math.floor(raw) === raw
}

function validFilter(row) {
  return row && typeof row === "object"
    && nonnegativeInteger(row.id)
    && typeof row.title === "string"
    && typeof row.enabled === "boolean"
    && typeof row.category === "string"
    && nonnegativeInteger(row.blocked)
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
    && typeof doc.updateSummary === "string"
    && nonnegativeInteger(doc.lastUpdateTs)
    && typeof doc.error === "string"
}

// helper sample: {"ok":true,"installed":true,"running":true,"httpsFiltering":true,"blockedToday":70,"filters":[{"id":2,"title":"AdGuard Base filter","enabled":true,"category":"Ad blocking","blocked":11}],"exitNodeActive":false,"updateSummary":"","lastUpdateTs":1787538763,"error":""}
function parseStatus(raw) {
  var out = defaultStatus()
  if (!raw) { out.error = "Could not read the helper's output."; return out }
  var doc
  try { doc = JSON.parse(String(raw)) } catch (e) { out.error = "Could not read the helper's output."; return out }
  if (!validStatusShape(doc)) { out.error = "Could not read the helper's output."; return out }

  out.parsed = true
  out.ok = doc.ok === true
  out.installed = doc.installed === true
  out.running = doc.running === true
  out.httpsFiltering = doc.httpsFiltering === true
  out.blockedToday = doc.blockedToday
  out.exitNodeActive = doc.exitNodeActive === true
  out.updateSummary = String(doc.updateSummary || "")
  out.lastUpdateTs = doc.lastUpdateTs
  out.error = String(doc.error || "")

  var rows = []
  for (var i = 0; i < doc.filters.length; i++) {
    var row = doc.filters[i]
    if (!validFilter(row)) continue
    rows.push({ id: row.id, title: String(row.title), enabled: row.enabled === true,
                category: String(row.category), blocked: row.blocked })
  }
  out.filters = rows
  if (rows.length !== doc.filters.length && out.error === "")
    out.error = "Some filters could not be read."
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
  if (!s.installed) return "AdGuard is not installed"
  if (s.running) return "Protection is on"
  return "Protection is off"
}

// AdGuard's own category names, said the way its desktop app says them. An unmapped
// category still gets a row, so a filter list this map has never heard of is never
// silently dropped from the totals.
function categoryLabel(category) {
  if (category === "Ad blocking") return "Ads blocked"
  if (category === "Privacy") return "Trackers blocked"
  if (category === "Security") return "Threats blocked"
  if (category === "Social widgets") return "Social widgets blocked"
  if (category === "" || category === undefined) return "Other blocked"
  return String(category) + " blocked"
}

// One row per category that has a filter, in the order AdGuard lists them.
function categoryRows(filters) {
  if (!Array.isArray(filters)) return []
  var order = []
  var totals = {}
  for (var i = 0; i < filters.length; i++) {
    var key = String(filters[i].category || "")
    if (totals[key] === undefined) { totals[key] = 0; order.push(key) }
    totals[key] += filters[i].blocked
  }
  var rows = []
  for (var j = 0; j < order.length; j++) {
    rows.push({ key: order[j], label: categoryLabel(order[j]), blocked: totals[order[j]] })
  }
  return rows
}

// "updated 2h ago", in the coarsest unit that is still true.
function updatedAgo(lastUpdateTs, nowSec) {
  var secondsPerMinute = 60
  var secondsPerHour = 3600
  var secondsPerDay = 86400
  if (!lastUpdateTs || lastUpdateTs <= 0) return ""
  var age = Math.floor(nowSec - lastUpdateTs)
  if (age < secondsPerMinute) return "updated just now"
  if (age < secondsPerHour) return "updated " + Math.floor(age / secondsPerMinute) + "m ago"
  if (age < secondsPerDay) return "updated " + Math.floor(age / secondsPerHour) + "h ago"
  return "updated " + Math.floor(age / secondsPerDay) + "d ago"
}


function stateMeta(s) {
  if (!s.installed) return "adguard-cli is not on this machine"
  if (!s.running) return "AdGuard is stopped"
  if (s.httpsFiltering) return "System-wide, HTTPS filtering on"
  return "System-wide, HTTPS filtering off"
}

// Reads as the value on an informational row, so it says the whole state in one phrase.
function filtersMeta(filters) {
  var on = enabledCount(filters)
  var total = Array.isArray(filters) ? filters.length : 0
  if (total === 0) return "none added"
  if (on === total) return "all " + total + " on"
  return on + " of " + total + " on"
}
