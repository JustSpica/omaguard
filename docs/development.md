# Development

How to work on the plugin, validate it, and avoid the traps that already cost
time.

## Cycle

The plugin folder is the repository. Two ways to work on it:

**Clone straight into the plugins directory** — what `omarchy plugin add` leaves
behind, and the closest thing to what a user runs:

```bash
git clone <url> ~/.config/omarchy/plugins/spica.omaguard
```

Edits reload on save: this is a real directory, so Quickshell's watcher sees it.

**Or symlink an existing checkout**, to keep the repo where you already work:

```bash
ln -sfn "$PWD" ~/.config/omarchy/plugins/spica.omaguard
```

Convenient, but with two costs: the watcher does not follow a directory symlink,
so every change needs `omarchy restart shell`; and `omarchy plugin validate` on
the installed path fails, because it refuses symlinks — validate the repo
directory instead.

```bash
omarchy restart shell
journalctl --user -f | grep "spica.omaguard"
```

## Validation

```bash
node --test 'test/*.test.js'                # parsing, against real fixtures
omarchy plugin validate .                   # manifest, from the repo root
qmllint -I /usr/share/omarchy/shell Service.qml RelayPicker.qml TrafficCounters.qml MullvadIcon.qml
```

The system `qmllint 1.0` exits 255 without a diagnostic on `Panel.qml`. The same
failure happens on Omarchy's built-in Tailscale panel, whose typed `IpcHandler`
uses the same host-supported pattern. Keep `Panel.qml` in the runtime validation
below until the packaged linter can parse that pattern; do not interpret the
omission above as syntax coverage.

**`qmllint` is not enough.** It also approved a nonexistent `fontFamily` on
`TextField` that the shell rejected at runtime. The validation that counts is the
log:

```bash
journalctl --user | grep "Plugin widget spica.omaguard failed"
```

A line there means the widget did not load. On the other hand,
`IpcHandler ... another handler is registered` is expected — see "one instance
per monitor" in [`architecture.md`](architecture.md).

### Tests

Tests run in Node against fixtures captured from the machine, in
`test/fixtures/`. `Model.js` is a QML JS library: the harness strips the
`.pragma library` line and evaluates the rest in a `vm`, since everything else is
plain JavaScript.

When adding a parser, capture the real output first:

```bash
mullvad relay list > test/fixtures/relay-list.txt
mullvad status --json > test/fixtures/status-connected.json
```

Redact anything that is a credential before committing — the account fixture has
its number replaced with `1111 2222 3333 4444`, and a test asserts that no field
of the result carries it.

One harness caveat: comparing values that came out of the `vm` with
`deepStrictEqual` fails on prototype identity (different realms). Compare
`length`, or pass them through `Array.from`.

## Traps

### From the Omarchy harness

- **`settings` arrives after `Component.onCompleted`.** The host injects it by
  duck-typing. Read it only through declarative bindings
  (`readonly property int x: intSetting(...)`), never in imperative
  initialization.
- **Inside `PanelHero.trailingControl`, `root` resolves to the `PanelHero`**, not
  to your `Panel`. Expose state through a named wrapper `Item` — that is what
  `Item { id: header }` is for here.
- **Delegates and inline `component`s need `required property`** — the delegate
  context does not leak into `component` declarations.
- **One `IpcHandler` per target.** Hence `manageIpc: false` in `Panel.qml`, which
  replaces the default handler with one that has extra methods.
- **`PanelKeyCatcher` uses `Keys.priority: Keys.BeforeItem`.** Without
  `blocked: <editor active>`, no text field ever receives typed keys.
- **Never color from `containsMouse`.** The `CursorSurface` contract is: the
  mouse mutates the cursor at the root, color derives from `hasCursor`/`current`.
  That is what guarantees a single highlight on screen across keyboard and mouse.
- **No raw pixels.** Use `Style.space()`, `Style.spacing.*`, `Style.font.*`, and
  `Color.*` — the theme scales and switches between light and dark.
- **`qs.Ui.TextField` inherits from Qt Quick Controls**: its font comes from
  `font.family`, not from the `fontFamily` the rest of the kit uses.

### From diagnostics

- **`column.implicitHeight` inside `onOpenedChanged` reads 0** — the handler runs
  before layout. Measuring dimensions there yields a false diagnosis of a
  collapsed panel. Measure through an on-demand IPC call with the panel already
  open.
- **The shell process is called `quickshell`.** `omarchy-shell` is the
  `systemd-cat` tag in the journal and the name of the IPC client. `pgrep
  omarchy-shell` finds nothing and makes it look like the bar died.
- **`hyprctl layers`** lists layer-shell surfaces. An `omarchy-keyboard-panel`
  among them proves the panel is open, even when nothing shows on screen.

### From testing

**Connecting or disconnecting the tunnel drops every network connection on the
machine**, including that of an AI agent running in the session — execution
appears to hang. Run connection tests from an ordinary terminal.

## Manual verification script

Tests cover parsing; the visual layer needs eyes.

| # | Scenario | Expected |
| --- | --- | --- |
| 1 | `sudo systemctl stop mullvad-daemon` | panel reports the daemon is down, without hanging |
| 2 | `sudo systemctl start mullvad-daemon` | the stream returns through backoff, with no shell restart |
| 3 | Click the toggle | the icon flips immediately, before the daemon confirms |
| 4 | `mullvad disconnect` in another terminal | the widget reflects it within seconds |
| 5 | Pick a city from the list | connects to that city; its name turns bold |
| 6 | Connected | exit confirmed by Mullvad, and the relay under "Servidor" |
| 7 | Turn off wifi while connected | shows "checking", never "outside the tunnel" |
| 8 | `sudo pacman -R mullvad-vpn-daemon` | reports the CLI is missing; the bar stays intact |
| 9 | Type in the server search | keys go to the field, not to the panel |
| 10 | Light and dark themes | colors come from `Color.*`, no raw values |
| 11 | Connected, panel open | traffic counters rise every 3s; stop when the panel closes |
| 12 | `mullvad account logout` in another terminal | the panel returns to the no-account state with the login field |

### Declared limitation

There is no headless QML harness in this environment, so no automated test covers
the visual layer — hence the script above. The mitigation is structural: all
parsing lives in `Model.js` as plain JavaScript, tested in Node.

## Reading references

Never edit these — `/usr/share/omarchy/` belongs to the package and disappears on
the next update. Reading is safe and encouraged.

| Path | Why look |
| --- | --- |
| `plugins/panels/tailscale/` | the template: VPN, toggle, lists, external CLI, error states |
| `plugins/panels/network/` | logic/presentation split with `Model.js` |
| `plugins/panels/dropbox/` | external helper emitting JSON, for CLIs that speak none |
| `Ui/` | the components available in `qs.Ui` |
| `plugins/dev-gallery/` | a live gallery of those components |
| `services/PluginRegistry.qml` | what the manifest validator accepts |

All under `/usr/share/omarchy/shell/`.

## Conventions

Documentation, code comments, test names, and commit messages in English.
Conventional Commits with scope (`feat(plugin):`, `docs:`).

The one exception is **user-facing strings in the panel, which stay in
Portuguese** — that is what the person using the bar reads.
