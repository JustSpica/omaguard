# Mullvad CLI surface

Samples captured on the machine on 2026-08-15, with `mullvad-cli 2026.3` and the
`mullvad-daemon` running. This file is the source of truth for the parsing in
`Model.js` — when the CLI changes, this is where the difference shows up
first.

Anything still unverified is marked as such.

---

## General rule: the exit code is not an error channel

```
mullvad status         exit=0
mullvad account get    exit=0   ← even with no account at all
mullvad relay list     exit=0   ← even when it returns nothing
```

All of them return `0` even when they have nothing to answer with. The signal is
in the **output content**, not the exit status. Parsing must treat empty output
and state sentences as valid results, not failures.

This differs from tailscale, whose `Service.qml` uses `exitCode === 0` as the
main branch. Here the exit code only distinguishes "the binary ran" from "the
binary is missing".

## Tunnel state

### Snapshot — `mullvad status --json`

```json
{
  "state": "disconnected",
  "details": {
    "location": {
      "ipv4": "177.4.239.51",
      "ipv6": null,
      "country": "Brazil",
      "city": "Canoas",
      "latitude": -29.9228,
      "longitude": -51.1744,
      "mullvad_exit_ip": false,
      "hostname": null,
      "entry_hostname": null,
      "obfuscator_hostname": null
    },
    "locked_down": false
  }
}
```

