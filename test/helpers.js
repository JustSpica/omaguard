// Loads a QML JS library into a vm context, resolving its `.import` statements
// the way the QML engine does: each imported file becomes a namespace object in
// the importer's scope. Shared by the test suites.

const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

// One instance per file for the whole process, mirroring QML: a `.pragma
// library` is a singleton per engine, so Model.js and a test importing I18n.js
// must see the same object — otherwise setLocale() in a test would not reach
// the code under test.
const modules = {}

function loadQmlJs(relativePath) {
  const full = path.join(__dirname, "..", relativePath)
  if (modules[full]) return modules[full]

  const source = fs.readFileSync(full, "utf8")
  const context = { module: { exports: {} } }
  vm.createContext(context)
  modules[full] = context

  const dir = path.dirname(relativePath)
  const imports = [...source.matchAll(/^\s*\.import\s+"([^"]+)"\s+as\s+(\w+)\s*$/gm)]
  for (const [, target, alias] of imports) {
    context[alias] = loadQmlJs(path.join(dir, target))
  }

  const body = source
    .replace(/^\s*\.pragma library\s*$/m, "")
    .replace(/^\s*\.import\s+"[^"]+"\s+as\s+\w+\s*$/gm, "")
  vm.runInContext(body, context)
  return context
}

module.exports = { loadQmlJs }
