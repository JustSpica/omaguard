import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "I18n.js" as I18n

Panel {
  id: root

  moduleName: "io.github.justspica.omaguard"
  ipcTarget: "io.github.justspica.omaguard"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Tunnel up but traffic leaving outside it — distinct from plain "connected",
  // and the state an interface check alone cannot see. Only meaningful when a
  // location is present: during transitions the daemon nulls the field and
  // everything would look like a leak.
  readonly property bool leaking: mullvad.phase === "connected" && mullvad.hasLocation && !mullvad.exitIsMullvad
  readonly property bool needsAccount: mullvad.availabilityState === "noAccount"
  readonly property bool operable: mullvad.availabilityState === "operable"

  // Outside "operable" the tunnel state is unknown, not off: a stopped daemon
  // leaves the WireGuard interface up in the kernel. The icon must not claim
  // "disconnected" for something it cannot see — it goes neutral instead.
  readonly property bool tunnelStateKnown: operable

  // Situations that ask the user to do something, as opposed to merely waiting
  // for a probe to answer.
  readonly property bool needsAttention: leaking || needsAccount
    || mullvad.availabilityState === "cliMissing"
    || mullvad.availabilityState === "daemonDown"

  readonly property color barIconColor: {
    if (leaking) return root.urgent
    if (!tunnelStateKnown) return Qt.darker(root.barForeground, 1.55)
    return mullvad.connected ? root.barForeground : Qt.darker(root.barForeground, 1.55)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property bool loginActive: false
  property string loginDraft: ""

  onOpenedChanged: {
    mullvad.watchingTraffic = opened
    if (!opened) { loginActive = false; loginDraft = ""; return }
    mullvad.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: mullvad
    settings: root.settings

    onLoginFinished: function (success) {
      if (!success) return
      root.loginActive = false
      root.loginDraft = ""
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function connect(): string { return root.ipcActionResult(mullvad.connect()) }
    function disconnect(): string { return root.ipcActionResult(mullvad.disconnect()) }
    function toggleVpn(): string { return root.ipcActionResult(mullvad.toggleConnection()) }
    function refresh(): string { return root.ipcActionResult(mullvad.refresh()) }
    function status(): string {
      return JSON.stringify({
        phase: mullvad.phase,
        location: mullvad.locationLabel,
        exitIsMullvad: mullvad.exitIsMullvad,
        loggedIn: mullvad.loggedIn,
        daysLeft: mullvad.daysLeft
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar

    iconComponent: Component {
      Item {
        MullvadIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.barIconColor
          badgeColor: root.urgent
          filled: root.tunnelStateKnown && mullvad.connected
          crossed: root.tunnelStateKnown && !mullvad.connected
          warning: root.needsAttention
        }
      }
    }

    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) mullvad.toggleConnection()
      else if (buttonCode === Qt.MiddleButton) mullvad.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Keys.priority is BeforeItem: without this gate the text fields would never
      // receive typed keys.
      blocked: root.loginActive || relayPicker.searching

      onCloseRequested: root.close()
      onActivateRequested: if (root.operable) mullvad.toggleConnection()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (key) {
        if (!root.operable) return
        if (key === "c" || key === "C") mullvad.toggleConnection()
      }

      // The panel is capped in height, so the content has to scroll rather than
      // be clipped: with the map and a connected tunnel it overflows, and
      // without this the server list simply disappeared off the bottom.
      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: panelFlick.width
        spacing: Style.space(10)

        Item {
          id: header
          width: parent.width
          implicitHeight: hero.implicitHeight

          // Inside trailingControl, `root` resolves to the PanelHero — the panel's
          // state has to arrive through this named wrapper.
          readonly property bool canToggle: root.operable

          PanelHero {
            id: hero
            width: parent.width
            title: "Mullvad"
            meta: root.heroMeta()
            detail: mullvad.lockdownMode ? I18n.t("label.lockdown") : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: mullvad.connected ? 1.0 : 0.5

            iconComponent: Component {
              MullvadIcon {
                iconSize: Style.font.display
                color: root.leaking ? root.urgent : root.foreground
                badgeColor: root.urgent
                filled: root.tunnelStateKnown && mullvad.connected
                crossed: root.tunnelStateKnown && !mullvad.connected
                warning: root.needsAttention
              }
            }

            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                visible: header.canToggle
                checked: mullvad.connected
                busy: mullvad.busy || mullvad.transitioning
                foreground: hero.foreground
                onToggled: mullvad.toggleConnection()

                PanelToolTip {
                  visible: powerSwitch.containsMouse
                  text: I18n.t(mullvad.connected ? "action.disconnect" : "action.connect")
                  fontFamily: hero.fontFamily
                }
              }
            }
          }
        }

        // Disconnected, the daemon reports where *you* are rather than a relay,
        // so the marker changes colour with its meaning: accent for the server
        // the tunnel exits through, plain foreground for your own location.
        WorldMap {
          visible: root.operable
          width: parent.width
          foreground: root.foreground
          accent: root.leaking ? root.urgent
            : mullvad.phase === "connected" ? Color.accent
            : root.foreground
          server: isFinite(mullvad.latitude) && isFinite(mullvad.longitude)
            ? { lat: mullvad.latitude, lon: mullvad.longitude }
            : null
        }

        Text {
          visible: mullvad.actionStatus !== "" || mullvad.lastError !== ""
          width: parent.width
          text: mullvad.actionStatus !== "" ? mullvad.actionStatus : mullvad.lastError
          color: mullvad.lastError !== "" && mullvad.actionStatus === "" ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // --- backend missing -----------------------------------------------

        MessageBlock {
          visible: mullvad.availabilityState === "cliMissing"
          width: parent.width
          text: I18n.t("setup.cliMissing")
        }

        MessageBlock {
          visible: mullvad.availabilityState === "daemonDown"
          width: parent.width
          text: I18n.t("setup.daemonDown")
        }

        // --- login -----------------------------------------------------------

        Column {
          visible: root.needsAccount
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: I18n.t("account.title")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            text: I18n.t("account.prompt")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: accountField
              Layout.fillWidth: true
              // The number is the credential: masked on screen, held only in the
              // field, and discarded as soon as the daemon receives it over stdin.
              password: true
              placeholderText: I18n.t("account.placeholder")
              foreground: root.foreground
              // TextField inherits from Qt Quick Controls: its font comes from
              // font.family, not from the kit's fontFamily.
              font.family: root.fontFamily
              text: root.loginDraft
              enabled: !mullvad.busy

              onTextChanged: root.loginDraft = text
              onActiveFocusChanged: root.loginActive = activeFocus
              onAccepted: root.submitLogin()
              Keys.onEscapePressed: {
                root.loginDraft = ""
                keyCatcher.forceActiveFocus()
              }
            }

            Button {
              text: I18n.t("account.submit")
              enabled: !mullvad.busy && root.loginDraft.replace(/\D/g, "").length === 16
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.submitLogin()
            }
          }
        }

        // --- connection --------------------------------------------------
        //
        // State and location are deliberately absent: the hero already reads
        // "CONECTADO - TOKYO, JAPAN", and repeating it two rows below cost the
        // height that pushed the server list off the panel.

        Column {
          visible: root.operable
          width: parent.width
          spacing: Style.space(5)

          PanelSeparator { foreground: root.foreground }

          DetailRow {
            width: parent.width
            visible: mullvad.phase === "connected"
            label: I18n.t("label.exit")
            value: root.exitPhrase()
            emphasis: root.leaking
          }

          DetailRow {
            width: parent.width
            visible: mullvad.hostname !== ""
            label: I18n.t("label.server")
            value: mullvad.hostname
          }

          DetailRow {
            width: parent.width
            visible: mullvad.rxBytes >= 0
            label: I18n.t("label.traffic")
            value: "↓ " + root.formatBytes(mullvad.rxBytes) + "   ↑ " + root.formatBytes(mullvad.txBytes)
          }

          DetailRow {
            width: parent.width
            visible: mullvad.daysLeft >= 0
            label: I18n.t("label.account")
            value: I18n.plural("account.daysLeft", mullvad.daysLeft)
            emphasis: mullvad.daysLeft <= 7
          }
        }

        // --- technical details ---------------------------------------------
        //
        // Diagnostic rather than daily: kept below the fold of a full panel,
        // where scrolling reaches them without them crowding the rest.

        Column {
          visible: root.operable && mullvad.deviceName !== ""
          width: parent.width
          spacing: Style.space(5)

          PanelSeparator { foreground: root.foreground }

          DetailRow {
            width: parent.width
            visible: mullvad.features.length > 0
            label: I18n.t("label.protections")
            value: mullvad.features.join(" - ")
          }

          DetailRow {
            width: parent.width
            visible: mullvad.endpointAddress !== ""
            label: I18n.t("label.endpoint")
            value: mullvad.endpointProtocol !== ""
              ? mullvad.endpointAddress + " - " + mullvad.endpointProtocol
              : mullvad.endpointAddress
          }

          DetailRow {
            width: parent.width
            visible: mullvad.tunnelInterface !== ""
            label: I18n.t("label.interface")
            value: mullvad.tunnelInterface
          }

          DetailRow {
            width: parent.width
            visible: mullvad.deviceName !== ""
            label: I18n.t("label.device")
            value: mullvad.deviceName
          }
        }

        PanelSeparator {
          visible: root.operable
          foreground: root.foreground
        }

        RelayPicker {
          id: relayPicker
          visible: root.operable
          width: parent.width
          cities: mullvad.cities
          selectedCountry: mullvad.selectedCountry
          selectedCity: mullvad.selectedCity
          enabled: !mullvad.busy
          foreground: root.foreground
          fontFamily: root.fontFamily

          onCitySelected: function (countryCode, cityCode) {
            mullvad.setLocation(countryCode, cityCode)
          }
        }
      }
      }
    }
  }

  function heroMeta() {
    if (mullvad.availabilityState === "checkingCli") return I18n.t("status.checking")
    if (mullvad.availabilityState === "cliMissing") return I18n.t("status.notInstalled")
    if (mullvad.availabilityState === "daemonDown") return I18n.t("status.daemonDown")
    if (mullvad.availabilityState === "checkingAccount") return I18n.t("status.checkingAccount")
    if (root.needsAccount) return I18n.t("status.noAccount")
    if (root.leaking) return I18n.t("status.leaking")
    return mullvad.locationLabel !== "" ? mullvad.phrase + " - " + mullvad.locationLabel : mullvad.phrase
  }

  function ipcActionResult(started) {
    return started ? "ok" : mullvad.operationBlockReason
  }

  function exitPhrase() {
    if (!mullvad.hasLocation) return I18n.t("exit.checking")
    return I18n.t(mullvad.exitIsMullvad ? "exit.confirmed" : "exit.outside")
  }

  function submitLogin() {
    if (mullvad.busy) return
    mullvad.login(root.loginDraft)
  }

  function formatBytes(bytes) {
    return Model.formatBytes(bytes)
  }

  component MessageBlock: Text {
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    wrapMode: Text.WordWrap
  }

  component DetailRow: RowLayout {
    property string label: ""
    property string value: ""
    property bool emphasis: false

    spacing: Style.space(8)

    Text {
      text: parent.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignRight
      text: parent.value
      color: parent.emphasis ? root.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }
}
