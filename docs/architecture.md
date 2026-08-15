# Architecture

How the widget works internally. For what the Mullvad CLI returns, see
[`mullvad-cli.md`](mullvad-cli.md); for the reasoning behind each choice, see
[`decisions.md`](decisions.md).

## The files

The plugin follows the split used by Omarchy's built-in panels
(`panels/tailscale/`, `panels/network/`): presentation separated from I/O, with
parsing isolated in a QML-free JavaScript file.

| File | Responsibility | Knows QML? |
| --- | --- | --- |
| `manifest.json` | id, kinds, entryPoints, settings schema. At the repo root, because the clone is the plugin folder | — |
| `Panel.qml` | bar icon, panel, login, details | yes |
| `Service.qml` | processes, timers, state. No UI | yes |
| `RelayPicker.qml` | city search and list | yes |
| `TrafficCounters.qml` | interface byte counters, read from sysfs | yes |
| `MullvadIcon.qml` | vector shield | yes |
| `Model.js` | parsing and formatting, pure functions | **no** |
| `I18n.js` | translation lookup, plural forms, locale resolution | **no** |
| `locale/*.js` | one catalogue per language | **no** |

`Model.js` importing no QML is what makes the project testable: it is the only
file covered by automated tests, and it covers exactly the part that breaks when
the CLI changes.

## State flow

```
mullvad-daemon
      │
      │  mullvad status --json listen        (stream, one JSON line per event)
      ▼
Service.applyDaemonLine(line)
      │
      ▼
Model.parseDaemonEvent(line) ──► { ok, kind: "tunnel" | "settings", ... }
      │
      ├─ kind "tunnel"   ──► Service.applyTunnel()    phase, location, endpoint, features
      └─ kind "settings" ──► Service.applySettings()  lockdown, auto-connect, constraint
      │
      ▼
Service properties ──► Panel bindings ──► screen
```

State is **pushed**, not polled. A `mullvad disconnect` typed in another terminal
shows up in the widget in under a second, with no interval to wait for.

### The three update layers

| Layer | Role |
| --- | --- |
| **Stream** (`status --json listen`) | primary source. No latency, no burst of subprocesses |
| **Backoff supervisor** | the stream dies when the daemon restarts. Reconnects with exponential backoff from 1s to 30s, capped |
| **Reconciliation** (`status --json`) | every `reconcileIntervalSec` and on panel open, corrects drift if the stream died silently |

The backoff resets on any reconciliation tick where the stream is alive —
without that, it would only shrink after a successful restart.

### Parsing contract

Every parser in `Model.js` returns one of three shapes:

```js
{ ok: false, error, message }              // parsing failed
{ ok: true, unavailable: true, message }   // command answered, but there is no data
{ ok: true, ...fields }                    // valid data
```

This three-state distinction carries all the weight because **the Mullvad CLI
exits 0 even when it has nothing to report** — no account, no relay list,
nothing. Output content is the only reliable signal; the exit code only
distinguishes "the binary ran" from "the binary is missing".

## Availability state machine

Four different absences, each with its own UI, because each one calls for a
different action from the user:

| State | Detection | What the panel shows |
| --- | --- | --- |
| CLI missing | `which mullvad` ≠ 0 | how to install the package |
| Daemon down | CLI present, `status` returns nothing | how to start the service |
| No account | daemon answers `Not logged in` | account number field |
| Operable | active account | state, servers, details |

The UI derives from one mutually exclusive `availabilityState`. If the daemon
becomes unavailable, tunnel and account snapshots are cleared together; stale
account data can never leave actions enabled behind a "daemon down" warning.

## Optimistic state

The toggle does not wait for the daemon to confirm:

```qml
property int _desired: -1   // -1 follows real state; 0/1 while an action has not landed
readonly property bool connected: _desired === -1 ? phase === "connected" : (_desired === 1)
```

`_desired` returns to `-1` as soon as the daemon event agrees with it, or when
the action fails. Same mechanism as the built-in tailscale panel.

## Real exit verification

*Does an up interface prove traffic flows through it?* It does not — and the
`mullvad_exit_ip` field the daemon already ships in its status answers the
question directly. No external call.

Reading it requires a guard:

```qml
readonly property bool leaking: mullvad.phase === "connected"
  && mullvad.hasLocation && !mullvad.exitIsMullvad
```

The daemon nulls `location` during transitions, and a missing `mullvad_exit_ip`
read as `false` would flag a leak on every connection. Without `hasLocation`,
the panel says "checking" — never "outside the tunnel".

## Account number security

The account number is Mullvad's **only** credential: whoever holds it holds the
account. The widget treats it as a secret along the whole path.

| Where | How |
| --- | --- |
| Input | field with `password: true`, masked on screen |
| Transport | `stdin` of `mullvad account login`, never `argv` — in `argv` any `ps` would read it |
| Retention | the property is cleared in `onStarted`, right after the `write` |
| Output | `Model.parseAccountGet` reads expiry and device, and does **not** extract the number even though it is in the input |
| Persistence | none. Never written to `shell.json`, logs, or disk |

There is a dedicated test for this: it feeds output containing a number and
asserts that no field of the result carries it.

Commands are built as arrays (`["mullvad", "connect"]`), with no shell — there is
no string to inject into. Where a shell string is unavoidable, use
`Util.shellQuote`.

## Traffic counters

These come from `/sys/class/net/<iface>/statistics/{rx,tx}_bytes`, not from
`wg show <iface> transfer`: `wireguard-tools` is not a dependency of
`mullvad-vpn-daemon` and need not be installed. Sysfs gives the same number,
without root.

The interface name comes from the status itself
(`endpoint.tunnel_interface`), never hardcoded. The interface exists only while
the tunnel is up, so its disappearance is a normal state — and the reason
counters fall back to `-1` instead of freezing at the last value read.

Reads happen **only while the panel is open** (`watchingTraffic`), every 3
seconds. With the panel closed, the cost is zero.

## Process discipline

Rules that keep the widget from becoming a subprocess factory inside the bar's
own process:

- Every launch is guarded by `if (!proc.running) ...`.
- Actions get a 20s watchdog, **armed only at launch**. Re-arming on every
  refresh would push the deadline ahead of a hung process forever — a real bug,
  already fixed and commented in the built-in tailscale `Service.qml`.
- Every finite daemon query has its own watchdog. A hung snapshot, account
  lookup, relay list, login, or sysfs read is stopped without borrowing another
  process's deadline.
- Relay selection is sequenced by process completion: a successful
  `relay set location` starts `connect` or `reconnect` from `onExited`. There is
  no fixed delay that can race a slow daemon.
- The relay list (~50 KB of output) loads once and only reloads on demand; it
  changes on a scale of days.
- The account is queried once an hour, plus once per panel open.

## One instance per monitor

Omarchy creates one widget instance per monitor. On a two-monitor machine there
are two `Service` objects, hence **two resident event streams**.

That is the same cost the tailscale panel pays with its per-instance polling.
Coordinating instances through `BarWidget`'s `broadcast()` would only be worth it
if the cost showed up in practice.

This also explains the `Handler was registered but will not be used` warning in
the log: only one instance serves the IPC target. Every built-in panel emits the
same warning.
