#!/usr/bin/env bash
# Instala o plasmoide Claude Usage por symlink (edições ficam ao vivo).
set -euo pipefail

ID="io.github.gpontespc.claudeusage"
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${HOME}/.local/share/plasma/plasmoids/${ID}"

chmod +x "${SRC}/contents/scripts/fetch-usage.sh"
mkdir -p "$(dirname "$DEST")"

if [ -L "$DEST" ] || [ -e "$DEST" ]; then
    rm -rf "$DEST"
fi
ln -s "$SRC" "$DEST"

echo "Instalado: $DEST -> $SRC"
echo
echo "Testar isolado:   plasmoidviewer -a ${ID}    (pacote plasma-sdk)"
echo "Adicionar ao painel: clique direito no painel > Adicionar Widgets > 'Uso do Claude'"
echo
echo "Se já estava adicionado, recarregue o shell:"
echo "  kquitapp6 plasmashell && kstart plasmashell    (ou faça logout/login)"
