// Pure parsing and formatting functions for the Mullvad widget.
//
// Nothing here touches QML, Process, or timers — Service.qml does the I/O and
// hands the raw strings over. That keeps parsing testable in Node against the
// samples in docs/mullvad-cli.md, which is the only automated validation
// possible while there is no headless QML harness.
//
// Return contract, following the pattern of Omarchy's built-in panels:
//
//   { ok: false, error, message }            parsing failed
//   { ok: true, unavailable: true, message } command answered, but has no data
//   { ok: true, ... }                        valid data
//
// The Mullvad CLI exits 0 even when it has nothing to report (verified in
// docs/mullvad-cli.md), so output content is the only reliable signal and this
// three-state distinction carries all the weight.
//
// User-facing `message` strings stay in Portuguese, since the panel does; the
// `error` field is diagnostic and goes to the log in English.

.pragma library

// Tunnel phases, in the order the daemon reports them.
var TUNNEL_PHASES = ["disconnected", "connecting", "connected", "disconnecting", "error"]

// One line of `mullvad status --json listen`. The same stream carries tunnel
// and settings events, told apart by their top-level key.
function parseDaemonEvent(line) {
  var text = String(line || "").trim()
  if (text === "") return { ok: true, unavailable: true, message: "" }

  var event
  try {
    event = JSON.parse(text)
  } catch (e) {
    return { ok: false, error: String(e), message: "Evento ilegível do daemon" }
  }

  if (!event || typeof event !== "object") {
    return { ok: false, error: "event is not an object", message: "Evento ilegível do daemon" }
  }
  if (typeof event.state === "string") return readTunnelState(event)
  if (event.relay_settings !== undefined) return readDaemonSettings(event)

  // Device, version, and relay-list events also come through here. Ignoring
  // them silently is correct: they are not errors, and the widget has no use
  // for them.
  return { ok: true, unavailable: true, message: "" }
}

// `mullvad status --json` and the stream's tunnel events share one schema.
function readTunnelState(event) {
  if (!event || typeof event.state !== "string") {
    return { ok: false, error: "missing state field", message: "Estado ilegível" }
  }

  var details = event.details || {}
  var location = details.location || null
  var endpoint = details.endpoint || null

  return {
    ok: true,
    kind: "tunnel",
    phase: normalizePhase(event.state),
    lockedDown: details.locked_down === true,
    // location is null during transitions — on every state change, not only
    // when the connection drops. Never read its absence as a lost tunnel.
    hasLocation: location !== null,
    country: location ? String(location.country || "") : "",
    city: location ? String(location.city || "") : "",
    hostname: location ? String(location.hostname || "") : "",
    exitIsMullvad: location ? location.mullvad_exit_ip === true : false,
    // endpoint only exists once the tunnel is up.
    endpointAddress: endpoint ? String(endpoint.address || "") : "",
    endpointProtocol: endpoint ? String(endpoint.protocol || "") : "",
    tunnelInterface: endpoint ? String(endpoint.tunnel_interface || "") : "",
    features: featureLabels(details.feature_indicators)
  }
}

// The daemon hands over the list of active protections ready-made. Known keys
// get a label; unknown ones are passed through, so a newly added feature shows
// up instead of silently disappearing. Labels are user-facing, hence Portuguese.
var FEATURE_LABELS = {
  QuantumResistance: "Resistente a quântico",
  Daita: "DAITA",
  Multihop: "Multihop",
  BridgeMode: "Bridge",
  SplitTunneling: "Split tunneling",
  LockdownMode: "Lockdown",
  LanSharing: "LAN liberada",
  DnsContentBlockers: "Bloqueio de conteúdo",
  CustomDns: "DNS personalizado",
  ServerIpOverride: "IP de servidor forçado",
  CustomMtu: "MTU personalizada",
  Udp2Tcp: "UDP sobre TCP",
  Shadowsocks: "Shadowsocks",
  QuicObfuscation: "Ofuscação QUIC"
}

