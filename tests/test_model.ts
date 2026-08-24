function assertEquals(actual: unknown, expected: unknown): void {
  if (!Object.is(actual, expected))
    throw new Error(`expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
}

const modelSource = (await Deno.readTextFile(new URL("../Model.js", import.meta.url)))
  .replace(/^\.pragma library\s*\n/, "")
const model = new Function(`${modelSource}\nreturn {
  defaultStatus, parseStatus, formatCount, enabledCount, stateTitle, stateMeta, filtersMeta
}`)()

function snapshot(overrides: Record<string, unknown> = {}) {
  return {
    ok: true,
    installed: true,
    running: true,
    httpsFiltering: true,
    blockedToday: 78,
    filters: [{ id: 2, title: "AdGuard Base filter", enabled: true }],
    exitNodeActive: false,
    error: "",
    ...overrides,
  }
}

Deno.test("parseStatus reads a well formed object", () => {
  const s = model.parseStatus(JSON.stringify(snapshot()))
  assertEquals(s.ok, true)
  assertEquals(s.running, true)
  assertEquals(s.blockedToday, 78)
  assertEquals(s.filters.length, 1)
  assertEquals(s.filters[0].title, "AdGuard Base filter")
})

// A parse failure must return the whole shape, because the panel binds every field.
Deno.test("garbage returns the full default shape rather than throwing", () => {
  for (const raw of ["", "not json", "[]", "null", "{}"]) {
    const s = model.parseStatus(raw)
    assertEquals(s.ok, false)
    assertEquals(s.running, false)
    assertEquals(s.blockedToday, 0)
    assertEquals(Array.isArray(s.filters), true)
    assertEquals(s.filters.length, 0)
    assertEquals(typeof s.error, "string")
  }
})

Deno.test("a wrong field type is rejected wholesale", () => {
  assertEquals(model.parseStatus(JSON.stringify(snapshot({ blockedToday: "78" }))).ok, false)
  assertEquals(model.parseStatus(JSON.stringify(snapshot({ running: "yes" }))).ok, false)
  assertEquals(model.parseStatus(JSON.stringify(snapshot({ filters: {} }))).ok, false)
  assertEquals(model.parseStatus(JSON.stringify(snapshot({ blockedToday: -1 }))).ok, false)
  assertEquals(model.parseStatus(JSON.stringify(snapshot({ blockedToday: 1.5 }))).ok, false)
})

// One malformed row must not cost the panel the rows around it.
Deno.test("a malformed filter row is dropped, the good ones survive", () => {
  const s = model.parseStatus(JSON.stringify(snapshot({
    filters: [
      { id: 2, title: "Good", enabled: true },
      { id: "3", title: "Bad id", enabled: true },
      { id: 4, title: 17, enabled: false },
      { id: 5, title: "Also good", enabled: false },
    ],
  })))
  assertEquals(s.ok, true)
  assertEquals(s.filters.length, 2)
  assertEquals(s.filters[0].title, "Good")
  assertEquals(s.filters[1].title, "Also good")
})

Deno.test("formatCount groups thousands", () => {
  assertEquals(model.formatCount(0), "0")
  assertEquals(model.formatCount(78), "78")
  assertEquals(model.formatCount(999), "999")
  assertEquals(model.formatCount(1000), "1,000")
  assertEquals(model.formatCount(1247), "1,247")
  assertEquals(model.formatCount(1234567), "1,234,567")
})

Deno.test("formatCount refuses to render nonsense as a number", () => {
  assertEquals(model.formatCount(-5), "0")
  assertEquals(model.formatCount("abc"), "0")
  assertEquals(model.formatCount(undefined), "0")
  assertEquals(model.formatCount(null), "0")
})

Deno.test("enabledCount counts only enabled rows", () => {
  assertEquals(model.enabledCount([]), 0)
  assertEquals(model.enabledCount(undefined), 0)
  assertEquals(model.enabledCount([{ enabled: true }, { enabled: false }, { enabled: true }]), 2)
})

Deno.test("stateTitle separates absent, stopped and running", () => {
  assertEquals(model.stateTitle(snapshot({ installed: false })), "Not installed")
  assertEquals(model.stateTitle(snapshot({ running: false })), "Not filtering")
  assertEquals(model.stateTitle(snapshot()), "Protecting")
})

Deno.test("stateMeta names the HTTPS filtering state only while running", () => {
  assertEquals(model.stateMeta(snapshot()), "System-wide, HTTPS filtering on")
  assertEquals(model.stateMeta(snapshot({ httpsFiltering: false })), "System-wide, HTTPS filtering off")
  assertEquals(model.stateMeta(snapshot({ running: false })), "AdGuard is stopped")
  assertEquals(model.stateMeta(snapshot({ installed: false })), "adguard-cli is not on this machine")
})

Deno.test("filtersMeta distinguishes all-on from partly-on", () => {
  assertEquals(model.filtersMeta([]), "none added")
  assertEquals(model.filtersMeta([{ enabled: true }, { enabled: true }]), "2 on")
  assertEquals(model.filtersMeta([{ enabled: true }, { enabled: false }]), "1 of 2 on")
})
