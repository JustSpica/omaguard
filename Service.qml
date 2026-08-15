import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// State and I/O for the Mullvad widget. No UI: Panel.qml reads these properties
// and calls these functions. The file name follows the convention of Omarchy's
// built-in panels (tailscale, dropbox), where the Panel/Service pair is the
// standard split between presentation and external process.
//
// The source of truth is the `mullvad status --json listen` stream, which pushes
// one JSON line per event. Polling exists only as a safety net.
Item {
  id: root

  property var settings: ({})

  // Injected by the host after Component.onCompleted, so it can only be read
  // through declarative bindings — never in imperative initialization.
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.min(max, Math.max(min, n))
  }

  readonly property int reconcileIntervalSec: intSetting("reconcileIntervalSec", 30, 10, 3600)

  // --- availability -----------------------------------------------------------
  // Three distinct absences, because each one calls for a different UI: binary
  // off PATH, daemon down, and daemon with no account.
  property bool cliResolved: false
  property bool cliInstalled: false
  property bool daemonReachable: false
  property bool accountResolved: false
  property bool loggedIn: false

  // --- tunnel -----------------------------------------------------------------
  property string phase: "disconnected"
  property bool hasLocation: false
  property bool lockedDown: false
  property string country: ""
  property string city: ""
  property string hostname: ""
  property bool exitIsMullvad: false
  property string endpointAddress: ""
  property string endpointProtocol: ""
  property string tunnelInterface: ""
  property var features: []

  // Tunnel interface counters. -1 while there is no valid reading.
  readonly property real rxBytes: traffic.rxBytes
  readonly property real txBytes: traffic.txBytes

  // The panel turns this on when it opens: counters only matter while someone is
  // looking, and this keeps the widget from spending a process every few seconds
  // in the background.
  property bool watchingTraffic: false

  // --- daemon settings --------------------------------------------------------
  property bool lockdownMode: false
  property bool autoConnect: false
  property string selectedCountry: ""
  property string selectedCity: ""
  property var recentLocations: []

  // --- servers ----------------------------------------------------------------
  property var cities: []
  property bool citiesResolved: false

  // --- account ----------------------------------------------------------------
  property string expiresAt: ""
  property string deviceName: ""
  readonly property int daysLeft: expiresAt === "" ? -1 : Model.daysUntil(expiresAt, Date.now())

  // --- feedback ---------------------------------------------------------------
  property string actionStatus: ""
  property string lastError: ""

  readonly property bool busy: actionProcess.running || loginProcess.running
  readonly property bool connected: _desired === -1 ? phase === "connected" : (_desired === 1)
  readonly property bool transitioning: phase === "connecting" || phase === "disconnecting"
  readonly property string phrase: Model.phraseForPhase(phase, hasLocation)
  readonly property string locationLabel: Model.locationLabel(country, city)

  // Optimistic state: the icon reacts to the click without waiting for the
  // daemon event. -1 follows real state; 0/1 while an action has not landed yet.
  property int _desired: -1

  signal loginFinished(bool success)

  // --- lifecycle --------------------------------------------------------------

  Component.onCompleted: probeCli()

  function probeCli() {
    if (cliProbe.running) return
    cliProbe.running = true
  }

  function start() {
    if (!cliInstalled) return
    snapshot()
    if (!statusStream.running) statusStream.running = true
  }

  // `mullvad status --json` — reconciliation and first read. Word order matters
  // in the stream (--json is an option of status, not of listen), and keeping the
  // same order here stops anyone from "fixing" the stream's.
  function snapshot() {
    if (!cliInstalled || snapshotProcess.running) return
    snapshotProcess.running = true
  }

  function refresh() {
    if (!cliResolved) { probeCli(); return }
    snapshot()
    refreshAccount()
    refreshRelays()
  }

  function refreshAccount() {
    if (!cliInstalled || accountProcess.running) return
    accountProcess.running = true
  }

  // The server list changes on a scale of days and costs ~50 KB of output, so it
  // loads once and only reloads on demand.
  function refreshRelays(force) {
    if (!cliInstalled || relayListProcess.running) return
    if (citiesResolved && force !== true) return
    relayListProcess.running = true
  }

  // --- actions ----------------------------------------------------------------

  function connect() {
    if (!canOperate()) return
    _desired = 1
    runAction(["mullvad", "connect"], "Conectando…")
  }

  function disconnect() {
    if (!canOperate()) return
    _desired = 0
    runAction(["mullvad", "disconnect"], "Desconectando…")
  }

  function toggleConnection() {
    connected ? disconnect() : connect()
  }

  // Picking a server is a request to connect to it: with the tunnel up the daemon
  // does not reconnect on its own when the constraint changes, and with it down,
  // merely storing the constraint would do nothing visible.
  function setLocation(country, city) {
    if (!canOperate() || !country) return
    var command = ["mullvad", "relay", "set", "location", country]
    if (city) command.push(city)
    runAction(command, "Trocando servidor…")
    _desired = 1
    followUpAction.restart()
  }

  function canOperate() {
    return cliInstalled && !actionProcess.running
  }

  function runAction(command, label) {
    actionStatus = label || ""
    lastError = ""
    actionProcess.command = command
    actionProcess.running = true
    if (!actionWatchdog.running) actionWatchdog.start()
  }

  // The account number is Mullvad's only credential. It goes over stdin because
  // in argv any `ps` would read it, and it is cleared as soon as the process
  // receives it — never logged, displayed, or persisted.
  function login(accountNumber) {
    if (!cliInstalled || loginProcess.running) return
    if (!Model.isPlausibleAccountNumber(accountNumber)) {
      lastError = "O número da conta tem 16 dígitos"
      return
    }
    lastError = ""
    actionStatus = "Entrando…"
    loginProcess.pendingAccount = Model.normalizeAccountNumber(accountNumber)
    loginProcess.running = true
  }

  // --- applying state ---------------------------------------------------------

  function applyDaemonLine(line) {
    var parsed = Model.parseDaemonEvent(line)
    if (!parsed.ok) {
      lastError = parsed.message
      console.warn("spica.omaguard:", parsed.error)
      return
    }
    if (parsed.unavailable) return

    daemonReachable = true
    parsed.kind === "tunnel" ? applyTunnel(parsed) : applySettings(parsed)
  }

  function applyTunnel(state) {
    phase = state.phase
    hasLocation = state.hasLocation
    lockedDown = state.lockedDown
    exitIsMullvad = state.exitIsMullvad
    endpointAddress = state.endpointAddress
    endpointProtocol = state.endpointProtocol
    tunnelInterface = state.tunnelInterface
    features = state.features

    // The daemon nulls location during transitions. Keeping the last known one
    // stops the panel from flickering between a place and blank on every event.
    if (state.hasLocation) {
      country = state.country
      city = state.city
      hostname = state.hostname
    } else if (state.phase === "disconnected") {
      hostname = ""
    }

    if (_desired !== -1 && connectedPhase(state.phase) === (_desired === 1)) _desired = -1
    if (state.phase !== "error") lastError = ""
  }

  function connectedPhase(phase) {
    return phase === "connected"
  }

  function applySettings(config) {
    lockdownMode = config.lockdownMode
    autoConnect = config.autoConnect
    recentLocations = config.recents
    selectedCountry = config.selectedCountry
    selectedCity = config.selectedCity
  }

  function applyAccount(raw) {
    var parsed = Model.parseAccountGet(raw)
    accountResolved = true
    if (!parsed.ok || parsed.unavailable) return

    loggedIn = parsed.loggedIn === true
    expiresAt = parsed.loggedIn ? parsed.expiresAt : ""
    deviceName = parsed.loggedIn ? parsed.deviceName : ""
  }

  function noteStatus(message) {
    actionStatus = message
    actionStatusTimer.restart()
  }

  // --- processes --------------------------------------------------------------

  Process {
    id: cliProbe
    running: false
    command: ["which", "mullvad"]
    onExited: function (exitCode) {
      root.cliResolved = true
      root.cliInstalled = exitCode === 0
      if (root.cliInstalled) root.start()
    }
  }

  Process {
    id: snapshotProcess
    running: false
    command: ["mullvad", "status", "--json"]
    stdout: StdioCollector { id: snapshotStdout; waitForEnd: true }
    stderr: StdioCollector { id: snapshotStderr; waitForEnd: true }
    onExited: function () {
      var out = String(snapshotStdout.text || "").trim()
      if (out === "") {
        // Binary present and silent: the daemon is down.
        root.daemonReachable = false
        root.lastError = Model.elide(String(snapshotStderr.text || "") || "Daemon do Mullvad não responde", 140)
        return
      }
      root.applyDaemonLine(out)
    }
  }

  // The stream lives as long as the daemon does. SplitParser delivers line by
  // line while the process runs; StdioCollector would only deliver at the end,
  // which never comes.
  Process {
    id: statusStream
    running: false
    command: ["mullvad", "status", "--json", "listen"]
    stdout: SplitParser { onRead: function (line) { root.applyDaemonLine(line) } }
    onExited: function () {
      root.daemonReachable = false
      root.scheduleStreamRestart()
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function (exitCode) {
      actionWatchdog.stop()
      var error = String(actionStderr.text || "").trim()
      if (exitCode !== 0 || error !== "") {
        root._desired = -1
        root.lastError = Model.elide(error || "A ação falhou", 140)
        root.actionStatus = ""
        return
      }

      root.actionStatus = ""
      root.snapshot()
    }
  }

  Process {
    id: loginProcess
    property string pendingAccount: ""

    running: false
    command: ["mullvad", "account", "login"]
    stdinEnabled: true
    stdout: StdioCollector { id: loginStdout; waitForEnd: true }
    stderr: StdioCollector { id: loginStderr; waitForEnd: true }

    onStarted: {
      write(pendingAccount + "\n")
      pendingAccount = ""
    }
    onExited: {
      root.actionStatus = ""
      // The CLI writes both the prompt and the error to stdout, and returns 0 even
      // when the account does not exist — the text is the only signal.
      var output = String(loginStdout.text || "") + " " + String(loginStderr.text || "")
      if (/error/i.test(output)) {
        root.lastError = Model.loginErrorMessage(output)
        root.loginFinished(false)
        return
      }
      root.lastError = ""
      root.refresh()
      root.loginFinished(true)
    }
  }

  Process {
    id: accountProcess
    running: false
    command: ["mullvad", "account", "get"]
    stdout: StdioCollector { id: accountStdout; waitForEnd: true }
    onExited: root.applyAccount(String(accountStdout.text || ""))
  }

  TrafficCounters {
    id: traffic
    tunnelInterface: root.tunnelInterface
    active: root.watchingTraffic && root.phase === "connected"
  }

  Process {
    id: relayListProcess
    running: false
    command: ["mullvad", "relay", "list"]
    stdout: StdioCollector { id: relayListStdout; waitForEnd: true }
    onExited: {
      var parsed = Model.parseRelayList(String(relayListStdout.text || ""))
      if (!parsed.ok) {
        root.lastError = parsed.message
        return
      }
      // With no account the list comes back empty: leaving it unresolved lets the
      // next refresh try again as soon as login happens.
      if (parsed.unavailable) return
      root.cities = parsed.cities
      root.citiesResolved = true
    }
  }

  // --- timers -----------------------------------------------------------------

  // Stream backoff. A restarting daemon is normal (package update, suspend); the
  // cap keeps reconnection from becoming an unbounded tight loop.
  property int streamRetryMs: 1000

  function scheduleStreamRestart() {
    if (!cliInstalled) return
    streamRestart.interval = streamRetryMs
    streamRetryMs = Math.min(30000, streamRetryMs * 2)
    streamRestart.restart()
  }

  Timer {
    id: streamRestart
    repeat: false
    onTriggered: {
      if (!root.cliInstalled || statusStream.running) return
      statusStream.running = true
      root.snapshot()
    }
  }

  // Reconciliation: corrects drift if the stream died without firing onExited.
  Timer {
    interval: root.reconcileIntervalSec * 1000
    repeat: true
    running: root.cliInstalled
    triggeredOnStart: true
    onTriggered: {
      root.snapshot()
      // A healthy stream resets the backoff; without this it would only shrink on restart.
      if (statusStream.running) root.streamRetryMs = 1000
      else root.scheduleStreamRestart()
    }
  }

  // The account changes slowly: hourly is enough, plus the refresh on panel open.
  Timer {
    interval: 3600000
    repeat: true
    running: root.cliInstalled
    triggeredOnStart: true
    onTriggered: root.refreshAccount()
  }

  // Armed only at action launch. Re-arming on every refresh would push the
  // deadline ahead of a hung process forever.
  Timer {
    id: actionWatchdog
    interval: 20000
    repeat: false
    onTriggered: {
      if (!actionProcess.running) return
      actionProcess.running = false
      root._desired = -1
      root.actionStatus = ""
      root.lastError = "A ação não respondeu a tempo"
    }
  }

  // Waits for the constraint to be stored before bringing the tunnel up.
  // `reconnect` does not connect a closed tunnel, and `connect` does not switch
  // relays on an open one — hence the two paths.
  Timer {
    id: followUpAction
    interval: 400
    repeat: false
    onTriggered: {
      if (root.phase === "disconnected") root.runAction(["mullvad", "connect"], "Conectando…")
      else root.runAction(["mullvad", "reconnect"], "Reconectando…")
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }
}
