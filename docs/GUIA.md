# Guía de estudio — local-k8s-lab

Explicación archivo por archivo de qué hace cada pieza, por qué existe y
qué conceptos hay detrás. Léela con el archivo abierto al lado.

## Mapa mental

```
Tú ──► make <objetivo> ──► scripts/*.sh ──► herramientas (kind, kubectl, helm)
                     │
                     ├─► kind/cluster.yaml ──► 3 contenedores Docker = 3 "nodos" Kubernetes
                     │
                     └─► helm + values/onlineboutique.yaml ──► 12 Deployments en el namespace boutique
GitHub ──► .github/workflows/ci.yaml ──► repite exactamente lo mismo en una máquina limpia
```

La idea central: **una sola forma de hacer las cosas**, igual en tu PC y en
CI. Si funciona en CI desde cero, cualquiera puede reproducirlo.

---

## `Makefile`

**Qué es:** un archivo de `make`, una herramienta de 1976 que sigue siendo el
estándar para dar "botones" a un repo. Cada bloque `objetivo: ## descripción`
es un comando (`make up`, `make deploy`...).

**Líneas clave:**

| Línea | Qué hace | Concepto |
|---|---|---|
| `SHELL := /usr/bin/env bash` y `.SHELLFLAGS := -euo pipefail -c` | Cada receta corre en bash en modo estricto: se detiene ante el primer error (`-e`), falla si usas una variable no definida (`-u`) y si falla cualquier comando de un pipe (`pipefail`) | *Fail fast*: un error silencioso en automatización es peor que uno ruidoso |
| `CLUSTER ?= boutique` | Variable con valor por defecto que puedes sobrescribir: `make up CLUSTER=otro` | Configuración por parámetros, no editando código |
| `.PHONY: up` | Le dice a make que `up` no es un archivo sino una acción | Sin esto, si existiera un archivo llamado `up`, make no haría nada |
| `help:` con `awk` | Lee el propio Makefile y lista los comentarios `##` | Documentación que no se desactualiza |
| `up:` con `kind get clusters \| grep -qx` | Solo crea el cluster si no existe | **Idempotencia**: ejecutar dos veces da el mismo resultado que una |
| `helm upgrade --install ... --wait` | Instala si no existe, actualiza si existe, y espera a que los pods estén listos | Idempotencia otra vez; `--wait` convierte "se aplicó" en "está funcionando" |
| `port-forward --address 127.0.0.1` | Túnel desde tu PC hasta el Service `frontend` dentro del cluster | Los Services de Kubernetes no son accesibles desde fuera sin Ingress/LoadBalancer/túnel |

**Ejercicio:** agrega un objetivo `make logs` que muestre los logs del
frontend (`kubectl logs deploy/frontend -f`).

---

## `kind/cluster.yaml`

**Qué es:** la definición declarativa del cluster. `kind` (Kubernetes IN
Docker) crea cada nodo como un contenedor Docker que dentro corre
`kubelet`, `containerd`, etc.

- `role: control-plane`: el nodo "cerebro": API server, scheduler, etcd.
- `role: worker` × 2: donde corren tus aplicaciones.
- `labels: lab.role`: etiquetas en los nodos; más adelante sirven para
  decidir dónde se programan los pods (`nodeSelector`, afinidad).

**Concepto:** *declarativo vs imperativo*. No escribimos "crea un nodo, luego
otro"; describimos el estado deseado y la herramienta lo construye.

**Ejercicio:** `docker ps` y verás los 3 contenedores `boutique-*`.
`kubectl get nodes -L lab.role` muestra las etiquetas.

---

## `values/onlineboutique.yaml`

**Qué es:** los *overrides* del chart de Helm. Un **chart** es un paquete de
plantillas de manifiestos de Kubernetes; los **values** rellenan esas
plantillas. No copiamos los ~1000 líneas de YAML de la app: solo
versionamos lo que cambiamos.

- `images.repository`: corrige el registro de imágenes (ver "Incidentes").
- `frontend.externalService: false`: el chart crearía un Service tipo
  `LoadBalancer`, que en kind se queda `<pending>` para siempre.
- `loadGenerator.create: true`: un pod que simula usuarios comprando, para
  que haya tráfico y métricas.

**Ejercicios:**
- `helm show values oci://us-docker.pkg.dev/online-boutique-ci/charts/onlineboutique --version 0.10.6` para ver todo lo configurable.
- `helm template ... -f values/onlineboutique.yaml | less` para ver el YAML final que se aplica.

---

## `scripts/install-tools.sh`

**Qué es:** instala `kubectl`, `kind`, `helm` y `k9s` en `~/.local/bin`.