**`mullvad_exit_ip` comes free in the status itself.** The daemon already answers
whether traffic actually leaves through Mullvad, without the widget calling
`am.i.mullvad.net`. See [real exit verification](#real-exit-verification) below.

`details.location` is `null` whenever the daemon has no resolved location (right
after a state change, for instance). Every access needs a guard.

With the tunnel up, `details` gains two fields that do not exist in
`disconnected`:

```json
{
  "state": "connected",
  "details": {
    "endpoint": {
      "address": "89.37.63.10:55178",
      "protocol": "udp",
      "quantum_resistant": true,
      "obfuscation": null,
      "entry_endpoint": null,
      "tunnel_interface": "wg0-mullvad",
      "daita": false
    },
    "location": {
      "ipv4": null,
      "country": "Sweden",
      "city": "Stockholm",
      "mullvad_exit_ip": true,
      "hostname": "se-sto-wg-201"
    },
    "feature_indicators": ["QuantumResistance"]
  }
}
```

`hostname` now names the relay in use and `mullvad_exit_ip` flips to `true` — the
two confirmations that were missing. Note that `location.ipv4` is `null` while
connected and populated while disconnected: the daemon exposes the origin IP, not
the exit one.

`disconnecting` and `error` have **not been observed** yet.

### Stream — `mullvad status --json listen`

Word order matters: `--json` is an option of `status`, not of `listen`.

```
mullvad status --json listen     ✓
mullvad status listen --json     ✗  error: unexpected argument '--json' found
```

It emits **one JSON line per event**, indefinitely, with no separator or
terminator — exactly the format Quickshell's `SplitParser` consumes.

Two event shapes arrive on the same stream, told apart by their top-level key:

| Top-level key | Meaning |
| --- | --- |
| `state` | tunnel state change; same schema as the snapshot |
| `relay_settings` | daemon configuration change |

The settings event is large (~1.5 KB) and carries the whole configuration
object. The fields of interest:

```json
{
  "relay_settings": { "normal": { "location": { "only": { "location": { "country": "se" } } } } },
  "custom_lists": { "custom_lists": [] },
  "lockdown_mode": false,
  "auto_connect": false,
  "allow_lan": false,
  "recents": [],
  "settings_version": 15
}
```

`recents` is maintained **by the daemon itself**. The widget does not need to
persist recent servers in `shell.json` — it can read them from here.

A real sequence, toggling lockdown mode on and off:

```
{"state":"disconnected","details":{"location":{...},"locked_down":false}}
{"relay_settings":{...},"lockdown_mode":true,...}
{"state":"disconnected","details":{"location":null,"locked_down":true}}
{"relay_settings":{...},"lockdown_mode":false,...}
{"state":"disconnected","details":{"location":null,"locked_down":false}}
```

Note that a single action produces **two** events, and that `location` goes back
to `null` mid-transition. The widget must not treat `location: null` as a lost
connection.

## Account

```
$ mullvad account get
Mullvad account:    <redacted>
Expires at:         2026-09-13 09:43:04 -03:00
Device name:        Robust Owl
```

No `--json`; only `-v/--verbose`, which adds `Account id`, `Device id`,
`Device pubkey`, and `Device created`. Parsing is text-based.

With no account:

```
$ mullvad account get
Not logged in on any account
```

That sentence is the canonical "no account" signal — not an error.

The expiry format, `2026-09-13 09:43:04 -03:00`, is accepted by `Date.parse` as
is. Normalizing it to ISO first breaks it: replacing the space with `T` leaves
the offset dangling and yields `NaN`.

### Login — the account number goes over stdin

```
$ printf '1234567890123456\n' | mullvad account login
Enter an account number: Error: The account does not exist
```

The `[ACCOUNT]` argument is **optional**: omitted, the CLI prints
`Enter an account number: ` and reads stdin. That is how the widget must send the
number — never through `argv`, where any `ps` would read it.

In QML this is the pattern the network panel already uses for enterprise wifi
passwords (`/usr/share/omarchy/shell/plugins/panels/network/Panel.qml:777`):

```qml
Process {
  property string accountNumber: ""
  stdinEnabled: true
  onStarted: {
    write(accountNumber + "\n")
    accountNumber = ""        // does not outlive the write
  }
}
```

With no stdin at all, the error differs and is recognizable:

```
Enter an account number: Error: gRPC call returned error
  status: InvalidArgument, message: "INVALID_INPUT"
```

Observed error messages, useful for telling cases apart in the UI:

| Output | Meaning |
| --- | --- |
| `Error: The account does not exist` | well-formed number, nonexistent account |
| `INVALID_INPUT` | malformed or empty number |

## Servers

With no account, **there is no relay list** — neither from the CLI nor in cache.
Once logged in, both appear:

```
$ ls -l /var/cache/mullvad-vpn/
-rw-r--r-- 1 root root 861406 relays.json
-rw-r--r-- 1 root root   1810 version-info.json
```

`relays.json` is world-readable (`0644`). Its shape:

```json
{
  "locations": { "al-tia": { "city": "Tirana", "country": "Albania", "latitude": …, "longitude": … } },
  "wireguard": {
    "relays": [
      { "hostname": "al-tia-wg-001", "active": true, "owned": false,
        "location": "al-tia", "provider": "iRegister", "daita": true, … }
    ]
  }
}
```

574 relays across 91 locations, keyed `<country>-<city>`.

`mullvad relay list` returns the same information as a tab-indented tree, in
~50 KB instead of 861 KB:

```
Albania (al)
	Tirana (tia) @ 41.32795°N, 19.81902°W
		al-tia-wg-001 (103.124.165.2, 2a04:27c0:0:e::f001) - hosted by iRegister (rented)
```

Indentation level is the parser's grammar: 0 = country, 1 = city, 2 = relay.

### Current constraint — `mullvad relay get`

```
Generic constraints
    Location:               country se
    Provider(s):            any
    Ownership:              any
WireGuard constraints
    IP protocol:            any
    Multihop state:         disabled
```

Text, no JSON. The same information arrives structured in the stream's
`relay_settings` event — **prefer the stream** and leave this command aside.

The factory default is `country se` (Sweden).

### Selection

```
mullvad relay set location <COUNTRY> [CITY] [HOSTNAME]
mullvad relay set location <HOSTNAME>
```

The daemon does not reconnect on its own when the constraint changes with the
tunnel up, and `reconnect` does not connect a closed tunnel — so the widget picks
`connect` or `reconnect` depending on the current phase.

## Other state

```
$ mullvad lockdown-mode get
Block traffic when the VPN is disconnected: off

$ mullvad auto-connect get
Autoconnect: off

$ mullvad version
Current version       : 2026.3
Is supported          : true
Suggested upgrade     : none
```

The first two are also present in the stream's `relay_settings` event
(`lockdown_mode`, `auto_connect`) — same recommendation: read them from the
stream.

## Real exit verification

**Solved by the daemon itself.** Verified with the tunnel up: `mullvad_exit_ip`
flips to `true` and `hostname` names the relay. The widget makes no call to
`https://am.i.mullvad.net/json`.

This removed from the original plan an external network dependency, a timeout, a
setting (`verifyExit`), and the latency it would have added to the update cycle.

Reading it needs a transition guard: during a state change the daemon nulls
`location`, and a missing `mullvad_exit_ip` read as `false` would flag a leak on
every connection. It only counts when `state` is `connected` **and** `location`
is present.

## Care when testing connections

Connecting or disconnecting the tunnel re-establishes every network connection on
the machine. An agent running inside the session loses its own API connection the
moment `mullvad connect` runs — execution appears to hang. Test connections from
a terminal outside the agent, or accept the drop.

## Still unverified

- CLI behavior with the daemon stopped (requires `sudo systemctl stop`). It must
  be distinguishable from "CLI not installed" in the state machine.
- `details` schema in the `disconnecting` and `error` states.
