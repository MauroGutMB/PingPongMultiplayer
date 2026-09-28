#!/usr/bin/env bash
#
# Toggles LAN access to the PingPong server running in WSL2, so a phone on
# the same Wi-Fi can reach it:
#   1. Opens/closes a Windows Firewall rule for the port.
#   2. Adds/removes a `netsh portproxy` forwarding <Windows LAN IP>:PORT to
#      the current WSL2 IP (which changes every WSL restart).
#   3. Publishes the resulting ws:// URL to a private GitHub gist, so the
#      client app can fetch it automatically instead of the user typing an
#      IP by hand.
#
# Usage:
#   ./scripts/toggle-lan-access.sh          # flips current state
#   ./scripts/toggle-lan-access.sh on
#   ./scripts/toggle-lan-access.sh off
#   ./scripts/toggle-lan-access.sh status
#
# Requires: WSL2, gh (authenticated, "gist" scope), powershell.exe reachable,
# and an elevated (Administrator) prompt will pop up on Windows for the
# firewall/portproxy step — that's expected, accept it.
set -euo pipefail

PORT="${PORT:-8080}"
RULE_NAME="PingPong Server"
STATE_DIR="$HOME/.pingpong-toggle"
STATE_FILE="$STATE_DIR/state.env"
GIST_FILENAME="pingpong_server_url.txt"
GIST_DESCRIPTION="PingPong Multiplayer - dev server URL"
CONTENT_FILE="$STATE_DIR/$GIST_FILENAME"

mkdir -p "$STATE_DIR"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Erro: '$1' não encontrado no PATH." >&2
    exit 1
  }
}

require powershell.exe
require gh
require wslpath

if ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "Erro: este script assume que está rodando dentro do WSL." >&2
  exit 1
fi

# shellcheck disable=SC1090
[[ -f "$STATE_FILE" ]] && source "$STATE_FILE"
ENABLED="${ENABLED:-false}"
GIST_ID="${GIST_ID:-}"

save_state() {
  cat >"$STATE_FILE" <<EOF
ENABLED=$ENABLED
GIST_ID=$GIST_ID
EOF
}

wsl_ip() {
  ip -4 addr show eth0 | awk '/inet /{print $2}' | cut -d/ -f1
}

windows_lan_ip() {
  powershell.exe -NoProfile -Command '(Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq "Up" -and $_.IPv4DefaultGateway } | Select-Object -First 1 -ExpandProperty IPv4Address).IPAddress' | tr -d '\r\n'
}

firewall_rule_exists() {
  powershell.exe -NoProfile -Command "if (Get-NetFirewallRule -DisplayName '$RULE_NAME' -ErrorAction SilentlyContinue) { Write-Output yes } else { Write-Output no }" | tr -d '\r\n'
}

# netsh writes its own failures to stdout instead of a terminating error, so
# piping it through `| Out-Null` (as the elevated block does) silently
# swallows them — the script would report success even when the portproxy
# rule was never actually created. Check the real table instead of trusting
# the elevated block's exit status.
portproxy_rule_matches() {
  local expected_addr="$1"
  powershell.exe -NoProfile -Command "netsh interface portproxy show v4tov4" \
    | tr -d '\r' \
    | awk -v port="$PORT" -v addr="$expected_addr" \
        '$1=="0.0.0.0" && $2==port && $3==addr && $4==port { found=1 } END { exit !found }'
}

run_elevated_ps1() {
  local tmp_ps1 win_path
  tmp_ps1="$(mktemp --suffix=.ps1)"
  cat >"$tmp_ps1"
  win_path="$(wslpath -w "$tmp_ps1")"
  powershell.exe -NoProfile -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$win_path'"
  rm -f "$tmp_ps1"
}

gist_raw_url() {
  local owner
  owner="$(gh api "gists/$GIST_ID" --jq '.owner.login')"
  echo "https://gist.githubusercontent.com/$owner/$GIST_ID/raw/$GIST_FILENAME"
}

