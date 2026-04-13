# SI3009 — Proyecto 2: Arquitecturas Distribuidas

> **Curso:** Bases de Datos Avanzadas · 2026-1
> **Dominio:** Red social simplificada (usuarios, posts, follows, likes)
> **Motores evaluados:** PostgreSQL 15 (manual) · CockroachDB (NewSQL)

---

## Tabla de contenidos

1. [Estructura del repositorio](#1-estructura-del-repositorio)
2. [Dominio y modelo de datos](#2-dominio-y-modelo-de-datos)
3. [Fundamentos teóricos](#3-fundamentos-teóricos)
4. [Arquitectura del sistema](#4-arquitectura-del-sistema)
5. [PostgreSQL: configuración distribuida manual](#5-postgresql-configuración-distribuida-manual)
6. [NewSQL: CockroachDB](#6-newsql-cockroachdb)
7. [Experimentos y resultados](#7-experimentos-y-resultados)
8. [Análisis comparativo final](#8-análisis-comparativo-final)
9. [Análisis crítico](#9-análisis-crítico)
10. [Generador de datos sintéticos](#10-generador-de-datos-sintéticos)

---

## 1. Estructura del repositorio

```
/
├── infra/
│   └── docker-compose.yml          # Cluster CockroachDB 3 nodos en Docker
├── scripts/
│   ├── 01_create_tables.sql        # Esquema base con CHECK por rango (aplicar en cada nodo)
│   ├── 01_create_tables_newsql.sql # Esquema sin CHECK para CockroachDB
│   ├── 02_indexes.sql              # Índices por partición
│   ├── 03_inserts.sql              # Datos de prueba mínimos
│   ├── 04_routing.sql              # Funciones PL/pgSQL de enrutamiento
│   ├── 05_2pc.sql                  # Transacciones distribuidas PREPARE/COMMIT PREPARED
│   ├── 06_replication.sql          # Benchmark synchronous_commit y failover
│   └── 07_explain_queries.sql      # 8 consultas con EXPLAIN ANALYZE documentadas
├── newsql/
│   └── cockroachdb_setup.sh        # Inicialización cluster CockroachDB Docker
├── data/                           # Archivos SQL generados (git-ignored)
├── resultados/
│   └── explain_output.txt          # Output completo EXPLAIN ANALYZE PostgreSQL
├── generate_data.py                # Generador de datos sintéticos (Faker)
└── README.md
```

---

## 2. Dominio y modelo de datos

### Contexto

Se modela una **red social simplificada** donde los usuarios pueden publicar contenido, seguir a otros usuarios y reaccionar a publicaciones mediante likes. Este dominio es especialmente adecuado para experimentar con bases de datos distribuidas porque permite segmentar los datos de forma natural por `user_id`, y genera patrones de acceso mixtos (OLTP frecuente + OLAP analítico).

**Volúmenes reales generados y cargados:**

| Tabla   | Nodo 1 (1–3000) | Nodo 2 (3001–6000) | Nodo 3 (6001–10000) | Total   |
|---------|-----------------|--------------------|---------------------|---------|
| users   | 3.000           | 3.000              | 4.000               | 10.000  |
| posts   | 14.881          | 14.930             | 20.198              | 50.009  |
| likes   | 29.939          | 30.080             | 39.999              | 100.018 |
| follows | 9.033           | 9.062              | 11.924              | 30.019  |

### Esquema implementado

```sql
-- users (CHECK por rango varía por nodo)
CREATE TABLE users (
    id         INT PRIMARY KEY CHECK (id BETWEEN 1 AND 3000), -- ajustar por nodo
    username   VARCHAR(50)  NOT NULL UNIQUE,
    email      VARCHAR(100) NOT NULL UNIQUE,
    bio        TEXT,
    created_at TIMESTAMP    DEFAULT NOW()
);

-- posts (FK local, data locality garantizada)
CREATE TABLE posts (
    id         INT PRIMARY KEY,
    user_id    INT NOT NULL,
    content    TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT fk_posts_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- follows (solo FK en follower_id local; followed_id puede ser cross-shard)
CREATE TABLE follows (
    follower_id INT NOT NULL,
    followed_id INT NOT NULL,
    created_at  TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (follower_id, followed_id),
    CONSTRAINT fk_follows_follower FOREIGN KEY (follower_id) REFERENCES users(id) ON DELETE CASCADE
);

-- likes (solo FK en user_id local)
CREATE TABLE likes (
    user_id    INT NOT NULL,
    post_id    INT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (user_id, post_id),
    CONSTRAINT fk_likes_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- shard_metadata (replicada en todos los nodos)
CREATE TABLE shard_metadata (
    shard_id    INT PRIMARY KEY,
    host        VARCHAR(50) NOT NULL,
    port        INT NOT NULL DEFAULT 5432,
    user_id_min INT NOT NULL,
    user_id_max INT NOT NULL,
    is_active   BOOLEAN DEFAULT TRUE,
    updated_at  TIMESTAMP DEFAULT NOW()
);
```

---

## 3. Fundamentos teóricos

### 3.1 Teorema CAP

El teorema CAP establece que un sistema distribuido solo puede garantizar **dos de las tres** propiedades simultáneamente:

- **Consistencia (C):** todos los nodos ven los mismos datos al mismo tiempo.
- **Disponibilidad (A):** cada solicitud recibe una respuesta (aunque no sea la más reciente).
- **Tolerancia a particiones (P):** el sistema sigue funcionando aunque se pierda comunicación entre nodos.

PostgreSQL en configuración distribuida manual es **CA** en un nodo, y debe configurarse explícitamente para tolerar particiones. CockroachDB es **CP**: prefiere rechazar escrituras antes que aceptar inconsistencias.

### 3.2 Modelo PACELC

| Motor | En partición | En operación normal |
|-------|-------------|---------------------|
| PostgreSQL (`synchronous_commit=off`) | PA | EL (baja latencia, riesgo de pérdida) |
| PostgreSQL (`synchronous_commit=on`)  | PC | EC (mayor latencia, consistencia fuerte) |
| CockroachDB | PC | EC (overhead de consenso Raft) |

### 3.3 ACID vs Consistencia eventual

**ACID** garantiza atomicidad, consistencia, aislamiento y durabilidad. PostgreSQL implementa ACID de forma nativa en un único nodo. En configuración distribuida, se obtiene mediante **2PC (Two-Phase Commit)**. CockroachDB provee ACID distribuido de forma transparente mediante el protocolo Raft.

### 3.4 Particionamiento horizontal (Sharding)

Este proyecto implementa **sharding por rango de `user_id`**, colocando todos los datos de un usuario en el mismo nodo (data locality). La estrategia garantiza que las operaciones OLTP más frecuentes (feed de un usuario, posts propios) sean siempre locales y no requieran round-trips de red.

### 3.5 Two-Phase Commit (2PC)

1. **Fase Prepare:** el coordinador solicita a todos los participantes que preparen la transacción.
2. **Fase Commit/Abort:** si todos responden OK, el coordinador emite el commit definitivo.

**Riesgo crítico:** si el coordinador falla entre las dos fases, los participantes quedan bloqueados en estado `PREPARED` indefinidamente. Esto constituye una de las principales limitaciones del 2PC clásico.

---

## 4. Arquitectura del sistema

```
                    ┌──────────────────────┐
                    │   Aplicación / API   │
                    │  Lógica de negocio   │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │  Router de consultas │
                    │ get_shard_for_user() │
                    └──┬──────────┬────────┘
              ≤3000 /  │  ≤6000   │  >6000 \
                       │          │          │
     ┌─────────────────┼──────────┼──────────┼──────────────────┐
     │  PostgreSQL 15 — 3 instancias EC2 t3.medium (us-east-1b) │
     │                                                           │
     │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
     │  │   pg-s1      │  │   pg-s2      │  │   pg-s3      │   │
     │  │   PRIMARY    │  │   REPLICA    │  │   REPLICA    │   │
     │  │  1 – 3.000   │  │ 3.001–6.000  │  │ 6.001–10.000 │   │
     │  │172.31.30.214 │  │172.31.31.27  │  │172.31.17.120 │   │
     │  └──────┬───────┘  └──────────────┘  └──────────────┘   │
     │         │ streaming replication (async)                   │
     │         ├──────────────────────────────────────────────► │
     │         └──────────────────────────────────────────────► │
     │              ←── 2PC (PREPARE / COMMIT PREPARED) ──►     │
     └───────────────────────────────────────────────────────────┘

     ┌───────────────────────────────────────────────────────────┐
     │  CockroachDB — cluster 3 nodos Docker (localhost)        │
     │                                                           │
     │  ┌──────────┐   ┌──────────┐   ┌──────────┐             │
     │  │  roach1  │◄──►  roach2  │◄──►  roach3  │             │
     │  │ :26257   │   │ :26258   │   │ :26259   │             │
     │  └──────────┘   └──────────┘   └──────────┘             │
     │   Auto-sharding · Raft consensus · txn distribuidas       │
     └───────────────────────────────────────────────────────────┘
```

**IPs reales del despliegue:**

| Nodo | IP Pública | IP Privada | Rol |
|------|-----------|------------|-----|
| pg-s1 | 54.84.89.145 | 172.31.30.214 | Primary |
| pg-s2 | 34.227.9.92  | 172.31.31.27  | Replica (streaming) |
| pg-s3 | 34.229.159.138 | 172.31.17.120 | Replica (streaming) |

---

## 5. PostgreSQL: configuración distribuida manual

### 5.1 Estrategia de sharding

Sharding por rango de `user_id` en 3 instancias EC2:

| Nodo | Rango user_id | users | posts | likes | follows |
|------|--------------|-------|-------|-------|---------|
| pg-s1 | 1 – 3.000   | 3.000 | 14.881 | 29.939 | 9.033 |
| pg-s2 | 3.001 – 6.000 | 3.000 | 14.930 | 30.080 | 9.062 |
| pg-s3 | 6.001 – 10.000 | 4.000 | 20.198 | 39.999 | 11.924 |

El constraint `CHECK (id BETWEEN x AND y)` en la tabla `users` impone el rango a nivel de base de datos, rechazando inserciones fuera del rango del nodo:

```
ERROR: new row for relation "users" violates check constraint "users_id_check"
DETAIL: Failing row contains (3001, ...) -- rechazado en nodo 1
```

### 5.2 Lógica de enrutamiento (Script 04)

Implementada como función PL/pgSQL en cada nodo:

```sql
CREATE OR REPLACE FUNCTION get_shard_for_user(p_user_id INT)
RETURNS INT AS $$
BEGIN
    IF p_user_id BETWEEN 1 AND 3000 THEN RETURN 1;
    ELSIF p_user_id BETWEEN 3001 AND 6000 THEN RETURN 2;
    ELSIF p_user_id BETWEEN 6001 AND 10000 THEN RETURN 3;
    ELSE RAISE EXCEPTION 'user_id % fuera del rango (1–10000)', p_user_id;
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
```

Resultado de `simulate_routing_decision()`:

```
 user_id | shard_id |            connection_string
---------+----------+-----------------------------------------
     100 |        1 | host=10.0.0.1 port=5432 dbname=socialdb
    3500 |        2 | host=10.0.0.2 port=5432 dbname=socialdb
    7200 |        3 | host=10.0.0.3 port=5432 dbname=socialdb
       1 |        1 | host=10.0.0.1 port=5432 dbname=socialdb
    6000 |        2 | host=10.0.0.2 port=5432 dbname=socialdb
   10000 |        3 | host=10.0.0.3 port=5432 dbname=socialdb
```

### 5.3 Replicación streaming (Script 06)

Se configuró pg-s1 como Primary y pg-s2/pg-s3 como réplicas de solo lectura mediante `pg_basebackup`:

```bash
# En cada réplica
pg_basebackup -h 172.31.30.214 -U replicador \
  -D /var/lib/postgresql/15/main \
  -P -Xs -R --slot=replica_s2 --checkpoint=fast
```

Estado verificado en pg-s1:

```
  client_addr  | application_name |   state   | sync_state
---------------+------------------+-----------+------------
 172.31.31.27  | 15/main          | streaming | async
 172.31.17.120 | 15/main          | streaming | async
```

Las réplicas confirman modo recovery:

```sql
SELECT pg_is_in_recovery(); -- → t (true) en pg-s2 y pg-s3
```

**Impacto de `synchronous_commit` (medido con Script 06):**

| Configuración | Latencia escritura p50 | Riesgo pérdida datos |
|---------------|----------------------|----------------------|
| `off` (async) | ~1.5 ms | Sí (últimas txn no replicadas) |
| `on` (sync)   | ~8–15 ms | No |
| `remote_apply`| ~20–30 ms | No + réplica aplicó |

### 5.4 Transacciones distribuidas con 2PC (Script 05)

Demostración completa entre `socialdb` y `socialdb2` en pg-s1:

**Fase 1 — PREPARE (ambos nodos):**
```sql
-- DB 1
BEGIN;
INSERT INTO distributed_ops_log VALUES ('2pc_demo_2026_01_n1', 'follow_cross_shard', 'nodo1');
PREPARE TRANSACTION '2pc_demo_2026_01_n1';  -- → PREPARE TRANSACTION

-- DB 2
BEGIN;
INSERT INTO distributed_ops_log VALUES ('2pc_demo_2026_01_n2', 'follow_cross_shard', 'nodo2');
PREPARE TRANSACTION '2pc_demo_2026_01_n2';  -- → PREPARE TRANSACTION
```

**Verificación estado PREPARED:**
```
         gid         |           prepared            | database
---------------------+-------------------------------+-----------
 2pc_demo_2026_01_n1 | 2026-04-13 02:07:18.848784+00 | socialdb
 2pc_demo_2026_01_n2 | 2026-04-13 02:07:28.864784+00 | socialdb2
```

**Fase 2 — COMMIT:**
```sql
COMMIT PREPARED '2pc_demo_2026_01_n1';  -- → COMMIT PREPARED
COMMIT PREPARED '2pc_demo_2026_01_n2';  -- → COMMIT PREPARED
```

**Resultado final verificado:**
```
         gid         |      op_name       | source_node |         created_at
---------------------+--------------------+-------------+----------------------------
 2pc_demo_2026_01_n1 | follow_cross_shard | nodo1       | 2026-04-09 17:16:15.750818
 2pc_demo_2026_01_n2 | follow_cross_shard | nodo2       | 2026-04-09 17:18:38.142247
```

**Riesgo documentado:** si el coordinador falla entre PREPARE y COMMIT, las transacciones quedan bloqueadas. Detectable con:
```sql
SELECT gid, prepared, owner FROM pg_prepared_xacts;
-- Limpiar con: ROLLBACK PREPARED 'gid';
```

### 5.5 Failover (pendiente — sección 7.5)

---

## 6. NewSQL: CockroachDB

### 6.1 Inicialización del cluster (3 nodos Docker)

```bash
docker network create cockroachdb

docker run -d --name=roach1 --hostname=roach1 --net=cockroachdb \
  -p 26257:26257 -p 8080:8080 cockroachdb/cockroach:latest start \
  --insecure --join=roach1,roach2,roach3 \
  --listen-addr=0.0.0.0:26257 --advertise-addr=roach1:26257

# (roach2 y roach3 análogos en puertos 26258/26259)

docker exec -it roach1 ./cockroach init --insecure
# → Cluster successfully initialized
```

### 6.2 Carga de datos

Un solo endpoint recibe todos los datos — el motor distribuye automáticamente:

```
  tabla   | count
----------+---------
  users   |  10000
  posts   |  50000
  follows |  30000
  likes   | 100000
```

Vs PostgreSQL que requirió cargar archivos separados por nodo (`users_nodo1.sql`, `users_nodo2.sql`, etc.).

### 6.3 Auto-sharding y Raft

CockroachDB divide los datos en rangos de ~512 MB y los redistribuye entre nodos automáticamente. Cada rango tiene un leaseholder (líder Raft) y réplicas. El EXPLAIN ANALYZE muestra `distribution: full` cuando la consulta requiere datos de múltiples nodos, manejado internamente sin intervención del desarrollador.

### 6.4 Transacciones distribuidas nativas

```sql
-- En CockroachDB: transparente, sin configuración adicional
BEGIN;
INSERT INTO follows (follower_id, followed_id) VALUES (100, 4500);
COMMIT;
-- isolation level: serializable (por defecto)
```

---

## 7. Experimentos y resultados

### 7.1 EXPLAIN ANALYZE — PostgreSQL Nodo 1 (datos reales)

#### C1: Feed local de usuario (OLTP)
```
Execution Time: 0.069 ms
Plan: Bitmap Index Scan on idx_posts_user_created
      Index Cond: (user_id = 1500)
      Buffers: shared hit=11 (todo en caché)
```

#### C2: Búsqueda full-text ILIKE sin índice trgm
```
Execution Time: 22.403 ms
Plan: Seq Scan on posts
      Filter: (content ~~* '%PostgreSQL%')
      Rows Removed by Filter: 12.620
      → Requiere revisar 14.881 filas para retornar 2.261
```

#### C3: OLAP — usuarios con más publicaciones
```
Execution Time: 11.240 ms
Plan: HashAggregate + Hash Join
      Group Key: u.id
      Rows procesadas: 14.881 posts × 3.000 users
```

#### C4: Posts más populares por likes
```
Execution Time: 37.041 ms
Plan: Hash Right Join (likes ⟖ posts) + Hash Join (users)
      HashAggregate sobre 17.032 filas
      Memory: 3.345 MB
```

#### C5: Followers de un usuario (OLTP)
```
Execution Time: 0.041 ms
Plan: Index Scan on idx_follows_followed_id
      Index Cond: (followed_id = 1)
      Nested Loop con users_pkey
```

#### C6: Cross-shard — Nodo 1 (user_ids locales)
```
Execution Time: 0.989 ms
Plan: Bitmap Index Scan on idx_posts_user_created
      user_id IN (1,2,5,8,10) → 25 rows
```

#### C6: Cross-shard — Nodo 1 consultando user_ids de Nodo 2
```
Execution Time: 0.023 ms
Rows: 0 — los user_ids 3001,3002,3500 NO existen en este nodo
→ La app debe consultar Nodo 2 por separado y combinar resultados
```

#### C7: Vista v_user_stats (múltiples JOINs)
```
Execution Time: 5.652 ms
Plan: GroupAggregate + Merge Right Join + Index Only Scan
      Memoize hits: 618 / misses: 100 (caché efectivo)
```

#### C8: Benchmark perfil usuario (500 usuarios)
```
Execution Time: 42.479 ms
Plan: GroupAggregate + Nested Loop Left Join
      73.714 filas procesadas para 500 usuarios
```

### 7.2 EXPLAIN ANALYZE — CockroachDB (datos reales)

#### C1: Feed local (sin índice)
```
execution time: 81ms
distribution: full
Plan: FULL SCAN on posts (50.000 filas)
      rows decoded from KV: 50.001 (5.2 MiB, 2 gRPC calls)
```

#### C1: Feed local (con índice)
```
execution time: 7ms
distribution: local
Plan: Index scan on idx_posts_user_created
      rows decoded from KV: 15 (1008 B, 3 gRPC calls)
      isolation level: serializable
```

#### C3: OLAP GROUP BY (sin índice)
```
execution time: 117ms
distribution: full
Plan: Hash Join + group (hash)
      rows decoded from KV: 60.000 (5.6 MiB)
```

#### C3: OLAP GROUP BY (con índice)
```
execution time: 74ms
distribution: full
Plan: Hash Join + group (hash)
      rows decoded from KV: 60.000 (2.3 MiB) — menos bytes por índice
```

### 7.3 Comparación consolidada PostgreSQL vs CockroachDB

| Consulta | PostgreSQL (ms) | CockroachDB sin índice (ms) | CockroachDB con índice (ms) |
|----------|----------------|-----------------------------|-----------------------------|
| C1: Feed local (OLTP) | **0.069** | 81 | 7 |
| C2: Full-text ILIKE | 22.4 | — | — |
| C3: OLAP GROUP BY | 11.2 | 117 | 74 |
| C4: Posts populares | 37.0 | — | — |
| C5: Followers Index | **0.041** | — | — |
| C6: Cross-shard (local) | 0.989 | — | — |
| C6: Cross-shard (remoto) | 0 rows* | N/A | N/A automático |
| C8: Perfil 500 usuarios | 42.5 | — | — |

*En PostgreSQL, consultar user_ids de otro shard devuelve 0 resultados — la app debe consultar cada nodo por separado.

**Observaciones clave:**
- PostgreSQL es ~100x más rápido en consultas OLTP locales (0.069 ms vs 7 ms) gracias a la ausencia de overhead de red y consenso distribuido.
- CockroachDB mejora dramáticamente con índices (81 ms → 7 ms en C1).
- CockroachDB maneja cross-shard automáticamente (`distribution: full`); PostgreSQL requiere lógica en la aplicación.
- CockroachDB usa `isolation level: serializable` por defecto, sin configuración adicional.

### 7.4 Impacto de réplicas en PostgreSQL

| Modo replicación | Estado réplicas | sync_state |
|-----------------|----------------|------------|
| Streaming async | 2 réplicas activas | async |
| Verificado con | `pg_stat_replication` | streaming |

Las réplicas son read-only (`pg_is_in_recovery() = t`). Intentar escritura en réplica produce:
```
ERROR: cannot execute INSERT in a read-only transaction
ERROR: cannot execute CREATE TABLE in a read-only transaction
```

### 7.5 Simulación de Failover

**Escenario:** caída del Primary (pg-s1). Promoción manual de pg-s2. Reintegración de pg-s1 como réplica.

**Estado inicial verificado:**
```
-- pg-s1 (Primary)
  client_addr  |   state   | sync_state
 172.31.31.27  | streaming | async
 172.31.17.120 | streaming | async

-- pg-s2 y pg-s3
 pg_is_in_recovery → t
```

**Proceso ejecutado:**

| Paso | Acción | Comando | Resultado |
|------|--------|---------|-----------|
| 1 | Apagar Primary | `systemctl stop postgresql` | `pg_isready` → no response |
| 2 | Detectar caída en réplica | `pg_last_xact_replay_timestamp()` | lag ~47 min sin WAL nuevo |
| 3 | Promover pg-s2 | `pg_ctl promote -D /var/lib/postgresql/15/main` | `server promoted` |
| 4 | Verificar nuevo Primary | `SELECT pg_is_in_recovery()` | `f` (ya no es réplica) |
| 5 | Probar escritura | `INSERT INTO distributed_ops_log ...` | `INSERT 0 1` ✅ |
| 6 | Actualizar routing | `UPDATE shard_metadata SET host='172.31.31.27'` | `UPDATE 1` |
| 7 | Reintegrar pg-s1 | `pg_basebackup -h 172.31.31.27 ...` | `48261/48261 kB (100%)` |
| 8 | Redirigir pg-s3 | `ALTER SYSTEM SET primary_conninfo` | streaming desde nuevo Primary |

**Estado final:**
```
-- pg-s2 (nuevo Primary)
  client_addr  |   state   | sync_state
 172.31.30.214 | streaming | async   ← pg-s1 ahora es réplica
 172.31.17.120 | streaming | async   ← pg-s3 redirigido
```

**Retos encontrados durante el failover:**

1. **Slots de replicación no se transfieren:** al promover pg-s2, los slots `replica_s2` y `replica_s3` no existían en el nuevo Primary. Hubo que crearlos manualmente con `pg_create_physical_replication_slot()` antes de que las réplicas pudieran reconectarse.

2. **pg-s3 seguía apuntando al Primary caído:** el archivo `postgresql.auto.conf` tenía hardcodeada la IP de pg-s1 (`172.31.30.214`). Requirió `ALTER SYSTEM SET primary_conninfo` para redirigirlo manualmente a pg-s2.

3. **Tiempo de detección:** las réplicas no detectan la caída instantáneamente — el lag acumulado llegó a ~47 minutos desde la última transacción replicada, lo que implica potencial pérdida de datos en modo async.

4. **Sin automatización:** todo el proceso tomó múltiples pasos manuales. En producción, Patroni + etcd automatiza la detección y promoción con quórum, evitando split-brain (dos nodos creyéndose Primary simultáneamente).

**Contraste con CockroachDB:** el mismo escenario en CockroachDB se resuelve con `docker stop roach1` — el cluster elige automáticamente un nuevo leaseholder via Raft en segundos, sin intervención del operador.

---

## 8. Análisis comparativo final

| Dimensión | PostgreSQL (distribuido manual) | CockroachDB |
|-----------|--------------------------------|-------------|
| **Particionamiento** | Manual por rango. CHECK constraint impone el rango. Enrutamiento en la aplicación | Automático. Auto-sharding por rangos de clave. Transparente |
| **Replicación** | Streaming replication. Configuración manual vía postgresql.conf y pg_basebackup | Protocolo Raft automático. Cada rango tiene 3 réplicas por defecto |
| **Consistencia** | ACID local. Distribuida requiere 2PC manual | Serializable global por defecto. Sin configuración adicional |
| **Modelo CAP** | CA por nodo. Configurable hacia CP (sync) o AP (async) | CP siempre |
| **PACELC** | PA/EL (async) o PC/EC (sync) — configurable | PC/EC siempre |
| **Transacciones distribuidas** | No nativas. PREPARE TRANSACTION + COMMIT PREPARED manual | Nativas y transparentes. BEGIN/COMMIT estándar |
| **Failover** | Manual. pg_ctl promote. Riesgo de split-brain sin Patroni | Automático en segundos vía Raft |
| **Latencia OLTP local** | Muy baja (~0.069 ms con índice en caché) | Mayor (~7 ms con índice, overhead gRPC) |
| **Latencia OLAP** | ~11–42 ms por nodo (datos parciales) | ~74–117 ms (datos completos, distribuido) |
| **Cross-shard joins** | No nativos. Combinar en aplicación, múltiples conexiones | Nativos. distribution: full automático |
| **Carga de datos** | Archivo separado por nodo (_nodo1.sql, _nodo2.sql, _nodo3.sql) | Un solo endpoint. 10.000 users, 50.000 posts en un comando |
| **Complejidad operativa** | Alta. pg_hba, postgresql.conf, slots de replicación, security groups, permisos | Baja. docker run + init |
| **Compatibilidad SQL** | SQL estándar completo + extensiones PG | Dialecto PostgreSQL. Algunas funciones de sistema difieren (ej. pg_tables → crdb_internal) |
| **Escalabilidad** | Manual. Redistribuir shards requiere migración de datos | Nativa. Agregar nodo redistribuye automáticamente |

---

## 8.5 Retos reales encontrados en la implementación

Esta sección documenta los problemas concretos que surgieron durante el despliegue, no como errores a esconder sino como evidencia de la complejidad operativa real.

| Reto | Causa | Solución |
|------|-------|----------|
| Kali Linux bloqueaba `pip install` | Sistema externamente administrado (PEP 668) | Crear virtualenv con `--system-site-packages` tras instalar `python3.13-venv` |
| `sudo -u postgres psql` devuelve "Permission denied" | El directorio `/home/ubuntu` no es accesible por el usuario postgres | Inofensivo — el comando funciona igual; solo es un warning del cwd |
| `pg_basebackup` fallaba con "directory not empty" | El directorio de datos tenía archivos residuales | Usar `find -mindepth 1 -delete` como usuario postgres en lugar de `rm -rf` |
| Security group bloqueaba tráfico entre nodos | Una instancia tenía un SG diferente (`launch-wizard`) | Agregar `pg-cluster-sg` a la instancia con SG incorrecto |
| `ping` entre nodos fallaba 100% packet loss | ICMP bloqueado por AWS — el puerto 5432 sí funcionaba | Usar `nc -zv` para verificar conectividad TCP |
| IP pública cambia al reiniciar instancias | AWS Academy no asigna IPs elásticas por defecto | Actualizar regla SSH en security group con "My IP" cada sesión |
| Slots de replicación no se transfieren en failover | Los slots son locales al Primary — no se replican | Crear slots manualmente en el nuevo Primary post-promoción |
| pg-s3 seguía apuntando al Primary caído | `postgresql.auto.conf` tiene IP hardcodeada del basebackup original | `ALTER SYSTEM SET primary_conninfo` para redirigir al nuevo Primary |
| 2PC no funciona entre nodos diferentes | Las réplicas son read-only | Demostrar 2PC entre dos databases en el mismo Primary |
| CockroachDB init fallaba con "connection refused" | Contenedores usaban IPv6 que WSL no enruta | Agregar `--listen-addr=0.0.0.0` para forzar IPv4 |

---

## 9. Análisis crítico

### 9.1 Complejidad operativa real

La implementación de este proyecto evidencia una brecha significativa entre la complejidad teórica y la práctica operativa. Configurar sharding manual en PostgreSQL requirió resolver problemas no documentados: security groups de AWS bloqueando tráfico entre nodos, permisos de sistema en Kali Linux impidiendo la instalación de paquetes, rutas de archivos inaccesibles para el usuario `postgres`, y slots de replicación que deben pre-existir antes del basebackup.

Ninguno de estos problemas es técnicamente difícil en aislamiento, pero en conjunto representan horas de debugging que un sistema administrado o NewSQL habría absorbido internamente. CockroachDB se inicializó con tres comandos `docker run` y un `init`; PostgreSQL distribuido requirió configurar manualmente postgresql.conf, pg_hba.conf, slots de replicación, security groups, usuarios de replicación y permisos de sistema.

Un caso concreto que ilustra esto a escala industrial es **Rappi** (Colombia): en su crecimiento entre 2017 y 2020, la compañía debió migrar progresivamente de bases de datos centralizadas hacia arquitecturas distribuidas, enfrentando exactamente estos trade-offs. La gestión de consistencia eventual en un sistema de pedidos donde un producto puede mostrarse disponible mientras ya fue comprado en otro nodo no es un problema trivial, y requirió equipos dedicados exclusivamente a infraestructura de datos.

### 9.2 Impacto en costos

| Aspecto | PostgreSQL distribuido | CockroachDB Cloud |
|---------|----------------------|-------------------|
| Infraestructura | EC2 t3.medium ~$30/mes/nodo | ~$200-400/mes/nodo (gestionado) |
| Costo DBA | Alto (8–15M COP/mes en Colombia) | Bajo (motor gestiona failover/sharding) |
| Costo downtime | Alto (failover manual puede tomar horas) | Bajo (failover automático en segundos) |
| Punto de equilibrio | Equipos pequeños con experiencia PG | Equipos que crecen rápido o escala global |

El costo oculto más significativo de PostgreSQL distribuido manual no es la infraestructura sino el tiempo de ingeniería. Un incidente de split-brain o un bloqueo de 2PC en producción puede implicar horas de downtime.

### 9.3 Lo que los benchmarks no muestran

Los números de latencia de este proyecto (0.069 ms PostgreSQL vs 7 ms CockroachDB en OLTP) favorecen a PostgreSQL, pero omiten variables críticas de producción:

- **Escalabilidad:** agregar un cuarto nodo en PostgreSQL requiere redistribuir manualmente los rangos y migrar datos. En CockroachDB es un `docker run` adicional.
- **Consistencia bajo carga:** PostgreSQL async puede perder transacciones ante un failover; CockroachDB no.
- **Cross-shard invisible:** Twitter operó años con sharding manual de MySQL antes de desarrollar herramientas propias de redistribución, una inversión de meses de ingeniería que CockroachDB provee nativamente.

### 9.4 BD centralizada vs distribuida vs servicio administrado

| Dimensión | BD centralizada | BD distribuida manual | Servicio administrado (RDS) |
|-----------|----------------|----------------------|----------------------------|
| Complejidad implementación | Baja | Alta | Media |
| Complejidad operativa | Baja | Muy alta | Baja |
| Escalabilidad | Vertical limitada | Horizontal | Media-alta |
| Control infraestructura | Total | Total | Limitado |
| Costo inicial | Bajo | Medio | Bajo |
| Costo a escala | Bajo-medio | Medio | Alto |
| Vendor lock-in | Ninguno | Ninguno | Alto |
| SLA disponibilidad | Equipo | Equipo | 99.9–99.99% |

Para proyectos en etapa temprana, RDS o Cloud SQL ofrece el mejor balance. La distribución manual tiene sentido con restricciones regulatorias o cuando el volumen lo justifica. NewSQL es adecuado para escala global con equipos maduros.

---

## 10. Generador de datos sintéticos

### Instalación y uso

```bash
python3 -m venv venv
source venv/bin/activate
pip install faker
python generate_data.py --users 10000 --posts 50000 --follows 30000 --likes 100000 --out ./data
```

### Archivos generados

```
data/
├── users_nodo1.sql     # 3.000 usuarios (id 1–3000)
├── users_nodo2.sql     # 3.000 usuarios (id 3001–6000)
├── users_nodo3.sql     # 4.000 usuarios (id 6001–10000)
├── posts_nodo1.sql     # 14.881 posts
├── posts_nodo2.sql     # 14.930 posts
├── posts_nodo3.sql     # 20.198 posts
├── follows_nodo1.sql   # 9.033 follows (follower local)
├── follows_nodo2.sql   # 9.062 follows
├── follows_nodo3.sql   # 11.924 follows
├── follows_all.sql     # todos los follows (para CockroachDB)
├── likes_nodo1.sql     # 29.939 likes
├── likes_nodo2.sql     # 30.080 likes
├── likes_nodo3.sql     # 39.999 likes
└── likes_all.sql       # todos los likes (para CockroachDB)
```

### Carga en PostgreSQL (por nodo)

```bash
# Nodo 1 — desde laptop
sudo cp data/users_nodo1.sql /tmp/ && sudo -u postgres psql -d socialdb -f /tmp/users_nodo1.sql
sudo cp data/posts_nodo1.sql /tmp/ && sudo -u postgres psql -d socialdb -f /tmp/posts_nodo1.sql
sudo cp data/follows_nodo1.sql /tmp/ && sudo -u postgres psql -d socialdb -f /tmp/follows_nodo1.sql
sudo cp data/likes_nodo1.sql /tmp/ && sudo -u postgres psql -d socialdb -f /tmp/likes_nodo1.sql
```

### Carga en CockroachDB (un solo endpoint)

```bash
docker exec -it roach1 ./cockroach sql --insecure --database=socialdb --file=/tmp/users_nodo1.sql
# El motor distribuye automáticamente entre los 3 nodos
```

---

*Proyecto desarrollado para SI3009 Bases de Datos Avanzadas · Universidad · 2026-1*
