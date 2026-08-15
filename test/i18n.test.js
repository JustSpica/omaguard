// Tests for the translation layer.
//
//   node --test 'test/*.test.js'
//
// The key-parity test is the one that matters: missing keys fall back to
// English silently, which is the right behaviour at runtime and the wrong thing
// to discover in production. This suite fails the build instead.

const { test } = require("node:test")
const assert = require("node:assert")
const { loadQmlJs } = require("./helpers.js")

const I18n = loadQmlJs("I18n.js")

function keysOf(catalog) {
  return Object.keys(catalog).sort()
}

test("every catalogue carries exactly the English keys", () => {
  const english = keysOf(I18n.CATALOGS[I18n.DEFAULT_LOCALE])

  for (const tag of I18n.availableLocales()) {
    const keys = keysOf(I18n.CATALOGS[tag])
    const missing = english.filter((k) => !keys.includes(k))
    const extra = keys.filter((k) => !english.includes(k))

    assert.deepStrictEqual(missing, [], `${tag} is missing keys: ${missing}`)
    assert.deepStrictEqual(extra, [], `${tag} has keys English does not: ${extra}`)
  }
})

test("plural entries have the same shape in every catalogue", () => {
  const english = I18n.CATALOGS[I18n.DEFAULT_LOCALE]

  for (const key of Object.keys(english)) {
    const isPlural = english[key] !== null && typeof english[key] === "object"
    if (!isPlural) continue

    for (const tag of I18n.availableLocales()) {
      const forms = I18n.CATALOGS[tag][key]
      assert.strictEqual(typeof forms, "object", `${tag}.${key} should be a plural object`)
      assert.strictEqual(typeof forms.one, "string", `${tag}.${key} is missing "one"`)
      assert.strictEqual(typeof forms.other, "string", `${tag}.${key} is missing "other"`)
    }
  }
})

test("locale tags resolve exactly, in xx_YY form", () => {
  assert.strictEqual(I18n.resolve("pt_BR"), "pt_BR")
  assert.strictEqual(I18n.resolve("pt_BR.UTF-8"), "pt_BR")
  assert.strictEqual(I18n.resolve("pt-BR"), "pt_BR")
  assert.strictEqual(I18n.resolve("en_US"), "en_US")
})

test("a near-miss language falls back to English rather than guessing", () => {
  assert.strictEqual(I18n.resolve("pt"), "en_US")
  assert.strictEqual(I18n.resolve("pt_PT"), "en_US")
  assert.strictEqual(I18n.resolve("es_ES"), "en_US")
  assert.strictEqual(I18n.resolve(""), "en_US")
  assert.strictEqual(I18n.resolve(null), "en_US")
})

test("translation follows the active locale", () => {
  I18n.setLocale("en_US")
  assert.strictEqual(I18n.t("status.connected"), "Connected")

  I18n.setLocale("pt_BR")
  assert.strictEqual(I18n.t("status.connected"), "Conectado")

  I18n.setLocale("en_US")
})

test("interpolation replaces named placeholders", () => {
  I18n.setLocale("en_US")
  assert.strictEqual(I18n.t("server.noMatch", { query: "atlantis" }), "No city matches “atlantis”.")
})

test("an unknown placeholder is left visible instead of blanked", () => {
  assert.strictEqual(I18n.t("server.noMatch", {}), "No city matches “{query}”.")
})

test("plural picks the form and injects the count", () => {
  I18n.setLocale("en_US")
  assert.strictEqual(I18n.plural("account.daysLeft", 1), "1 day left")
  assert.strictEqual(I18n.plural("account.daysLeft", 28), "28 days left")

  I18n.setLocale("pt_BR")
  assert.strictEqual(I18n.plural("account.daysLeft", 1), "1 dia restante")
  assert.strictEqual(I18n.plural("account.daysLeft", 28), "28 dias restantes")

  I18n.setLocale("en_US")
})

test("an unknown key returns itself rather than throwing", () => {
  assert.strictEqual(I18n.t("nope.not.here"), "nope.not.here")
})

test("a plural entry read through t() does not render as an object", () => {
  assert.strictEqual(I18n.t("account.daysLeft"), "account.daysLeft")
})

test("the decimal separator follows the locale", () => {
  I18n.setLocale("en_US")
  assert.strictEqual(I18n.decimalSeparator(), ".")

  I18n.setLocale("pt_BR")
  assert.strictEqual(I18n.decimalSeparator(), ",")

  I18n.setLocale("en_US")
})