publish_gist() {
  local content="$1"
  printf '%s\n' "$content" >"$CONTENT_FILE"
  if [[ -z "$GIST_ID" ]]; then
    local url
    url="$(gh gist create "$CONTENT_FILE" -d "$GIST_DESCRIPTION")"
    GIST_ID="${url##*/}"
    echo "Gist criado: $url"
  else
    gh gist edit "$GIST_ID" --filename "$GIST_FILENAME" "$CONTENT_FILE" >/dev/null
    echo "Gist atualizado: https://gist.github.com/$GIST_ID"
  fi
}

do_enable() {
  local wsl_addr win_addr
  wsl_addr="$(wsl_ip)"
  win_addr="$(windows_lan_ip)"

  if [[ -z "$wsl_addr" || -z "$win_addr" ]]; then
    echo "Erro: não consegui descobrir os IPs (WSL='$wsl_addr' Windows='$win_addr')." >&2
    exit 1
  fi

  echo "Habilitando: Windows $win_addr:$PORT -> WSL $wsl_addr:$PORT"
  echo "Uma janela do Windows vai pedir permissão de administrador — aceite."

  run_elevated_ps1 <<PSEOF
\$ErrorActionPreference = 'Stop'
Get-NetFirewallRule -DisplayName '$RULE_NAME' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName '$RULE_NAME' -Direction Inbound -LocalPort $PORT -Protocol TCP -Action Allow | Out-Null
netsh interface portproxy delete v4tov4 listenport=$PORT listenaddress=0.0.0.0 | Out-Null
netsh interface portproxy add v4tov4 listenport=$PORT listenaddress=0.0.0.0 connectport=$PORT connectaddress=$wsl_addr | Out-Null
PSEOF

  if [[ "$(firewall_rule_exists)" != "yes" ]]; then
    echo "Erro: a regra de firewall não foi criada (permissão negada na janela do UAC?)." >&2
    exit 1
  fi

  if ! portproxy_rule_matches "$wsl_addr"; then
    echo "Erro: o firewall foi liberado, mas o portproxy não ficou ativo." >&2
    echo "O 'netsh' roda dentro do processo elevado e falha silenciosamente se algo der errado," >&2
    echo "então essa verificação pega o caso em que a janela do UAC pareceu ter dado certo mas não deu." >&2
    echo "Tente abrir um PowerShell 'Executar como administrador' manualmente e rodar:" >&2
    echo "  netsh interface portproxy add v4tov4 listenport=$PORT listenaddress=0.0.0.0 connectport=$PORT connectaddress=$wsl_addr" >&2
    exit 1
  fi

  local url="ws://$win_addr:$PORT"
  publish_gist "$url"

  ENABLED=true
  save_state

  echo
  echo "Ativo."
  echo "URL do servidor: $url"
  echo "URL raw do gist (pro app buscar automaticamente): $(gist_raw_url)"
}

do_disable() {
  echo "Desabilitando regra de firewall e portproxy..."
  echo "Uma janela do Windows vai pedir permissão de administrador — aceite."

  run_elevated_ps1 <<PSEOF
\$ErrorActionPreference = 'SilentlyContinue'
Get-NetFirewallRule -DisplayName '$RULE_NAME' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
netsh interface portproxy delete v4tov4 listenport=$PORT listenaddress=0.0.0.0 | Out-Null
PSEOF

  if [[ -n "$GIST_ID" ]]; then
    publish_gist "offline"
  fi

  ENABLED=false
  save_state

  echo "Desativado."
}

show_status() {
  echo "Habilitado: $ENABLED"
  echo "Porta: $PORT"
  if [[ -n "$GIST_ID" ]]; then
    echo "Gist: https://gist.github.com/$GIST_ID"
    echo "Raw:  $(gist_raw_url)"
  else
    echo "Gist: (ainda não criado)"
  fi
  echo "Regra de firewall presente: $(firewall_rule_exists)"
  if portproxy_rule_matches "$(wsl_ip)"; then
    echo "Portproxy ativo e apontando para o WSL atual: sim"
  else
    echo "Portproxy ativo e apontando para o WSL atual: não"
  fi
}

case "${1:-toggle}" in
  on) do_enable ;;
  off) do_disable ;;
  status) show_status ;;
  toggle)
    if [[ "$ENABLED" == "true" ]]; then
      do_disable
    else
      do_enable
    fi
    ;;
  *)
    echo "Uso: $0 [on|off|status|toggle]" >&2
    exit 1
    ;;
esac
