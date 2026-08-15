// English catalogue — the default locale and the fallback for every other one.
//
// Keys are namespaced by where they surface: status (tunnel phrases), label
// (panel row titles), action (transient progress text), error (failures),
// account, server, and feature (the daemon's protection indicators).
//
// A key present here and missing elsewhere resolves to this file silently, so
// this catalogue must stay complete. `test/i18n.test.js` enforces that every
// other catalogue matches these keys exactly.
//
// Plural forms are objects with `one` and `other`. Interpolation uses {name}.

.pragma library

var catalog = {
  // Locale-dependent formatting, not translation.
  "number.decimal": ".",

  // Tunnel phrases shown next to the shield and in the state row.
  "status.connected": "Connected",
  "status.connectedLocating": "Connected, locating",
  "status.connecting": "Connecting",
  "status.disconnecting": "Disconnecting",
  "status.disconnected": "Disconnected",
  "status.tunnelError": "Tunnel error",

  // Hero subtitle, one per availability state.
  "status.checking": "Checking",
  "status.notInstalled": "Not installed",
  "status.daemonDown": "Daemon is down",
  "status.checkingAccount": "Checking account",
  "status.noAccount": "No account",
  "status.leaking": "Traffic outside the tunnel",

  // Panel row labels.
  "label.state": "State",
  "label.location": "Location",
  "label.server": "Server",
  "label.exit": "Exit",
  "label.account": "Account",
  "label.device": "Device",
  "label.protections": "Protections",
  "label.endpoint": "Endpoint",
  "label.interface": "Interface",
  "label.traffic": "Traffic",
  "label.lockdown": "LOCKDOWN",

  // Exit verification.
  "exit.confirmed": "Confirmed by Mullvad",
  "exit.outside": "Outside the tunnel",
  "exit.checking": "Checking",

  // Transient progress text while a command runs.
  "action.connecting": "Connecting…",
  "action.disconnecting": "Disconnecting…",
  "action.reconnecting": "Reconnecting…",
  "action.switchingServer": "Switching server…",
  "action.signingIn": "Signing in…",
  "action.connect": "Connect",
  "action.disconnect": "Disconnect",

  // Account section.
  "account.title": "ACCOUNT",
  "account.prompt": "Enter your Mullvad account number (16 digits).",
  "account.placeholder": "0000 0000 0000 0000",
  "account.submit": "Sign in",
  "account.daysLeft": { "one": "{count} day left", "other": "{count} days left" },

  // Server section.
  "server.title": "SERVERS",
  "server.search": "Search country or city",
  "server.pending": "The server list has not arrived yet.",
  "server.noMatch": "No city matches “{query}”.",

  // Backend availability, with the command that fixes each one.
  "setup.cliMissing": "The Mullvad CLI is not installed.\nsudo pacman -S mullvad-vpn-daemon",
  "setup.daemonDown": "The Mullvad daemon is not responding.\nsudo systemctl start mullvad-daemon",

  // Failures surfaced in the panel.
  "error.unreadableEvent": "Unreadable event from the daemon",
  "error.unreadableState": "Unreadable state",
  "error.unreadableAccount": "Unreadable account response",
  "error.noDaemonResponse": "No response from the daemon",
  "error.daemonUnreachable": "The Mullvad daemon is not responding",
  "error.daemonStreamLost": "Connection to the daemon was interrupted",
  "error.relayListUnavailable": "Server list unavailable",
  "error.relayListUnreadable": "Unreadable server list",
  "error.actionFailed": "The action failed",
  "error.accountDigits": "The account number has 16 digits",
  "error.accountMissing": "That account does not exist",
  "error.accountInvalid": "Invalid account number",
  "error.deviceLimit": "Device limit reached",
  "error.signInFailed": "Could not sign in",
  "error.timeoutAction": "The action did not respond in time",
  "error.timeoutDaemon": "The Mullvad daemon did not respond in time",
  "error.timeoutAccount": "The account lookup did not respond in time",
  "error.timeoutRelays": "The server list did not respond in time",
  "error.timeoutLogin": "Sign-in did not respond in time",

  // Protection indicators reported by the daemon. Unknown ones pass through raw
  // so a newly added feature shows up instead of disappearing.
  "feature.QuantumResistance": "Quantum resistant",
  "feature.Daita": "DAITA",
  "feature.Multihop": "Multihop",
  "feature.BridgeMode": "Bridge",
  "feature.SplitTunneling": "Split tunneling",
  "feature.LockdownMode": "Lockdown",
  "feature.LanSharing": "LAN allowed",
  "feature.DnsContentBlockers": "Content blocking",
  "feature.CustomDns": "Custom DNS",
  "feature.ServerIpOverride": "Server IP override",
  "feature.CustomMtu": "Custom MTU",
  "feature.Udp2Tcp": "UDP over TCP",
  "feature.Shadowsocks": "Shadowsocks",
  "feature.QuicObfuscation": "QUIC obfuscation"
}
