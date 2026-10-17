#!/usr/bin/env bash
# Respalda la(s) llave(s) de Sealed Secrets del cluster en:
#   1. ~/.sa-p9/sealed-secrets/<nombre>.crt|.key   (copia local, fuera del repo)
#   2. s3://sa-p9-llaves/sealed-secrets/          (MinIO, fuera del cluster)
# Idempotente. Debe correrse tambien cuando el controlador rota su llave
# (cada 30 dias por defecto): SealedSecrets nuevos se cifran con la llave
# mas reciente, y sin ella no se podrian descifrar tras una reconstruccion.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cargar_credenciales

mkdir -p "$LLAVES_DIR" && chmod 700 "$LLAVES_DIR"
N=0
for s in $(kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o name); do
  n=$(basename "$s")
  kubectl get "$s" -n kube-system -o jsonpath='{.data.tls\.crt}' | base64 -d > "$LLAVES_DIR/$n.crt"
  kubectl get "$s" -n kube-system -o jsonpath='{.data.tls\.key}' | base64 -d > "$LLAVES_DIR/$n.key"
  N=$((N+1))
done
chmod 600 "$LLAVES_DIR"/*
[ "$N" -gt 0 ] || { echo "No hay llaves de Sealed Secrets en kube-system"; exit 1; }

s3 s3 cp "$LLAVES_DIR/" "s3://$BUCKET_LLAVES/sealed-secrets/" --recursive --only-show-errors
echo "$(ts) Llaves respaldadas ($N): $(ls "$LLAVES_DIR" | tr '\n' ' ')-> s3://$BUCKET_LLAVES/sealed-secrets/"
