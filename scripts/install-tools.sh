#!/usr/bin/env bash
# Instala las herramientas del laboratorio con versiones fijadas y checksum verificado.
# Idempotente: si la versión correcta ya está instalada, no hace nada.
set -euo pipefail

KUBECTL_VERSION="v1.37.0"
KIND_VERSION="v0.33.0"
HELM_VERSION="v4.3.0"
K9S_VERSION="v0.51.0"

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
OS="linux"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64 | arm64) ARCH="arm64" ;;
  *) echo "Arquitectura no soportada: $ARCH" >&2; exit 1 ;;
esac

mkdir -p "$INSTALL_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

has_version() { # $1=binario $2=versión esperada $3...=comando de versión
  local bin="$1" want="$2"; shift 2
  command -v "$bin" > /dev/null && "$@" 2> /dev/null | grep -q -- "$want"
}

verify() { # $1=archivo $2=sha256 esperado
  echo "$2  $1" | sha256sum -c --quiet -
}

if has_version kubectl "$KUBECTL_VERSION" kubectl version --client; then
  echo "kubectl $KUBECTL_VERSION ya instalado"
else
  url="https://dl.k8s.io/release/$KUBECTL_VERSION/bin/$OS/$ARCH/kubectl"
  curl -fsSLo "$TMP/kubectl" "$url"
  verify "$TMP/kubectl" "$(curl -fsSL "$url.sha256")"
  install -m 0755 "$TMP/kubectl" "$INSTALL_DIR/kubectl"
  echo "kubectl $KUBECTL_VERSION instalado"
fi

if has_version kind "$KIND_VERSION" kind version; then
  echo "kind $KIND_VERSION ya instalado"
else
  url="https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-$OS-$ARCH"
  curl -fsSLo "$TMP/kind" "$url"
  verify "$TMP/kind" "$(curl -fsSL "$url.sha256sum" | awk '{print $1}')"
  install -m 0755 "$TMP/kind" "$INSTALL_DIR/kind"
  echo "kind $KIND_VERSION instalado"
fi

if has_version helm "$HELM_VERSION" helm version --short; then
  echo "helm $HELM_VERSION ya instalado"
else
  file="helm-$HELM_VERSION-$OS-$ARCH.tar.gz"
  curl -fsSLo "$TMP/$file" "https://get.helm.sh/$file"
  verify "$TMP/$file" "$(curl -fsSL "https://get.helm.sh/$file.sha256sum" | awk '{print $1}')"
  tar -xzf "$TMP/$file" -C "$TMP"
  install -m 0755 "$TMP/$OS-$ARCH/helm" "$INSTALL_DIR/helm"
  echo "helm $HELM_VERSION instalado"
fi

if has_version k9s "$K9S_VERSION" k9s version -s; then
  echo "k9s $K9S_VERSION ya instalado"
else
  file="k9s_Linux_$ARCH.tar.gz"
  base="https://github.com/derailed/k9s/releases/download/$K9S_VERSION"
  curl -fsSLo "$TMP/$file" "$base/$file"
  verify "$TMP/$file" "$(curl -fsSL "$base/checksums.sha256" | awk -v f="$file" '$2==f {print $1}')"
  tar -xzf "$TMP/$file" -C "$TMP" k9s
  install -m 0755 "$TMP/k9s" "$INSTALL_DIR/k9s"
  echo "k9s $K9S_VERSION instalado"
fi

case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) echo "Aviso: agrega $INSTALL_DIR a tu PATH" >&2 ;;
esac
