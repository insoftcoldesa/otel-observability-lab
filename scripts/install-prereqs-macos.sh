#!/usr/bin/env bash
# Laboratorio OTel - Prerequisitos macOS Apple Silicon. Idempotente.
# v2: corrige Terraform (ya no esta en homebrew-core desde el cambio de licencia BUSL)
set -uo pipefail
G=$'\033[0;32m'; Y=$'\033[0;33m'; B=$'\033[0;34m'; N=$'\033[0m'
say(){ printf "\n${B}==> %s${N}\n" "$1"; }; ok(){ printf "${G}  ok: %s${N}\n" "$1"; }
skip(){ printf "${Y}  ya instalado: %s${N}\n" "$1"; }

say "Homebrew"
command -v brew >/dev/null 2>&1 || { /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; eval "$(/opt/homebrew/bin/brew shellenv)"; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"; }
skip "Homebrew"
export HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1

say "Formulas"
for f in git jq make python@3.12 uv k6 awscli node; do
  brew list --formula "$f" >/dev/null 2>&1 && skip "$f" || { brew install "$f" && ok "$f"; }
done

say "Terraform (tap de HashiCorp)"
# terraform salio de homebrew-core cuando HashiCorp cambio a licencia BUSL.
# La via soportada es el tap oficial:
if command -v terraform >/dev/null 2>&1; then skip "terraform"
else
  brew tap hashicorp/tap
  brew install hashicorp/tap/terraform && ok "terraform"
fi
# Alternativa 100% open source si el tap diera problemas:
#   brew install opentofu   # y usar 'tofu' en lugar de 'terraform'

say "Casks"
[ -d "/Applications/Docker.app" ] && skip "Docker Desktop" || { brew install --cask docker && ok "Docker Desktop"; }
command -v gcloud >/dev/null 2>&1 && skip "gcloud" || { brew install --cask gcloud-cli && ok "gcloud"; }

say "Claude Code"
command -v claude >/dev/null 2>&1 && skip "claude code" || { npm install -g @anthropic-ai/claude-code && ok "claude code"; }

say "PATH de gcloud (zsh)"
if ! grep -q "google-cloud-sdk/path.zsh.inc" "$HOME/.zshrc" 2>/dev/null; then
  {
    echo ''
    echo '# Google Cloud SDK'
    echo 'source "/opt/homebrew/share/google-cloud-sdk/path.zsh.inc"'
    echo 'source "/opt/homebrew/share/google-cloud-sdk/completion.zsh.inc"'
  } >> "$HOME/.zshrc"
  ok "gcloud anadido a ~/.zshrc"
else skip "PATH de gcloud"; fi

say "Pasos manuales"
cat <<'EOT'
  1. Docker Desktop > Settings > Resources > Memory: subir de 7 GB a 8-10 GB. Apply & Restart.
  2. Reinicia la terminal:  exec zsh
  3. Python: el sistema tiene 3.14. NO lo cambies. El lab usa uv, que fija 3.12 por proyecto:
       cd services/service-a && uv venv --python 3.12
  4. Nube (hazlo HOY, la verificacion de facturacion tarda):
       gcloud auth login && gcloud auth application-default login
       aws configure
  5. Vuelve a correr:  bash scripts/preflight-local.sh
EOT
printf "\n${G}Listo.${N}\n"
