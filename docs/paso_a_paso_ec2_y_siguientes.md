# Paso a paso detallado: despliegue completo (EC2 + pruebas)

Objetivo: dejar funcionando lo exigido por el curso con enfoque individual usando:
- PostgreSQL manual distribuido (sharding + 2PC + replica/failover)
- NewSQL (CockroachDB) para comparacion

## 0) Arquitectura objetivo

- **PostgreSQL recomendado**: 6 EC2
  - `pg-s1-primary` / `pg-s1-replica`
  - `pg-s2-primary` / `pg-s2-replica`
  - `pg-s3-primary` / `pg-s3-replica`
- **CockroachDB**: 3 nodos (puede ser local con Docker para cerrar rapido)

Si no te alcanza presupuesto:
- 3 EC2 para shards PostgreSQL
- replica/failover demostrada en Docker (dejarlo explicitado en README)

## 1) Preparacion local (tu laptop)

En la raiz del repo:

```bash
python -m pip install --upgrade pip
python -m pip install faker
python scripts/generate_data.py --out ./data
```

Archivos generados clave:
- `data/users_nodo1.sql`, `data/users_nodo2.sql`, `data/users_nodo3.sql`
- `data/posts_nodo1.sql`, `data/posts_nodo2.sql`, `data/posts_nodo3.sql`
- `data/follows_nodo1.sql`, `data/follows_nodo2.sql`, `data/follows_nodo3.sql`
- `data/likes_nodo1.sql`, `data/likes_nodo2.sql`, `data/likes_nodo3.sql`

## 2) Crear infraestructura EC2

## 2.1 Instancias

Crear 6 instancias Ubuntu 22.04 (`t3.medium`, 20GB gp3):
- `pg-s1-primary`, `pg-s1-replica`
- `pg-s2-primary`, `pg-s2-replica`
- `pg-s3-primary`, `pg-s3-replica`

## 2.2 Security Group

Reglas inbound:
- TCP `22` desde tu IP
- TCP `5432` desde el mismo SG (trafico entre nodos)
- TCP `5432` desde tu IP (admin psql)

## 2.3 Variables de referencia (llenar antes de ejecutar)

- `S1P=<ip-privada-pg-s1-primary>`
- `S1R=<ip-privada-pg-s1-replica>`
- `S2P=<ip-privada-pg-s2-primary>`
- `S2R=<ip-privada-pg-s2-replica>`
- `S3P=<ip-privada-pg-s3-primary>`
- `S3R=<ip-privada-pg-s3-replica>`

## 3) Instalar PostgreSQL 15 en TODOS los nodos

Conectate por SSH a cada EC2 y ejecuta:

```bash
sudo apt update
sudo apt install -y curl ca-certificates gnupg lsb-release
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
sudo apt update
sudo apt install -y postgresql-15 postgresql-client-15
sudo systemctl enable postgresql
sudo systemctl start postgresql
sudo -u postgres psql -c "SELECT version();"
```

## 4) Configurar PostgreSQL (todos los nodos)

## 4.1 Encontrar archivos de config

```bash
sudo -u postgres psql -t -c "SHOW config_file;"
sudo -u postgres psql -t -c "SHOW hba_file;"
```

## 4.2 Editar `postgresql.conf`

Agregar/ajustar:

```conf
listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 256MB
max_prepared_transactions = 20
hot_standby = on
```

## 4.3 Editar `pg_hba.conf`

Agregar (ajusta CIDR a tu VPC):

```conf
host    all             all             10.0.0.0/16            scram-sha-256
host    replication     replicador      10.0.0.0/16            scram-sha-256
host    all             all             <TU_IP_PUBLICA>/32      scram-sha-256
```

## 4.4 Reiniciar y validar

```bash
sudo systemctl restart postgresql
sudo -u postgres pg_isready
```

## 5) Crear DB y usuario replicador (solo primarios)

Ejecutar en `pg-s1-primary`, `pg-s2-primary`, `pg-s3-primary`:

```bash
sudo -u postgres psql <<'SQL'
CREATE DATABASE socialdb;
CREATE ROLE replicador WITH REPLICATION LOGIN PASSWORD 'repl_secret_2026';
SQL
```

Si `socialdb` ya existe, ignora ese error.

## 6) Cargar scripts del repo en primarios

Desde tu laptop, copia repo a cada primario (ejemplo):

```bash
scp -r ./ ubuntu@<IP_PUBLICA_S1P>:/home/ubuntu/BD_avanzadas
scp -r ./ ubuntu@<IP_PUBLICA_S2P>:/home/ubuntu/BD_avanzadas
scp -r ./ ubuntu@<IP_PUBLICA_S3P>:/home/ubuntu/BD_avanzadas
```

En cada primario:

```bash
cd /home/ubuntu/BD_avanzadas
sudo chown -R ubuntu:ubuntu .
```

