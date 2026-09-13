#!/usr/bin/env bash
# Verifica que el equipo puede correr el laboratorio.
set -uo pipefail

MIN_MEM_GB=4
fail=0

ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$1"; fail=1; }

echo "Herramientas:"
for tool in make curl docker kubectl kind helm k9s shellcheck; do
  if command -v "$tool" > /dev/null; then
    ok "$tool → $(command -v "$tool")"
  elif [[ "$tool" == k9s || "$tool" == shellcheck ]]; then
    warn "$tool no instalado (opcional)"
  else
    bad "$tool no instalado (ejecuta: make tools)"
  fi
done

echo "Docker:"
if docker info > /dev/null 2>&1; then
  ok "daemon accesible ($(docker info --format '{{.ServerVersion}}'))"
else
  bad "daemon no accesible (¿Docker iniciado? ¿usuario en el grupo docker?)"
fi

echo "Recursos:"
mem_gb=$(awk '/MemAvailable/ {printf "%d", $2/1024/1024}' /proc/meminfo)
if (( mem_gb >= MIN_MEM_GB )); then
  ok "memoria disponible: ${mem_gb} GB"
else
  bad "memoria disponible: ${mem_gb} GB (mínimo ${MIN_MEM_GB} GB)"
fi
ok "CPUs: $(nproc)"

exit "$fail"