- **Versiones fijadas** (`KUBECTL_VERSION="v1.37.0"`...): si cada quien usa
  "la última", el entorno cambia sin que nadie lo decida.
- **Checksum SHA-256** (`verify`): compara el hash del binario descargado con
  el publicado por el proyecto. Protege contra descargas corruptas o
  alteradas (*supply chain*).
- **Idempotente** (`has_version`): si ya tienes la versión correcta, no
  descarga nada.
- `trap 'rm -rf "$TMP"' EXIT`: limpia archivos temporales pase lo que pase.

**Ejercicio:** cambia `K9S_VERSION` a una versión inexistente y observa cómo
falla (y por qué `set -euo pipefail` hace que falle en vez de seguir).

---

## `scripts/doctor.sh`

**Qué es:** chequeo previo del entorno: herramientas, Docker y memoria.

**Concepto:** *preflight checks*. Es mejor fallar en 1 segundo con
"Docker no está iniciado" que a los 5 minutos con un error críptico de kind.
Devuelve código de salida `1` si algo obligatorio falta, así CI se detiene.

---

## `scripts/smoke-test.sh`

**Qué es:** prueba de humo: abre un túnel temporal y reintenta hasta que el
frontend responda HTTP 200.

- `&` + `pf_pid=$!`: lanza el port-forward en segundo plano y guarda su PID.
- `trap 'kill "$pf_pid"' EXIT`: cierra el túnel al terminar, aunque falle.
- Bucle con reintentos: los sistemas distribuidos tardan en estar listos;
  un solo intento daría falsos negativos.

**Concepto:** *smoke test* = la prueba mínima que dice "está vivo". No
prueba la lógica de negocio, prueba que el despliegue sirve.

---

## `.github/workflows/ci.yaml`

**Qué es:** pipeline de GitHub Actions que corre en cada push y PR.

- `on: pull_request / push / workflow_dispatch`: disparadores (el último
  permite lanzarlo a mano).
- `permissions: contents: read`: **mínimo privilegio** para el token del
  workflow.
- `concurrency ... cancel-in-progress`: si haces dos push seguidos, cancela
  el run viejo.
- Job `lint` → job `e2e` (`needs: lint`): no gastes 3 minutos levantando un
  cluster si el código ni siquiera pasa el lint.
- `if: failure()`: solo si algo falló, imprime pods y eventos para
  diagnosticar sin tener acceso a la máquina.
- `if: always()`: destruye el cluster siempre.

**Concepto:** el e2e demuestra el criterio de terminado de P0 — "desde un
clon limpio, `make up && make deploy` funciona" — en cada cambio.

---

## `.gitignore`

Evita subir logs, `.env` (secretos) y kubeconfigs (credenciales del cluster).

---

## Incidentes de este proyecto (léelos, son lo más valioso)

### 1. `ImagePullBackOff` en 10 de 12 pods
- **Síntoma:** `helm --wait` agotó los 10 minutos; pods en `ImagePullBackOff`.
- **Diagnóstico:**
  1. `kubectl get events` → `...adservice:v0.10.6: not found`.
  2. ¿Es la red? `docker exec boutique-worker curl https://us-central1-docker.pkg.dev/v2/` → `401` (hay red; 401 es normal sin login).
  3. ¿Existe el tag? `curl .../v2/google-samples/microservices-demo/frontend/tags/list` → llega hasta `v0.10.5`.
  4. El manifiesto oficial del release usa `online-boutique-ci/microservices-demo`.
- **Causa:** el default del chart apunta a un registro donde ese release no se publicó.
- **Arreglo:** `images.repository` en los values.
- **Lección:** separa hipótesis (red / credenciales / tag inexistente) y descártalas una por una con evidencia.

### 2. Puerto 8080 ocupado
- **Síntoma:** `port-forward` solo mostró `Forwarding from [::1]:8080`.
- **Diagnóstico:** `ss -ltnp | grep 8080` → otro contenedor tenía `127.0.0.1:8080`.
- **Arreglo:** puerto 8090 por defecto y `--address 127.0.0.1` para fallar explícitamente si está ocupado.
- **Lección:** lee lo que *falta* en la salida, no solo lo que aparece.

---

## Comandos para explorar el cluster

```bash
kubectl get nodes -o wide                  # los 3 nodos
kubectl -n boutique get deploy,pods,svc    # la app
kubectl -n boutique describe pod <pod>     # detalle + eventos
kubectl -n boutique logs deploy/frontend   # logs
k9s                                        # interfaz de terminal
helm -n boutique list                      # releases de Helm
helm -n boutique get values onlineboutique # values aplicados
```
