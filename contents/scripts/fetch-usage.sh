#!/usr/bin/env bash
#
# Busca os limites de uso do Claude na API OAuth da Anthropic e devolve um
# JSON normalizado para o plasmoide consumir. Nunca sai nada além de JSON no
# stdout (mesmo em erro), para o parse no QML ser sempre seguro.
#
# Fonte de dados: https://api.anthropic.com/api/oauth/usage
# Token: ~/.claude/.credentials.json (.claudeAiOauth.accessToken), escrito
# pelo CLI `claude`. O token só é enviado para a Anthropic.

set -uo pipefail

CRED="${HOME}/.claude/.credentials.json"
CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}"
CACHE="${CACHE_DIR}/claude-usage.json"
TTL=55  # segundos; o plasmoide poll a cada 60s, então evita bater 2x na API

# Emite {"ok":false,"error":"..."} com a string devidamente escapada e sai 0.
err() {
    printf '{"ok":false,"error":%s}\n' "$(printf '%s' "$1" | jq -Rsa .)"
    exit 0
}

command -v jq   >/dev/null 2>&1 || { printf '{"ok":false,"error":"jq nao instalado"}\n';   exit 0; }
command -v curl >/dev/null 2>&1 || { printf '{"ok":false,"error":"curl nao instalado"}\n'; exit 0; }
[ -r "$CRED" ] || err "credenciais nao encontradas (~/.claude/.credentials.json)"

# Cache: se ainda fresco, devolve e sai.
if [ -f "$CACHE" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))
    if [ "$age" -ge 0 ] && [ "$age" -lt "$TTL" ]; then
        cat "$CACHE"
        exit 0
    fi
fi

TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' "$CRED")
[ -n "$TOKEN" ] || err "token ausente no arquivo de credenciais"

resp=$(curl -s -m 15 -w $'\n%{http_code}' \
    https://api.anthropic.com/api/oauth/usage \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Content-Type: application/json") || err "falha de rede ao consultar a API"

code=$(printf '%s' "$resp" | tail -n1)
body=$(printf '%s' "$resp" | sed '$d')

case "$code" in
    401|403) err "token expirado — rode o CLI 'claude' para renovar" ;;
    200)     ;;
    *)       err "HTTP ${code}" ;;
esac

out=$(printf '%s' "$body" | jq -c '{
    ok: true,
    five_hour: {
        pct:       (.five_hour.utilization // 0),
        resets_at: (.five_hour.resets_at   // "")
    },
    seven_day: {
        pct:       (.seven_day.utilization // 0),
        resets_at: (.seven_day.resets_at   // "")
    },
    extra: {
        enabled:  (.extra_usage.is_enabled  // false),
        used:     (.extra_usage.used_credits // 0),
        currency: (.extra_usage.currency     // "")
    }
}' 2>/dev/null) || err "resposta da API em formato inesperado"

mkdir -p "$CACHE_DIR"
printf '%s\n' "$out" | tee "$CACHE"
