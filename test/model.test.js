// Tests for the widget's pure parsing, running in Node against the real fixtures
// captured in test/fixtures/.
//
//   node --test 'test/*.test.js'
//
// Model.js is a QML JS library — the leading `.pragma library` is not valid Node
// syntax, so the module is loaded without that line. Everything else is plain
// JavaScript, which is exactly why all parsing lives there: it is the only part
// of the plugin verifiable without a running shell.
//
// User-facing strings stay in Portuguese, matching the panel.

const { test } = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

function loadModel() {
  const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  const context = { module: { exports: {} } }
  vm.createContext(context)
  vm.runInContext(source.replace(/^\s*\.pragma library\s*$/m, ""), context)
  return context
}

function fixture(name) {
  return fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8")
}

const Model = loadModel()

test("disconnected status carries a location and denies a Mullvad exit", () => {
  const parsed = Model.parseDaemonEvent(fixture("status-disconnected.json"))

  assert.strictEqual(parsed.ok, true)
  assert.strictEqual(parsed.kind, "tunnel")
  assert.strictEqual(parsed.phase, "disconnected")
  assert.strictEqual(parsed.hasLocation, true)
  assert.strictEqual(parsed.exitIsMullvad, false)
  assert.strictEqual(parsed.country, "Brazil")
})

test("connected status confirms the Mullvad exit and names the relay", () => {
  const parsed = Model.parseDaemonEvent(fixture("status-connected.json"))

  assert.strictEqual(parsed.phase, "connected")
  assert.strictEqual(parsed.exitIsMullvad, true)
  assert.strictEqual(parsed.hostname, "se-sto-wg-201")
  assert.strictEqual(parsed.city, "Stockholm")
})

test("connected status exposes endpoint, interface, and active protections", () => {
  const parsed = Model.parseDaemonEvent(fixture("status-connected.json"))

  assert.strictEqual(parsed.endpointAddress, "89.37.63.10:55178")
  assert.strictEqual(parsed.endpointProtocol, "udp")
  assert.strictEqual(parsed.tunnelInterface, "wg0-mullvad")
  assert.deepStrictEqual(Array.from(parsed.features), ["Resistente a quântico"])
})

test("disconnected has neither endpoint nor protections", () => {
  const parsed = Model.parseDaemonEvent(fixture("status-disconnected.json"))

  assert.strictEqual(parsed.endpointAddress, "")
  assert.strictEqual(parsed.tunnelInterface, "")
  assert.strictEqual(parsed.features.length, 0)
})

test("an unknown feature shows up raw instead of disappearing", () => {
  const event = '{"state":"connected","details":{"feature_indicators":["Multihop","FeatureNova"]}}'
  const parsed = Model.parseDaemonEvent(event)

  assert.deepStrictEqual(Array.from(parsed.features), ["Multihop", "FeatureNova"])
})

test("interface counters come from the two sysfs lines", () => {
  const parsed = Model.parseInterfaceCounters("298650879287\n2598223518\n")

  assert.strictEqual(parsed.ok, true)
  assert.strictEqual(parsed.rxBytes, 298650879287)
  assert.strictEqual(parsed.txBytes, 2598223518)
})

test("a missing interface is unavailability, not an error", () => {
  const parsed = Model.parseInterfaceCounters("")

  assert.strictEqual(parsed.ok, true)
  assert.strictEqual(parsed.unavailable, true)
  assert.strictEqual(parsed.rxBytes, -1)
})

test("bytes become a readable unit with a decimal comma", () => {
  assert.strictEqual(Model.formatBytes(0), "0 B")
  assert.strictEqual(Model.formatBytes(512), "512 B")
  assert.strictEqual(Model.formatBytes(1536), "1,5 KB")
  assert.strictEqual(Model.formatBytes(2598223518), "2,4 GB")
  assert.strictEqual(Model.formatBytes(-1), "")
})

test("a settings event is told apart from a tunnel event", () => {
  const event = JSON.stringify({
    relay_settings: { normal: { location: { only: { location: { country: "se", city: "got" } } } } },
    lockdown_mode: true,
    auto_connect: false,
    recents: []
  })
  const parsed = Model.parseDaemonEvent(event)

  assert.strictEqual(parsed.kind, "settings")
  assert.strictEqual(parsed.lockdownMode, true)
  assert.strictEqual(parsed.selectedCountry, "se")
  assert.strictEqual(parsed.selectedCity, "got")
})

test("a null location during a transition is not a lost connection", () => {
  const parsed = Model.parseDaemonEvent('{"state":"connecting","details":{"location":null,"locked_down":false}}')

  assert.strictEqual(parsed.phase, "connecting")
  assert.strictEqual(parsed.hasLocation, false)
  assert.strictEqual(parsed.country, "")
})

