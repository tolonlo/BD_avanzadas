#!/usr/bin/env sh
set -eu

# Inicializa esquema base para CockroachDB (3 nodos docker compose).
# Ejecutar desde la raiz del repo:
#   sh newsql/cockroach_setup.sh

HOST="${HOST:-localhost}"
PORT="${PORT:-26257}"
DB="${DB:-socialdb}"
USER_NAME="${USER_NAME:-root}"

PSQL="psql -h ${HOST} -p ${PORT} -U ${USER_NAME}"

echo "[1/4] Creando base de datos ${DB}..."
${PSQL} -d defaultdb -c "CREATE DATABASE IF NOT EXISTS ${DB};"

echo "[2/4] Creando tablas base..."
${PSQL} -d "${DB}" -f scripts/01_create_tables_newsql.sql

echo "[3/4] Creando indices..."
${PSQL} -d "${DB}" -f scripts/02_indexes.sql

echo "[4/4] Listo para carga de datos y EXPLAIN."

echo "OK: CockroachDB inicializado en ${HOST}:${PORT}/${DB}"
