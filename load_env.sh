#!/bin/bash
# Archivo: load_env.sh

set -u
set -a 

# Usamos BASH_SOURCE para saber dónde está ESTE archivo exactamente
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
  source "$SCRIPT_DIR/.env"
else
  echo "Error: No se encontró el archivo .env en $SCRIPT_DIR"
  exit 1
fi

set +a