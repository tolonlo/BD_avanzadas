#!/usr/bin/env sh
set -eu

# Inicializa esquema base para YugabyteDB (YSQL).
# Ejecutar desde la raiz del repo:
#   sh newsql/yugabyte_setup.sh

HOST="${HOST:-localhost}"
PORT="${PORT:-5433}"
DB="${DB:-socialdb}"
USER_NAME="${USER_NAME:-yugabyte}"

PSQL="psql -h ${HOST} -p ${PORT} -U ${USER_NAME}"

echo "[1/4] Creando base de datos ${DB}..."
${PSQL} -d postgres -c "CREATE DATABASE ${DB};" || true

echo "[2/4] Creando tablas base..."
${PSQL} -d "${DB}" -f scripts/01_create_tables_newsql.sql

echo "[3/4] Creando indices..."
${PSQL} -d "${DB}" -f scripts/02_indexes.sql

echo "[4/4] Listo para carga de datos y EXPLAIN."

echo "OK: YugabyteDB inicializado en ${HOST}:${PORT}/${DB}"
