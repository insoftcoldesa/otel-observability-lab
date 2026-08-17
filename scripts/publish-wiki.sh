#!/usr/bin/env bash
# Publica docs/wiki/ en el Wiki de GitHub del repositorio.
#
#   bash scripts/publish-wiki.sh
#
# Requisitos, en este orden:
#   1. El repo NO puede ser privado en el plan gratuito de GitHub: los wikis solo
#      existen en repos publicos (o privados de un plan de pago). Verificalo con
#      `gh api repos/<owner>/<repo> --jq .has_wiki`.
#   2. El wiki debe estar habilitado e **inicializado**: hay que crear la primera
#      pagina una vez desde la web (pestana Wiki -> "Create the first page").
#      Hasta que exista esa pagina, el repositorio <repo>.wiki.git no existe.
#
# Mientras eso no se cumpla, docs/wiki/ se lee perfectamente en GitHub y no se
# pierde nada: este script solo copia el mismo contenido al Wiki.
set -euo pipefail

REPO="${WIKI_REPO:-insoftcoldesa/otel-observability-lab}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORIGEN="$ROOT/docs/wiki"
TRABAJO="$(mktemp -d)"
trap 'rm -rf "$TRABAJO"' EXIT

echo "==> clonando el wiki de $REPO"
if ! git clone -q "https://github.com/$REPO.wiki.git" "$TRABAJO/wiki" 2>/dev/null; then
  cat >&2 <<EOF
!! No se pudo clonar https://github.com/$REPO.wiki.git

   Causas posibles:
   - El repo es privado y el plan no incluye wikis  -> hazlo publico, o
   - El wiki nunca se inicializo                    -> crea la primera pagina
     desde la pestana Wiki en la web y vuelve a correr esto.

   Entre tanto el contenido esta en docs/wiki/ y se lee bien en GitHub.
EOF
  exit 1
fi

echo "==> copiando paginas"
# En el Wiki los enlaces van sin extension: [[Pagina]] o [texto](Pagina).
for archivo in "$ORIGEN"/*.md; do
  nombre="$(basename "$archivo")"
  sed -E 's/\(([A-Za-z0-9._-]+)\.md\)/(\1)/g; s/\(\.\.\/[^)]*\)/(Home)/g' \
    "$archivo" > "$TRABAJO/wiki/$nombre"
done

cd "$TRABAJO/wiki"
if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain)" ]; then
  echo "==> el wiki ya esta al dia"
  exit 0
fi

git add -A
git commit -q -m "docs: sincroniza el wiki desde docs/wiki/"
git push -q origin HEAD
echo "==> publicado en https://github.com/$REPO/wiki"