function featureLabels(indicators) {
  if (!Array.isArray(indicators)) return []

  return indicators.map(function (indicator) {
    var key = String(indicator || "")
    return FEATURE_LABELS[key] || key
  }).filter(function (label) { return label !== "" })
}

// Daemon settings events. The full object is ~1.5 KB; only these fields matter
// to the widget.
function readDaemonSettings(event) {
  var constraint = locationConstraint(event.relay_settings)
  return {
    ok: true,
    kind: "settings",
    lockdownMode: event.lockdown_mode === true,
    autoConnect: event.auto_connect === true,
    allowLan: event.allow_lan === true,
    // The daemon keeps recent locations; the widget persists nothing.
    recents: Array.isArray(event.recents) ? event.recents : [],
    selectedCountry: constraint.country,
    selectedCity: constraint.city,
    selectedHostname: constraint.hostname
  }
}

function locationConstraint(relaySettings) {
  var empty = { country: "", city: "", hostname: "" }
  if (!relaySettings || !relaySettings.normal) return empty

  var only = relaySettings.normal.location ? relaySettings.normal.location.only : null
  var location = only ? only.location : null
  if (!location) return empty

  return {
    country: String(location.country || ""),
    city: String(location.city || ""),
    hostname: String(location.hostname || "")
  }
}

function normalizePhase(state) {
  var phase = String(state || "").toLowerCase()
  return TUNNEL_PHASES.indexOf(phase) === -1 ? "error" : phase
}

// `mullvad account get` has no --json; the output is text. The "not logged in"
// sentence is a valid result, not a failure — the exit code is 0 either way.
function parseAccountGet(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: true, unavailable: true, message: "Sem resposta do daemon" }

  if (/not logged in/i.test(text)) {
    return { ok: true, loggedIn: false, expiresAt: "", deviceName: "" }
  }

  // The account number appears in this output and is Mullvad's only credential.
  // It is never extracted here — what is not read cannot leak to the UI or log.
  var expiry = text.match(/expires at:\s*(.+)/i)
  var device = text.match(/device name:\s*(.+)/i)

  return {
    ok: true,
    loggedIn: true,
    expiresAt: expiry ? expiry[1].trim() : "",
    deviceName: device ? device[1].trim() : ""
  }
}

// Whole days left until expiry, or -1 when the date is unreadable.
//
// The CLI returns "2026-09-13 09:43:04 -03:00", which Date.parse already accepts
// as is. ISO normalization is only the second attempt: applied first, the "T"
// replacing the space leaves the offset dangling and yields NaN.
function daysUntil(expiresAt, nowMs) {
  var text = String(expiresAt || "").trim()
  if (text === "") return -1

  var target = Date.parse(text)
  if (isNaN(target)) target = Date.parse(toIsoInstant(text))
  if (isNaN(target)) return -1

  return Math.floor((target - nowMs) / 86400000)
}

function toIsoInstant(text) {
  return text
    .replace(/\s+UTC$/i, "Z")
    .replace(" ", "T")
    .replace(/ (?=[+-]\d{2}:?\d{2}$)/, "")
}

// Login errors worth a specific message. Anything else falls back to the raw
// text, truncated.
function loginErrorMessage(raw) {
  var text = String(raw || "").replace(/\s+/g, " ").trim()
  if (text === "") return ""
  if (/does not exist/i.test(text)) return "Conta inexistente"
  if (/INVALID_INPUT/i.test(text)) return "Número de conta inválido"
  if (/too many devices|max devices/i.test(text)) return "Limite de dispositivos atingido"
  return elide(text, 140)
}

// Digits only, and Mullvad uses 16. Validating before spending a round trip to
// the daemon keeps a typo from becoming a network call.
function normalizeAccountNumber(raw) {
  return String(raw || "").replace(/\D/g, "")
}

function isPlausibleAccountNumber(raw) {
  return normalizeAccountNumber(raw).length === 16
}

