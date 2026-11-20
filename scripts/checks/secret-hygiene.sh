#!/usr/bin/env bash
# Comprueba que el repositorio no versiona material sensible. Es determinista y
# rápido: no reemplaza al escaneo de secretos de CI, que además busca
# credenciales dentro de archivos legítimos.
. "$(dirname "$0")/../lib/common.sh"

cd "$INFRA_ROOT" || exit 1
status=0

forbidden=$(git ls-files | grep -E '(^|/)(\.env|.*\.decrypted\.yaml|.*\.agekey|.*\.tfvars|.*\.tfstate.*|.*\.tfplan)$' || true)
if [ -n "$forbidden" ]; then
  log_error "Archivos que no deben estar versionados:"
  printf '%s\n' "$forbidden" >&2
  status=1
fi

# Los secretos de producción sólo pueden estar cifrados con SOPS.
while IFS= read -r file; do
  [ -n "$file" ] || continue
  if ! grep -q 'ENC\[' "$file"; then
    log_error "$file tiene extensión .enc.yaml pero no está cifrado con SOPS"
    status=1
  fi
done <<EOF
$(git ls-files '*.enc.yaml')
EOF

# stringData en claro sólo se admite en el overlay local y en el placeholder.
plaintext=$(grep -rl 'stringData:' kubernetes/ | grep -vE 'overlays/minikube|secrets\.placeholder\.yaml' || true)
if [ -n "$plaintext" ]; then
  log_error "stringData en claro fuera del overlay local y del placeholder:"
  printf '%s\n' "$plaintext" >&2
  status=1
fi

[ "$status" -eq 0 ] || exit 1
log_info "Sin material sensible versionado"
