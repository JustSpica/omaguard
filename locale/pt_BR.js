// Brazilian Portuguese catalogue.
//
// Every key must match locale/en_US.js exactly — test/i18n.test.js enforces it.
// A missing key would fall back to English silently, which is correct behaviour
// but not something to discover in production.

.pragma library

var catalog = {
  "number.decimal": ",",

  "status.connected": "Conectado",
  "status.connectedLocating": "Conectado, localizando",
  "status.connecting": "Conectando",
  "status.disconnecting": "Desconectando",
  "status.disconnected": "Desconectado",
  "status.tunnelError": "Erro no túnel",

  "status.checking": "Verificando",
  "status.notInstalled": "Não instalado",
  "status.daemonDown": "Daemon fora do ar",
  "status.checkingAccount": "Verificando conta",
  "status.noAccount": "Sem conta",
  "status.leaking": "Tráfego fora do túnel",

  "label.state": "Estado",
  "label.location": "Localização",
  "label.server": "Servidor",
  "label.exit": "Saída",
  "label.account": "Conta",
  "label.device": "Dispositivo",
  "label.protections": "Proteções",
  "label.endpoint": "Endpoint",
  "label.interface": "Interface",
  "label.traffic": "Tráfego",
  "label.lockdown": "LOCKDOWN",

  "exit.confirmed": "Confirmada pela Mullvad",
  "exit.outside": "Fora do túnel",
  "exit.checking": "Verificando",

  "action.connecting": "Conectando…",
  "action.disconnecting": "Desconectando…",
  "action.reconnecting": "Reconectando…",
  "action.switchingServer": "Trocando servidor…",
  "action.signingIn": "Entrando…",
  "action.connect": "Conectar",
  "action.disconnect": "Desconectar",

  "account.title": "CONTA",
  "account.prompt": "Entre com o número da conta Mullvad (16 dígitos).",
  "account.placeholder": "0000 0000 0000 0000",
  "account.submit": "Entrar",
  "account.daysLeft": { "one": "{count} dia restante", "other": "{count} dias restantes" },

  "server.title": "SERVIDORES",
  "server.search": "Buscar país ou cidade",
  "server.pending": "A lista de servidores ainda não chegou.",
  "server.noMatch": "Nenhuma cidade para “{query}”.",

  "setup.cliMissing": "O CLI do Mullvad não está instalado.\nsudo pacman -S mullvad-vpn-daemon",
  "setup.daemonDown": "O daemon do Mullvad não responde.\nsudo systemctl start mullvad-daemon",

  "error.unreadableEvent": "Evento ilegível do daemon",
  "error.unreadableState": "Estado ilegível",
  "error.unreadableAccount": "Resposta de conta ilegível",
  "error.noDaemonResponse": "Sem resposta do daemon",
  "error.daemonUnreachable": "O daemon do Mullvad não responde",
  "error.daemonStreamLost": "Conexão com o daemon foi interrompida",
  "error.relayListUnavailable": "Lista de servidores indisponível",
  "error.relayListUnreadable": "Lista de servidores ilegível",
  "error.actionFailed": "A ação falhou",
  "error.accountDigits": "O número da conta tem 16 dígitos",
  "error.accountMissing": "Conta inexistente",
  "error.accountInvalid": "Número de conta inválido",
  "error.deviceLimit": "Limite de dispositivos atingido",
  "error.signInFailed": "Não foi possível entrar na conta",
  "error.timeoutAction": "A ação não respondeu a tempo",
  "error.timeoutDaemon": "O daemon do Mullvad não respondeu a tempo",
  "error.timeoutAccount": "A consulta da conta não respondeu a tempo",
  "error.timeoutRelays": "A lista de servidores não respondeu a tempo",
  "error.timeoutLogin": "O login não respondeu a tempo",

  "feature.QuantumResistance": "Resistente a quântico",
  "feature.Daita": "DAITA",
  "feature.Multihop": "Multihop",
  "feature.BridgeMode": "Bridge",
  "feature.SplitTunneling": "Split tunneling",
  "feature.LockdownMode": "Lockdown",
  "feature.LanSharing": "LAN liberada",
  "feature.DnsContentBlockers": "Bloqueio de conteúdo",
  "feature.CustomDns": "DNS personalizado",
  "feature.ServerIpOverride": "IP de servidor forçado",
  "feature.CustomMtu": "MTU personalizada",
  "feature.Udp2Tcp": "UDP sobre TCP",
  "feature.Shadowsocks": "Shadowsocks",
  "feature.QuicObfuscation": "Ofuscação QUIC"
}
