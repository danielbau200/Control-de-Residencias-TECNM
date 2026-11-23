#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$SCRIPT_DIR}"
cd "$PROJECT_DIR" || exit 1

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  . "$PROJECT_DIR/.env"
  set +a
fi

echo "Iniciando Sistema de Residencias de Ingeniería Industrial..."

# 1. Asegurar motor PostgreSQL 16 activo
DATA_DIR="${PGDATA:-$HOME/.postgres_data}"
BIN_DIR="${PGBIN:-$HOME/.local/opt/postgresql16/usr/lib/postgresql/16/bin}"
if [ -d "$DATA_DIR" ] && [ -x "$BIN_DIR/pg_ctl" ]; then
  if ! pg_isready -h "${PGHOST:-127.0.0.1}" -p "${PGPORT:-5432}" -U postgres >/dev/null 2>&1; then
    echo "Iniciando motor PostgreSQL 16 (residencias_industrial_db)..."
    "$BIN_DIR/pg_ctl" -D "$DATA_DIR" -l "$DATA_DIR/server.log" start
  else
    echo "PostgreSQL 16 activo en ${PGHOST:-127.0.0.1}:${PGPORT:-5432} (BD: ${PGDATABASE:-residencias_industrial_db})"
  fi
fi

# 2. Liberar puerto 8000 si estaba ocupado
fuser -k 8000/tcp 2>/dev/null
sleep 0.5

# 3. Iniciar Backend Seguro Flask + PostgreSQL (Procedimientos Almacenados)
python3 "$PROJECT_DIR/backend/server.py" &
PID=$!
sleep 1.2

# 4. Abrir en Brave o navegador predeterminado
URL="http://localhost:8000/fronted/pages/gestion-vinculacion.html"
if command -v flatpak >/dev/null 2>&1 && flatpak info com.brave.Browser >/dev/null 2>&1; then
  flatpak run com.brave.Browser "$URL" >/dev/null 2>&1 &
elif command -v brave-browser >/dev/null 2>&1; then
  brave-browser "$URL" >/dev/null 2>&1 &
else
  xdg-open "$URL" >/dev/null 2>&1 &
fi

echo "=================================================================="
echo " Sistema abierto en: $URL"
echo " API Backend: Flask + libpq -> PostgreSQL 16 (app_residencias_user)"
echo " Base de datos en pgAdmin 4: localhost:5432 / residencias_industrial_db"
echo " Presiona Ctrl + C para detener el servidor"
echo "=================================================================="

wait $PID