// `mullvad relay list` returns a tab-indented tree:
//
//   Albania (al)
//   \tTirana (tia) @ 41.32795°N, 19.81902°W
//   \t\tal-tia-wg-001 (103.124.165.2, ...) - hosted by iRegister (rented)
//
// The output weighs ~50 KB against 861 KB for /var/cache/mullvad-vpn/relays.json.
// Since the widget picks by city — and the daemon picks the relay within it —
// the larger cache does not justify staying resident in the bar's process.
function parseRelayList(raw) {
  var text = String(raw || "")
  if (text.trim() === "") {
    // With no account the CLI returns empty with exit 0. A state, not a failure.
    return { ok: true, unavailable: true, message: "Lista de servidores indisponível", cities: [] }
  }

  var lines = text.split("\n")
  var cities = []
  var country = ""
  var countryCode = ""
  var current = null

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.trim() === "") continue

    var countryMatch = line.match(/^([^\t].*) \(([a-z0-9]+)\)\s*$/i)
    if (countryMatch) {
      country = countryMatch[1]
      countryCode = countryMatch[2]
      continue
    }

    var cityMatch = line.match(/^\t([^\t].*?) \(([a-z0-9]+)\)/i)
    if (cityMatch && country !== "") {
      current = {
        country: country,
        countryCode: countryCode,
        city: cityMatch[1],
        cityCode: cityMatch[2],
        relayCount: 0
      }
      cities.push(current)
      continue
    }

    if (/^\t\t\S/.test(line) && current) current.relayCount += 1
  }

  var withRelays = cities.filter(function (city) { return city.relayCount > 0 })
  if (withRelays.length === 0) {
    return { ok: false, error: "no city found", message: "Lista de servidores ilegível", cities: [] }
  }
  return { ok: true, cities: withRelays }
}

// Search by country or city, case-insensitive.
function filterCities(cities, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (needle === "") return cities

  return (cities || []).filter(function (city) {
    return (city.city + " " + city.country + " " + city.countryCode).toLowerCase().indexOf(needle) !== -1
  })
}

function isSelectedCity(city, selectedCountry, selectedCity) {
  if (!city || !selectedCountry) return false
  if (city.countryCode !== selectedCountry) return false
  // A country-only constraint selects the whole country, not one city.
  return selectedCity === "" || city.cityCode === selectedCity
}

// "Gothenburg, Sweden" from the status fields.
function locationLabel(country, city) {
  var parts = []
  if (city) parts.push(city)
  if (country) parts.push(country)
  return parts.join(", ")
}

function phraseForPhase(phase, hasLocation) {
  if (phase === "connected") return hasLocation ? "Conectado" : "Conectado, localizando"
  if (phase === "connecting") return "Conectando"
  if (phase === "disconnecting") return "Desconectando"
  if (phase === "error") return "Erro no túnel"
  return "Desconectado"
}

// Tunnel interface counters, read from
// /sys/class/net/<iface>/statistics/{rx,tx}_bytes — two lines, without root and
// without wireguard-tools, which is not installed. The interface only exists
// while the tunnel is up, so its absence is a state, not an error.
function parseInterfaceCounters(raw) {
  var lines = String(raw || "").trim().split("\n")
  if (lines.length < 2) return { ok: true, unavailable: true, rxBytes: -1, txBytes: -1 }

  var rx = parseInt(lines[0].trim(), 10)
  var tx = parseInt(lines[1].trim(), 10)
  if (!isFinite(rx) || !isFinite(tx)) {
    return { ok: false, error: "unreadable counters", rxBytes: -1, txBytes: -1 }
  }
  return { ok: true, rxBytes: rx, txBytes: tx }
}

var BYTE_UNITS = ["B", "KB", "MB", "GB", "TB"]

function formatBytes(bytes) {
  var value = Number(bytes)
  if (!isFinite(value) || value < 0) return ""

  var unit = 0
  while (value >= 1024 && unit < BYTE_UNITS.length - 1) {
    value /= 1024
    unit += 1
  }

  var text = unit === 0 ? String(Math.round(value)) : value.toFixed(1)
  return text.replace(".", ",") + " " + BYTE_UNITS[unit]
}

function elide(raw, limit) {
  var text = String(raw || "").replace(/\s+/g, " ").trim()
  return text.length > limit ? text.substring(0, limit - 1) + "…" : text
}
