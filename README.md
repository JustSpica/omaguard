# Omaguard

A Mullvad VPN widget for the [Omarchy](https://omarchy.org) Quattro.

It shows the real connection state, connects and disconnects in one click and switches servers from the panel.

```
┌──────────────────────────────────────┐
│ 🛡  Mullvad                      ●━━ │
│    CONECTADO · ESTOCOLMO, SUÉCIA     │
│                                      │
│ Estado                    Conectado  │
│ Localização     Stockholm, Sweden    │
│ Servidor            se-sto-wg-201    │
│ Saída        Confirmada pela Mullvad │
│ Conta            28 dias restantes   │
│ Proteções   Resistente a quântico    │
│ Tráfego      ↓ 1,2 GB   ↑ 84,3 MB    │
│                                      │
│ SERVIDORES                           │
│ ┌──────────────────────────────────┐ │
│ │ Buscar país ou cidade            │ │
│ └──────────────────────────────────┘ │
│   Stockholm                       12 │
│   Sweden                             │
│   Gothenburg                       5 │
│   Sweden                             │
└──────────────────────────────────────┘
```

## What it does

- **Live state.** The daemon pushes events; a `mullvad disconnect` typed in
  another terminal shows up in the widget in under a second.
- **One click to connect.** No password dialog, ever.
- **Login in the panel itself.** Type the account number right there; it travels
  over stdin, is never visible to other processes, and is never written to disk.
- **Server switching with search.** 91 cities, each showing how many servers it
  has.
- **Tells you whether traffic really leaves through the VPN.** That is the
  question "the interface is up" cannot answer — and the main reason this widget
  exists.
- **Details while connected.** Active protections, endpoint, tunnel interface,
  and bytes transferred.
- **Account status.** Days remaining and the device name.
- **Degrades without breaking.** With no CLI installed, no daemon, or no account,
  it explains what is missing instead of taking the bar down.

## Requirements

- Omarchy 4.x (Quattro), where the bar is a Quickshell plugin
- `mullvad-vpn-daemon` — the CLI and the daemon, without the Electron app

```bash
sudo pacman -S mullvad-vpn-daemon
sudo systemctl enable --now mullvad-daemon
```

No terminal login needed: the panel has a field for the account number.

## Installation

```bash
omarchy plugin add https://github.com/JustSpica/omaguard.git --enable
```

That is the whole thing. Omarchy clones the repository into
`~/.config/omarchy/plugins/spica.omaguard/`, validates the manifest before
trusting it, and — with `--enable` — asks which bar section to place the widget
in and writes the entry for you.

Drop `--enable` to install without touching the bar, then place it later:

```bash
omarchy plugin enable spica.omaguard --section right
omarchy plugin disable spica.omaguard
omarchy bar move spica.omaguard --before omarchy.network
```

### Updating and removing

```bash
omarchy plugin update spica.omaguard    # fetch, show the diff, re-validate
omarchy plugin remove spica.omaguard    # uninstall
```

`update` only fast-forwards, re-validates the manifest afterwards, and rolls the
checkout back if the new revision fails validation — a broken push upstream
cannot leave you with a broken bar.

### What gets installed

The repository *is* the plugin folder: `manifest.json` sits at its root because
the clone lands directly in the plugins directory, with no subdirectory in
between. `docs/` and `test/` come along and are simply never loaded.

Plugins run as unsandboxed code inside the long-lived `omarchy-shell` process,
which is why `omarchy plugin add` prints a warning and asks for confirmation.
Read the source before you enable anything — this one included.

## Usage

| Action | Effect |
| --- | --- |
| Left click on the icon | open the panel |
| Right click | connect or disconnect |
| Middle click | force a refresh |
| `c` with the panel open | connect or disconnect |
| `Esc` | close |

The icon is a shield: **filled** while the tunnel is up, **struck through** while
it is down, and carrying a **badge** when something needs attention — no account,
or traffic leaving outside the tunnel.

### From the command line

```bash
omarchy-shell spica.omaguard status
omarchy-shell spica.omaguard toggleVpn
omarchy-shell spica.omaguard connect
omarchy-shell spica.omaguard disconnect
```

Handy for Hyprland keybindings.

## Configuration

Inline keys on the `shell.json` entry:

| Key | Default | What it does |
| --- | --- | --- |
| `reconcileIntervalSec` | 30 | how often state is reconciled. Normal state arrives as daemon events; this only corrects drift if the stream dies silently. Accepts 10 to 3600 |

Example:

```json
{ "id": "spica.omaguard", "reconcileIntervalSec": 60 }
```

## How it works

State comes from `mullvad status --json listen`, a stream the daemon feeds with
one JSON line per event — not from polling. A backoff supervisor reconnects the
stream when the daemon restarts, and a periodic reconciliation corrects drift if
it dies silently.

The widget never needs root: the Mullvad CLI talks to the daemon over a socket.
The account number, Mullvad's only credential, travels over stdin and is never
persisted.

Details in [`docs/architecture.md`](docs/architecture.md).

## Layout

```
manifest.json        id, kinds, entryPoints, and the settings schema
Panel.qml            bar icon, panel, login, details
Service.qml          event stream, backoff, reconciliation, actions
RelayPicker.qml      city search and list
TrafficCounters.qml  interface byte counters, read from sysfs
Model.js             pure parsing — no QML, testable in Node
MullvadIcon.qml      vector shield
test/                Model tests and real CLI fixtures
docs/                architecture, decisions, CLI surface, development
```

The manifest sits at the repository root because `omarchy plugin add` clones the
repo *as* the plugin folder — there is no notion of a subdirectory. Extra files
(`docs/`, `test/`, `README.md`) ride along harmlessly; the validator only rejects
symlinks.

## Documentation

| Document | About |
| --- | --- |
| [`docs/architecture.md`](docs/architecture.md) | state flow, update layers, credential handling, process discipline |
| [`docs/decisions.md`](docs/decisions.md) | why Mullvad CLI over plain WireGuard, why streaming over polling, what was left out |
| [`docs/mullvad-cli.md`](docs/mullvad-cli.md) | verified CLI surface, with real samples of every output |
| [`docs/development.md`](docs/development.md) | dev cycle, validation, Quickshell traps, and the manual verification script |

## Conventions

Documentation, code comments, test names, and commit messages in English;
Conventional Commits with scope (`feat(plugin):`, `docs:`). User-facing strings in
the panel stay in Portuguese.

The full rules for agents live in [`AGENTS.md`](AGENTS.md) — that is the
canonical file; do not duplicate rules in this README.
