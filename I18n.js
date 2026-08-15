// Translation lookup for the widget.
//
// Adding a language means two steps: drop a catalogue in locale/<xx_YY>.js and
// register it in CATALOGS below. Nothing else in the plugin knows that
// languages exist.
//
// Locale tags are matched exactly, in xx_YY form. `pt` or `pt_PT` do not
// resolve to `pt_BR`: a near-miss language is more confusing than English.
//
// Missing keys fall back to English silently, which is why en_US.js has to stay
// complete — test/i18n.test.js enforces that every catalogue has the same keys.

.pragma library
.import "locale/en_US.js" as EnUS
.import "locale/pt_BR.js" as PtBR

var DEFAULT_LOCALE = "en_US"

var CATALOGS = {
  "en_US": EnUS.catalog,
  "pt_BR": PtBR.catalog
}

// Resolved when this module is first evaluated, which is before any binding
// that calls t(). Doing it later — from Component.onCompleted, say — would
// leave already-evaluated bindings in English: t() is a plain function with no
// reactive dependency, so a binding that reads it never re-evaluates on its
// own. The language is therefore fixed for the life of the process.
var _locale = detectLocale()

function detectLocale() {
  // Qt is absent under the Node test harness, which drives the locale by hand.
  if (typeof Qt === "undefined" || typeof Qt.locale !== "function") return DEFAULT_LOCALE
  return resolve(Qt.locale().name)
}

// Accepts what a system exposes — "pt_BR.UTF-8", "pt-BR", "en_US" — and returns
// a tag this plugin actually carries.
function resolve(name) {
  var tag = String(name || "").split(".")[0].split("@")[0].replace("-", "_")
  return CATALOGS[tag] ? tag : DEFAULT_LOCALE
}

function setLocale(name) {
  _locale = resolve(name)
  return _locale
}

function locale() {
  return _locale
}

function availableLocales() {
  return Object.keys(CATALOGS)
}

function lookup(tag, key) {
  var catalog = CATALOGS[tag]
  return catalog ? catalog[key] : undefined
}

// The current catalogue first, English second, and the key itself last. A
// returned key means the catalogues disagree — the test suite exists to keep
// that from reaching a user.
function entry(key) {
  var value = lookup(_locale, key)
  if (value === undefined) value = lookup(DEFAULT_LOCALE, key)
  return value === undefined ? key : value
}

function interpolate(template, params) {
  if (!params) return template
  return String(template).replace(/\{(\w+)\}/g, function (match, name) {
    return params[name] === undefined ? match : String(params[name])
  })
}

function t(key, params) {
  var value = entry(key)
  // A plural entry reached through t() would render as [object Object].
  if (value !== null && typeof value === "object") return key
  return interpolate(value, params)
}

// English and Portuguese share the same one/other split. A language that needs
// more forms adds them to its catalogue and a branch here.
function plural(key, count, params) {
  var forms = entry(key)
  if (forms === null || typeof forms !== "object") return t(key, params)

  var form = count === 1 ? forms.one : forms.other
  var merged = { count: count }
  for (var name in params) merged[name] = params[name]
  return interpolate(form, merged)
}

function decimalSeparator() {
  return entry("number.decimal")
}
