import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "spica.omaguard"
  ipcTarget: "spica.omaguard"
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
  readonly property bool needsAccount: mullvad.cliInstalled && mullvad.accountResolved && !mullvad.loggedIn
  readonly property bool operable: mullvad.cliInstalled && mullvad.loggedIn

  readonly property color barIconColor: {
    if (leaking) return root.urgent
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
    function connect(): string { mullvad.connect(); return "ok" }
    function disconnect(): string { mullvad.disconnect(); return "ok" }
    function toggleVpn(): string { mullvad.toggleConnection(); return "ok" }
    function refresh(): string { mullvad.refresh(); return "ok" }
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
    tooltipText: mullvad.cliInstalled ? mullvad.phrase : "Mullvad não instalado"

    iconComponent: Component {
      Item {
        MullvadIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.barIconColor
          badgeColor: root.urgent
          filled: mullvad.connected
          crossed: !mullvad.connected && !root.needsAccount
          warning: root.leaking || root.needsAccount
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

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

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
            detail: mullvad.lockdownMode ? "LOCKDOWN" : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: mullvad.connected ? 1.0 : 0.5

            iconComponent: Component {
              MullvadIcon {
                iconSize: Style.font.display
                color: root.leaking ? root.urgent : root.foreground
                badgeColor: root.urgent
                filled: mullvad.connected
                crossed: !mullvad.connected && !root.needsAccount
                warning: root.leaking || root.needsAccount
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
                  text: mullvad.connected ? "Desconectar" : "Conectar"
                  fontFamily: hero.fontFamily
                }
              }
            }
          }
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
          visible: mullvad.cliResolved && !mullvad.cliInstalled
          width: parent.width
          text: "O CLI do Mullvad não está instalado.\nsudo pacman -S mullvad-vpn-daemon"
        }

        MessageBlock {
          visible: mullvad.cliInstalled && !mullvad.daemonReachable
          width: parent.width
          text: "O daemon do Mullvad não responde.\nsudo systemctl start mullvad-daemon"
        }

        // --- login -----------------------------------------------------------

        Column {
          visible: root.needsAccount
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "CONTA"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            text: "Entre com o número da conta Mullvad (16 dígitos)."
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
              placeholderText: "0000 0000 0000 0000"
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
              text: "Entrar"
              enabled: !mullvad.busy && root.loginDraft.replace(/\D/g, "").length === 16
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.submitLogin()
            }
          }
        }

        // --- connection state ------------------------------------------------

        Column {
          visible: root.operable
          width: parent.width
          spacing: Style.space(6)

          PanelSeparator { foreground: root.foreground }

          DetailRow {
            width: parent.width
            label: "Estado"
            value: mullvad.phrase
          }

          DetailRow {
            width: parent.width
            visible: mullvad.locationLabel !== ""
            label: "Localização"
            value: mullvad.locationLabel
          }

          DetailRow {
            width: parent.width
            visible: mullvad.hostname !== ""
            label: "Servidor"
            value: mullvad.hostname
          }

          DetailRow {
            width: parent.width
            visible: mullvad.phase === "connected"
            label: "Saída"
            value: root.exitPhrase()
            emphasis: root.leaking
          }

          DetailRow {
            width: parent.width
            visible: mullvad.daysLeft >= 0
            label: "Conta"
            value: mullvad.daysLeft + (mullvad.daysLeft === 1 ? " dia restante" : " dias restantes")
            emphasis: mullvad.daysLeft <= 7
          }

          DetailRow {
            width: parent.width
            visible: mullvad.deviceName !== ""
            label: "Dispositivo"
            value: mullvad.deviceName
          }

          DetailRow {
            width: parent.width
            visible: mullvad.features.length > 0
            label: "Proteções"
            value: mullvad.features.join(" · ")
          }

          DetailRow {
            width: parent.width
            visible: mullvad.endpointAddress !== ""
            label: "Endpoint"
            value: mullvad.endpointProtocol !== ""
              ? mullvad.endpointAddress + " · " + mullvad.endpointProtocol
              : mullvad.endpointAddress
          }

          DetailRow {
            width: parent.width
            visible: mullvad.tunnelInterface !== ""
            label: "Interface"
            value: mullvad.tunnelInterface
          }

          DetailRow {
            width: parent.width
            visible: mullvad.rxBytes >= 0
            label: "Tráfego"
            value: "↓ " + root.formatBytes(mullvad.rxBytes) + "   ↑ " + root.formatBytes(mullvad.txBytes)
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

  function heroMeta() {
    if (!mullvad.cliResolved) return "Verificando"
    if (!mullvad.cliInstalled) return "Não instalado"
    if (!mullvad.daemonReachable) return "Daemon fora do ar"
    if (root.needsAccount) return "Sem conta"
    if (root.leaking) return "Tráfego fora do túnel"
    return mullvad.locationLabel !== "" ? mullvad.phrase + " · " + mullvad.locationLabel : mullvad.phrase
  }

  function exitPhrase() {
    if (!mullvad.hasLocation) return "Verificando"
    return mullvad.exitIsMullvad ? "Confirmada pela Mullvad" : "Fora do túnel"
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
