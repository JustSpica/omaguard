# Decisions

What was decided, and why. A durable record: a decision that only exists in chat
history does not exist.

## Backend: Mullvad CLI, not plain WireGuard

| | Plain WireGuard | **Mullvad CLI** |
| --- | --- | --- |
| Privilege | root on every operation | none — the CLI talks to the daemon over a socket |
| Switching servers | download `.conf`, manage files | one command |
| Kill switch | hand-written in `PostUp`/`PreDown` | built in |
| Keys | expire silently | rotated automatically |
| Cost | no daemon | resident daemon, ~33 MiB, tied to one provider |

The absence of a password prompt decided it. Plain WireGuard needs root for every
`wg-quick` call, and no amount of polkit makes that as direct as a CLI that talks
to a daemon over a socket.

The package is `mullvad-vpn-daemon` (CLI + daemon), not `mullvad-vpn`, which
drags in an Electron app that is useless to a bar widget.

## State by stream, not polling

`mullvad status --json listen` emits one JSON line per event, indefinitely. The
daemon pushes; the widget never has to ask.

The built-in tailscale panel — this project's template in almost everything —
polls, because `tailscale` offers no stream. Where Mullvad does offer one,
following the template would be worse: a `mullvad disconnect` in another terminal
would take up to 30 seconds to appear instead of under one.

Polling survives as a safety-net reconciliation, not as the primary source.

## Exit verification out of the code

The original plan called for `curl https://am.i.mullvad.net/json` to confirm
traffic really leaves through the tunnel, with a timeout, network-failure
handling, and a setting to turn it off.

Mapping the CLI showed that `mullvad_exit_ip` already ships in `status --json`.
That removed, in one go: an external network dependency, a timeout, a setting
(`verifyExit`), the latency it would add to the update cycle, and one more
process running inside the bar.

It stands as a lesson in method: **mapping the real surface before writing the
parsing** cut a feature that would otherwise have been written and maintained
for nothing.

## Login in the widget, with the number over stdin

Login was initially meant to stay out of the widget, delegated to a floating
terminal — the account number is a credential, and passing it through `argv`
would expose it to any `ps`.

The requirement changed: login had to fit in the widget. Checking showed that
`mullvad account login` takes an **optional** `[ACCOUNT]` argument — omitted, it
prints `Enter an account number:` and reads from stdin.

That satisfied the request without giving up the security property. It is the
same pattern the built-in network panel uses for enterprise wifi passwords.

## Cities, not relays

The list holds 574 servers across 91 cities. The panel lists **cities**:

- The daemon already balances load within a city — picking an individual relay
  rarely helps.
- 91 items fit a navigable list; 574 do not.
- `mullvad relay set location <country> <city>` is exactly that granularity.

## `mullvad relay list`, not `relays.json`

The daemon maintains `/var/cache/mullvad-vpn/relays.json`, readable by any user
(`0644`) — the structured source the plan preferred.

The widget still uses `mullvad relay list`: 50 KB of hierarchical text against
861 KB of JSON. Since the choice is per city, the larger cache does not justify
staying resident in the process that also draws the bar and the lock screen.

Parsing by tab indentation is trivial and covered by tests against real output.

## Installed through `omarchy plugin add`, not a script of our own

Omarchy ships a git-based installer: `omarchy plugin add <url>` clones a repo,
validates it, and drops it in `~/.config/omarchy/plugins/<id>/`, with
`omarchy plugin update` and `omarchy plugin remove` to match.

An earlier layout shipped its own `install.sh`, symlinking a `plugin/`
subdirectory into place. It was dropped in favor of the built-in path, which
gives for free what a hand-written installer would have to earn: manifest
validation before install, a fast-forward-only update that re-validates and rolls
back on failure, uninstallation, and interactive placement into a bar section.

The consequence for the layout is that **`manifest.json` has to sit at the
repository root**: the clone *is* the plugin folder, so there is no subdirectory
to nest it in. Extra files ride along harmlessly — the validator only rejects
symlinks, and ignores `.git`.

It also fixes the hot-reload trap. The old symlinked directory was invisible to
Quickshell's watcher, so every edit needed a shell restart. A cloned plugin is a
real directory, and edits reload on save. The symlink route still works for
development, at that cost — and with the caveat that
`omarchy plugin validate <installed path>` then fails on the symlink itself, so
validation has to run against the repository directory.

## The bar entry is not this repository's business

`omarchy plugin enable` writes the widget's entry into
`~/.config/omarchy/shell.json`, and that is the only place it belongs. This
repository ships nothing that edits the bar layout: where and whether the widget
appears is the user's configuration, managed with `omarchy plugin enable`,
`omarchy plugin disable`, and `omarchy bar move`.

If that path happens to be a symlink, the write follows it: Quickshell's
`atomicWrites` replaces the *target*, not the link.

## Plugin id: `io.github.justspica.omaguard`

The id carries the project name, not the backend's: what the widget talks to may
change, but the plugin stays the same thing.

The reverse-domain form is what the plugin marketplace prefers, and ids there are
permanent — a retired one cannot be reused — so it was worth adopting before the
first submission rather than after. Omarchy's own validator only requires that an
id stay out of the reserved `omarchy.*` namespace.

Because the id is fixed in `manifest.json`, the install is independent of the
machine's username. It is also the plugin's address in three other places — the
folder under `~/.config/omarchy/plugins/`, the entry in `shell.json`, and the IPC
target — plus `moduleName` and `ipcTarget` in `Panel.qml`. Changing it means
reinstalling, not renaming a folder.

## Out of scope

Deliberately not implemented:

| What | Why |
| --- | --- |
| Split tunneling, custom lists, multihop, DAITA | rare configuration, better left to the CLI |
| Per-network auto-connect | the daemon already has `mullvad auto-connect` |
| `Account id`, `Device id`, `Device pubkey` | sensitive identifiers with no operational value in the bar — showing them only widens exposure |
| Logging out from the panel | built and then removed: it misbehaved while connected, and revoking a device is rare enough that `mullvad account logout` in a terminal covers it |
| MTU, key rotation interval | rarely relevant; they live in `mullvad tunnel get` |