test("an unreadable line is an error, an empty line is just missing data", () => {
  assert.strictEqual(Model.parseDaemonEvent("{this is not json").ok, false)
  assert.strictEqual(Model.parseDaemonEvent("").unavailable, true)
})

test("an unknown stream event is ignored without becoming an error", () => {
  const parsed = Model.parseDaemonEvent('{"app_version_info":{"supported":true}}')

  assert.strictEqual(parsed.ok, true)
  assert.strictEqual(parsed.unavailable, true)
})

test("a state outside the known vocabulary falls back to error", () => {
  assert.strictEqual(Model.parseDaemonEvent('{"state":"quantum"}').phase, "error")
})

test("account get returns expiry and device, and never the account number", () => {
  const raw = fixture("account-get.txt")
  const parsed = Model.parseAccountGet(raw)

  assert.strictEqual(parsed.loggedIn, true)
  assert.strictEqual(parsed.expiresAt, "2026-09-13 09:43:04 -03:00")
  assert.strictEqual(parsed.deviceName, "Robust Owl")

  // The number is in the input; no output field may carry it.
  assert.match(raw, /1111 2222 3333 4444/)
  for (const value of Object.values(parsed)) {
    assert.strictEqual(String(value).includes("1111"), false)
  }
})

test("no account is a valid result, not a failure", () => {
  const parsed = Model.parseAccountGet("Not logged in on any account")

  assert.strictEqual(parsed.ok, true)
  assert.strictEqual(parsed.loggedIn, false)
})

test("days remaining come from the CLI offset format", () => {
  const now = Date.parse("2026-09-03T09:43:04-03:00")

  assert.strictEqual(Model.daysUntil("2026-09-13 09:43:04 -03:00", now), 10)
  assert.strictEqual(Model.daysUntil("2026-09-13 09:43:04 UTC", now), 9)
  assert.strictEqual(Model.daysUntil("never", now), -1)
  assert.strictEqual(Model.daysUntil("", now), -1)
})

test("relay list becomes cities with a server count", () => {
  const parsed = Model.parseRelayList(fixture("relay-list.txt"))

  assert.strictEqual(parsed.ok, true)
  assert.ok(parsed.cities.length > 50, `too few cities: ${parsed.cities.length}`)

  const tirana = parsed.cities.find((c) => c.cityCode === "tia")
  assert.deepStrictEqual(
    { country: tirana.country, countryCode: tirana.countryCode, city: tirana.city, relayCount: tirana.relayCount },
    { country: "Albania", countryCode: "al", city: "Tirana", relayCount: 4 }
  )

  // No city may enter the list without a server: picking one would strand the
  // connection on an impossible constraint.
  assert.strictEqual(parsed.cities.every((c) => c.relayCount > 0), true)
})

test("an empty relay list is unavailability, not an error", () => {
  const parsed = Model.parseRelayList("")

  assert.strictEqual(parsed.ok, true)
  assert.strictEqual(parsed.unavailable, true)
  // Comparing to [] with deepStrictEqual would fail: the array is born in the
  // vm's realm and shares no prototype with the test process's.
  assert.strictEqual(parsed.cities.length, 0)
})

test("city search ignores case and matches country, city, and code", () => {
  const cities = Model.parseRelayList(fixture("relay-list.txt")).cities

  assert.ok(Model.filterCities(cities, "tirana").length >= 1)
  assert.ok(Model.filterCities(cities, "ALBANIA").length >= 1)
  assert.strictEqual(Model.filterCities(cities, "").length, cities.length)
  assert.strictEqual(Model.filterCities(cities, "atlantida").length, 0)
})

test("a country-only constraint selects every city in that country", () => {
  const rio = { country: "Brazil", countryCode: "br", city: "Rio de Janeiro", cityCode: "rio" }

  assert.strictEqual(Model.isSelectedCity(rio, "br", ""), true)
  assert.strictEqual(Model.isSelectedCity(rio, "br", "rio"), true)
  assert.strictEqual(Model.isSelectedCity(rio, "br", "sao"), false)
  assert.strictEqual(Model.isSelectedCity(rio, "se", ""), false)
})

test("login errors become specific messages", () => {
  assert.strictEqual(Model.loginErrorMessage("Error: The account does not exist"), "Conta inexistente")
  assert.strictEqual(Model.loginErrorMessage("status: InvalidArgument, INVALID_INPUT"), "Número de conta inválido")
  assert.strictEqual(Model.loginErrorMessage(""), "")
})

test("an account number is only accepted with 16 digits", () => {
  assert.strictEqual(Model.isPlausibleAccountNumber("1234 5678 9012 3456"), true)
  assert.strictEqual(Model.normalizeAccountNumber("1234 5678 9012 3456"), "1234567890123456")
  assert.strictEqual(Model.isPlausibleAccountNumber("123"), false)
  assert.strictEqual(Model.isPlausibleAccountNumber(""), false)
})