## 6.1 Shard 1 (`pg-s1-primary`)

Editar temporalmente `scripts/01_create_tables.sql` para que el `CHECK` quede `BETWEEN 1 AND 3000`, luego:

```bash
cd /home/ubuntu/BD_avanzadas
sudo -u postgres psql -d socialdb -f scripts/01_create_tables.sql
sudo -u postgres psql -d socialdb -f scripts/02_indexes.sql
sudo -u postgres psql -d socialdb -f data/users_nodo1.sql
sudo -u postgres psql -d socialdb -f data/posts_nodo1.sql
sudo -u postgres psql -d socialdb -f data/follows_nodo1.sql
sudo -u postgres psql -d socialdb -f data/likes_nodo1.sql
```

## 6.2 Shard 2 (`pg-s2-primary`)

`CHECK` en `01_create_tables.sql` a `BETWEEN 3001 AND 6000`, luego:

```bash
cd /home/ubuntu/BD_avanzadas
sudo -u postgres psql -d socialdb -f scripts/01_create_tables.sql
sudo -u postgres psql -d socialdb -f scripts/02_indexes.sql
sudo -u postgres psql -d socialdb -f data/users_nodo2.sql
sudo -u postgres psql -d socialdb -f data/posts_nodo2.sql
sudo -u postgres psql -d socialdb -f data/follows_nodo2.sql
sudo -u postgres psql -d socialdb -f data/likes_nodo2.sql
```

## 6.3 Shard 3 (`pg-s3-primary`)

`CHECK` en `01_create_tables.sql` a `BETWEEN 6001 AND 10000`, luego:

```bash
cd /home/ubuntu/BD_avanzadas
sudo -u postgres psql -d socialdb -f scripts/01_create_tables.sql
sudo -u postgres psql -d socialdb -f scripts/02_indexes.sql
sudo -u postgres psql -d socialdb -f data/users_nodo3.sql
sudo -u postgres psql -d socialdb -f data/posts_nodo3.sql
sudo -u postgres psql -d socialdb -f data/follows_nodo3.sql
sudo -u postgres psql -d socialdb -f data/likes_nodo3.sql
```

## 7) Crear replicas por shard

Ejecutar en cada replica, cambiando `<IP_PRIMARIO_SHARD>`:

```bash
sudo systemctl stop postgresql
sudo -u postgres rm -rf /var/lib/postgresql/15/main/*
sudo -u postgres pg_basebackup \
  -h <IP_PRIMARIO_SHARD> \
  -U replicador \
  -D /var/lib/postgresql/15/main \
  -P -R --wal-method=stream
sudo systemctl start postgresql
sudo -u postgres pg_isready
```

Verificar en cada primario:

```bash
sudo -u postgres psql -d socialdb -c "SELECT application_name, client_addr, state, sync_state FROM pg_stat_replication;"
```

## 8) Pruebas requeridas PostgreSQL

En cada primario:

```bash
cd /home/ubuntu/BD_avanzadas
sudo -u postgres psql -d socialdb -f scripts/04_routing.sql
```

2PC (manual en dos terminales psql):
- usar `scripts/05_2pc.sql` (tabla `distributed_ops_log`)
- correr PREPARE en nodo A y B
- luego COMMIT PREPARED en ambos

Benchmark y EXPLAIN:

```bash
sudo -u postgres psql -d socialdb -f scripts/06_replication.sql
sudo -u postgres psql -d socialdb -f scripts/07_explain_queries.sql
```

Failover de prueba (en replica):

```bash
sudo -u postgres psql -c "SELECT pg_promote();"
```

## 9) CockroachDB (recomendado para NewSQL)

En local (mas rapido):

```bash
docker compose -f infra/docker-compose.yml up -d
sh newsql/cockroach_setup.sh
for f in users_nodo1 users_nodo2 users_nodo3 posts_nodo1 posts_nodo2 posts_nodo3 follows_all likes_all; do
  psql -h localhost -p 26257 -U root -d socialdb -f data/$f.sql
done
psql -h localhost -p 26257 -U root -d socialdb -c "SHOW RANGES FROM TABLE posts;"
```

## 10) Llenar resultados y cerrar informe

Completar:
- `resultados/latencia_escritura.csv`
- `resultados/latencia_lectura.csv`

Luego actualizar:
- `README.md` (comparativo final PostgreSQL vs Cockroach)
- `docs/analisis_critico.md` (conclusiones y trade-offs)

## 11) Checklist final

- [ ] Shards PostgreSQL activos (3 primarios)
- [ ] Replicacion activa (3 replicas)
- [ ] 2PC ejecutado y evidenciado
- [ ] EXPLAIN/ANALYZE ejecutado y documentado
- [ ] Cockroach cargado y probado
- [ ] CSV de latencias completos
- [ ] README y analisis critico finalizados
