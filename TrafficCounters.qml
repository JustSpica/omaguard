import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Cumulative bytes on the tunnel interface, read from
// /sys/class/net/<iface>/statistics/{rx,tx}_bytes.
//
// This path was chosen over `wg show <iface> transfer` because wireguard-tools
// is not a dependency of mullvad-vpn-daemon and is not installed; sysfs gives
// the same number without root and without an extra package.
//
// The interface exists only while the tunnel is up, so its disappearance is a
// normal state — and the reason counters fall back to -1 instead of freezing at
// the last value read.
Item {
  id: root

  property string tunnelInterface: ""
  property bool active: false
  property int intervalMs: 3000

  readonly property real rxBytes: _rxBytes
  readonly property real txBytes: _txBytes
  readonly property bool hasReading: _rxBytes >= 0

  property real _rxBytes: -1
  property real _txBytes: -1

  readonly property bool _canRead: active && tunnelInterface !== ""

  onTunnelInterfaceChanged: reset()
  on_CanReadChanged: if (!_canRead) reset()

  function reset() {
    _rxBytes = -1
    _txBytes = -1
  }

  function read() {
    if (!_canRead || readProcess.running) return

    var base = "/sys/class/net/" + tunnelInterface + "/statistics/"
    readProcess.command = ["cat", base + "rx_bytes", base + "tx_bytes"]
    readProcess.running = true
  }

  Process {
    id: readProcess
    running: false
    command: []
    stdout: StdioCollector { id: readStdout; waitForEnd: true }
    onExited: function (exitCode) {
      // The interface vanished between scheduling and reading: the tunnel dropped.
      if (exitCode !== 0) { root.reset(); return }

      var counters = Model.parseInterfaceCounters(String(readStdout.text || ""))
      if (!counters.ok || counters.unavailable) return
      root._rxBytes = counters.rxBytes
      root._txBytes = counters.txBytes
    }
  }

  Timer {
    interval: root.intervalMs
    repeat: true
    running: root._canRead
    triggeredOnStart: true
    onTriggered: root.read()
  }
}
