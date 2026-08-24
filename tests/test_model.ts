function assertEquals(actual: unknown, expected: unknown): void {
  if (!Object.is(actual, expected))
    throw new Error(`expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
}

const modelSource = (await Deno.readTextFile(new URL("../Model.js", import.meta.url)))
  .replace(/^\.pragma library\s*\n/, "")
const model = new Function(`${modelSource}\nreturn {
  defaultStatus, parseStatus, formatCount, enabledCount, stateTitle, stateMeta,
  filtersMeta, categoryLabel, categoryRows, updatedAgo
}`)()

function filter(over: Record<string, unknown> = {}) {
  return { id: 2, title: "AdGuard Base filter", enabled: true, category: "Ad blocking", blocked: 0, ...over }
}

function snapshot(over: Record<string, unknown> = {}) {
  return {
    ok: true, installed: true, running: true, httpsFiltering: true,
    blockedToday: 78, filters: [filter()], exitNodeActive: false,
    updateSummary: "", lastUpdateTs: 1787538763, error: "", ...over,
  }
}

Deno.test("parseStatus reads a well formed object", () => {
  const s = model.parseStatus(JSON.stringify(snapshot()))
  assertEquals(s.ok, true)
  assertEquals(s.blockedToday, 78)
  assertEquals(s.filters.length, 1)
  assertEquals(s.filters[0].category, "Ad blocking")
  assertEquals(s.lastUpdateTs, 1787538763)
})

// A parse failure must return the whole shape, because the panel binds every field.
Deno.test("garbage returns the full default shape rather than throwing", () => {
  for (const raw of ["", "not json", "[]", "null", "{}"]) {
    const s = model.parseStatus(raw)
    assertEquals(s.ok, false)
    assertEquals(s.blockedToday, 0)
    assertEquals(s.lastUpdateTs, 0)
    assertEquals(Array.isArray(s.filters), true)
    assertEquals(s.filters.length, 0)
    assertEquals(typeof s.error, "string")
  }
})

Deno.test("a wrong field type is rejected wholesale", () => {
  assertEquals(model.parseStatus(JSON.stringify(snapshot({ blockedToday: "78" }))).ok, false)
  assertEquals(model.parseStatus(JSON.stringify(snapshot({ running: "yes" }))).ok, false)
  assertEquals(model.parseStatus(JSON.stringify(snapshot({ filters: {} }))).ok, false)
  assertEquals(model.parseStatus(JSON.stringify(snapshot({ lastUpdateTs: -1 }))).ok, false)
  assertEquals(model.parseStatus(JSON.stringify(snapshot({ updateSummary: 3 }))).ok, false)
})

// One malformed row must not cost the panel the rows around it.
Deno.test("a malformed filter row is dropped, the good ones survive", () => {
  const s = model.parseStatus(JSON.stringify(snapshot({
    filters: [
      filter({ id: 2, title: "Good" }),
      filter({ id: "3", title: "Bad id" }),
      filter({ id: 4, blocked: "many" }),
      filter({ id: 5, title: "Also good" }),
    ],
  })))
  assertEquals(s.ok, true)
  assertEquals(s.filters.length, 2)
  assertEquals(s.filters[0].title, "Good")
  assertEquals(s.filters[1].title, "Also good")
})

Deno.test("formatCount groups thousands", () => {
  assertEquals(model.formatCount(0), "0")
  assertEquals(model.formatCount(999), "999")
  assertEquals(model.formatCount(1000), "1,000")
  assertEquals(model.formatCount(1234567), "1,234,567")
})

Deno.test("formatCount refuses to render nonsense as a number", () => {
  for (const bad of [-5, "abc", undefined, null]) assertEquals(model.formatCount(bad), "0")
})

Deno.test("stateTitle separates absent, stopped and running", () => {
  assertEquals(model.stateTitle(snapshot({ installed: false })), "AdGuard is not installed")
  assertEquals(model.stateTitle(snapshot({ running: false })), "Protection is off")
  assertEquals(model.stateTitle(snapshot()), "Protection is on")
})

Deno.test("filtersMeta phrases the whole state", () => {
  assertEquals(model.filtersMeta([]), "none added")
  assertEquals(model.filtersMeta([{ enabled: true }, { enabled: true }]), "all 2 on")
  assertEquals(model.filtersMeta([{ enabled: true }, { enabled: false }]), "1 of 2 on")
})

// AdGuard's category names carry the desktop app's phrasing where one exists.
Deno.test("categoryLabel maps the known categories and keeps the rest", () => {
  assertEquals(model.categoryLabel("Ad blocking"), "Ads blocked")
  assertEquals(model.categoryLabel("Privacy"), "Trackers blocked")
  assertEquals(model.categoryLabel("Security"), "Threats blocked")
  assertEquals(model.categoryLabel("Social widgets"), "Social widgets blocked")
  assertEquals(model.categoryLabel("Language-specific"), "Language-specific blocked")
  assertEquals(model.categoryLabel(""), "Other blocked")
})

Deno.test("categoryRows totals each category and keeps AdGuard's order", () => {
  const rows = model.categoryRows([
    filter({ id: 2, category: "Ad blocking", blocked: 11 }),
    filter({ id: 3, category: "Privacy", blocked: 100 }),
    filter({ id: 17, category: "Privacy", blocked: 69 }),
    filter({ id: 208, category: "Security", blocked: 0 }),
  ])
  assertEquals(rows.length, 3)
  assertEquals(rows[0].label, "Ads blocked")
  assertEquals(rows[0].blocked, 11)
  assertEquals(rows[1].label, "Trackers blocked")
  assertEquals(rows[1].blocked, 169)
  assertEquals(rows[2].blocked, 0)
})

Deno.test("categoryRows survives nothing to total", () => {
  assertEquals(model.categoryRows([]).length, 0)
  assertEquals(model.categoryRows(undefined).length, 0)
})

Deno.test("updatedAgo uses the coarsest unit that is still true", () => {
  const now = 1000000
  assertEquals(model.updatedAgo(0, now), "")
  assertEquals(model.updatedAgo(now - 10, now), "updated just now")
  assertEquals(model.updatedAgo(now - 300, now), "updated 5m ago")
  assertEquals(model.updatedAgo(now - 7200, now), "updated 2h ago")
  assertEquals(model.updatedAgo(now - 172800, now), "updated 2d ago")
})

// A clock that has drifted behind the filter's stamp must not print a negative age.
Deno.test("updatedAgo never reads as the future", () => {
  assertEquals(model.updatedAgo(2000, 1000), "updated just now")
})

// parsed says the document was readable; ok says AdGuard is healthy. The service keeps the
// last known state when parsed is false, so conflating the two wipes good numbers.
Deno.test("parsed separates an unreadable answer from an unhealthy one", () => {
  assertEquals(model.parseStatus(JSON.stringify(snapshot())).parsed, true)
  assertEquals(model.parseStatus(JSON.stringify(snapshot({ ok: false }))).parsed, true)
  for (const raw of ["", "nonsense", "{}", "null", "[]"]) {
    assertEquals(model.parseStatus(raw).parsed, false)
  }
})

// The sample-input comment is documentation, so it has to survive its own validator.
Deno.test("the documented helper sample validates", () => {
  const documented = {
    ok: true, installed: true, running: true, httpsFiltering: true, blockedToday: 70,
    filters: [{ id: 2, title: "AdGuard Base filter", enabled: true, category: "Ad blocking", blocked: 11 }],
    exitNodeActive: false, updateSummary: "", lastUpdateTs: 1787538763, error: "",
  }
  const s = model.parseStatus(JSON.stringify(documented))
  assertEquals(s.parsed, true)
  assertEquals(s.filters.length, 1)
})

// A dropped row used to leave a smaller list looking healthy.
Deno.test("a dropped filter row is reported rather than passed off as a shorter list", () => {
  const s = model.parseStatus(JSON.stringify(snapshot({
    filters: [filter({ id: 2 }), filter({ id: "3" }), filter({ id: 4 })],
  })))
  assertEquals(s.filters.length, 2)
  assertEquals(s.error, "Some filters could not be read.")
})

Deno.test("a helper error is not overwritten by the dropped-row message", () => {
  const s = model.parseStatus(JSON.stringify(snapshot({
    error: "adguard-cli status failed.",
    filters: [filter({ id: 2 }), filter({ id: "3" })],
  })))
  assertEquals(s.error, "adguard-cli status failed.")
})
