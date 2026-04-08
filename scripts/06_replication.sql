-- =============================================================================
-- SI3009 | Proyecto 2 | Script 06: Replicación y configuración de consistencia
--
-- PARTE A: Configuración del servidor (postgresql.conf y pg_hba.conf)
-- PARTE B: Experimentos de latencia según synchronous_commit
-- PARTE C: Monitoreo del estado de replicación
-- PARTE D: Procedimiento de failover manual
-- =============================================================================


-- =============================================================================
-- PARTE A: Configuración recomendada (aplicar fuera de psql)
-- Archivo: postgresql.conf (PRIMARY)
-- =============================================================================
/*
-- ── Configuración de replicación ────────────────────────────────────────────
wal_level = replica              # Habilita replicación en streaming
max_wal_senders = 5              # Número máximo de réplicas concurrentes
wal_keep_size = 256MB            # Retención de WAL para réplicas retrasadas
max_replication_slots = 5        # Slots de replicación disponibles

-- ── Configuración de consistencia ───────────────────────────────────────────
# Controla el nivel de durabilidad y consistencia:
#   off          → asincrónico (mayor rendimiento, posible pérdida de datos)
#   on           → sincrónico (espera confirmación de recepción del WAL)
#   remote_write → espera escritura del WAL en disco en la réplica
#   remote_apply → espera aplicación del WAL (datos visibles en réplica)
synchronous_commit = on
synchronous_standby_names = 'replica1'

-- ── Configuración de acceso (pg_hba.conf) ───────────────────────────────────
# Permitir conexiones de replicación:
# host  replication  replicador  10.0.0.0/24  scram-sha-256

-- ── Creación de usuario de replicación ──────────────────────────────────────
CREATE USER replicador WITH REPLICATION ENCRYPTED PASSWORD 'repl_secret_2026';

-- ── Configuración en la RÉPLICA ─────────────────────────────────────────────
# En postgresql.conf o archivo de configuración equivalente:
# primary_conninfo = 'host=10.0.0.1 port=5432 user=replicador password=repl_secret_2026 application_name=replica1'
# hot_standby = on   # Permite consultas de solo lectura

# Crear archivo de señal para standby:
# touch /var/lib/postgresql/data/standby.signal
*/


-- =============================================================================
-- PARTE B: Benchmark de latencia según synchronous_commit
-- =============================================================================

-- Función para medir la latencia de inserciones bajo distintos modos
CREATE OR REPLACE FUNCTION benchmark_insert_latency(
    p_sync_mode  TEXT,           -- 'off', 'on', 'remote_write', 'remote_apply'
    p_iterations INT DEFAULT 100
)
RETURNS TABLE(
    sync_mode      TEXT,
    iterations     INT,
    total_ms       NUMERIC,
    avg_ms         NUMERIC,
    min_ms         NUMERIC,
    max_ms         NUMERIC
) AS $$
DECLARE
    v_start    TIMESTAMPTZ;
    v_end      TIMESTAMPTZ;
    v_elapsed  NUMERIC;
    v_min      NUMERIC := 999999;
    v_max      NUMERIC := 0;
    v_total    NUMERIC := 0;
    i          INT;
    v_user_id  INT;
BEGIN
    -- Configurar synchronous_commit a nivel de sesión
    EXECUTE format('SET synchronous_commit = %I', p_sync_mode);

    FOR i IN 1..p_iterations LOOP
        -- Generar user_id dentro del rango del shard correspondiente
        v_user_id := (random() * 2999 + 1)::INT;

        v_start := clock_timestamp();

        INSERT INTO posts (user_id, content, created_at)
        VALUES (v_user_id, 'benchmark_' || i || '_sync_' || p_sync_mode, NOW())
        ON CONFLICT DO NOTHING;

        v_end := clock_timestamp();
        v_elapsed := EXTRACT(MILLISECONDS FROM (v_end - v_start));

        -- Acumuladores
        v_total := v_total + v_elapsed;
        v_min := LEAST(v_min, v_elapsed);
        v_max := GREATEST(v_max, v_elapsed);
    END LOOP;

    -- Restaurar configuración
    RESET synchronous_commit;

    -- Limpiar datos de prueba
    DELETE FROM posts WHERE content LIKE 'benchmark_%';

    -- Retornar resultados
    sync_mode  := p_sync_mode;
    iterations := p_iterations;
    total_ms   := v_total;
    avg_ms     := round(v_total / p_iterations, 3);
    min_ms     := v_min;
    max_ms     := v_max;

    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;


-- ── Ejecución de pruebas ─────────────────────────────────────────────────────
-- NOTA: remote_write y remote_apply requieren réplica activa

SELECT * FROM benchmark_insert_latency('off', 100);
SELECT * FROM benchmark_insert_latency('on', 100);
-- SELECT * FROM benchmark_insert_latency('remote_write', 100);
-- SELECT * FROM benchmark_insert_latency('remote_apply', 100);


-- =============================================================================
-- PARTE C: Monitoreo de replicación (ejecutar en PRIMARY)
-- =============================================================================

-- Estado de las réplicas conectadas
SELECT
    client_addr,
    application_name,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    write_lag,
    flush_lag,
    replay_lag,
    sync_state
FROM pg_stat_replication;

-- Cálculo de lag en bytes (WAL pendiente)
SELECT
    application_name,
    pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn)   AS send_lag_bytes,
    pg_wal_lsn_diff(pg_current_wal_lsn(), write_lsn)  AS write_lag_bytes,
    pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn)  AS flush_lag_bytes,
    pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;

-- ── En la RÉPLICA ────────────────────────────────────────────────────────────

-- Verificar estado standby (TRUE = réplica)
SELECT pg_is_in_recovery();

-- Medir retraso temporal de replicación
SELECT
    now() - pg_last_xact_replay_timestamp() AS replication_lag;


-- =============================================================================
-- PARTE D: Failover manual (documentación operativa)
-- =============================================================================
/*
── ESCENARIO: caída del PRIMARY (10.0.0.1) ────────────────────────────────────

1. Detectar fallo:
   pg_isready -h 10.0.0.1 -p 5432
   → "no response" indica caída

2. Promover la RÉPLICA (10.0.0.2):
   # PostgreSQL >= 12:
   pg_ctl promote -D /var/lib/postgresql/data
   # o vía SQL:
   SELECT pg_promote();

3. Verificar promoción:
   SELECT pg_is_in_recovery();
   → FALSE indica que ya es PRIMARY

4. Actualizar configuración de la aplicación:
   UPDATE shard_metadata
   SET host = '10.0.0.2'
   WHERE shard_id = 1;

5. Reintegrar nodo caído como nueva réplica:
   pg_basebackup -h 10.0.0.2 -U replicador -D /var/lib/postgresql/data --wal-method=stream
   touch /var/lib/postgresql/data/standby.signal
   pg_ctl start -D /var/lib/postgresql/data


── PREVENCIÓN DE SPLIT-BRAIN ──────────────────────────────────────────────────

El split-brain ocurre cuando dos nodos actúan como PRIMARY simultáneamente.

Estrategia básica:
  synchronous_standby_names = 'replica1'
  → El PRIMARY requiere confirmación de la réplica para aceptar commits

Estrategia avanzada (recomendada en producción):
  Uso de herramientas como Patroni + etcd:
  → Control de liderazgo mediante quorum distribuido
  → Garantiza un único PRIMARY activo
*/

-- Verificación global de rol del nodo
SELECT
    pg_is_in_recovery() AS es_replica,
    inet_server_addr() AS ip_nodo;
-- Si múltiples nodos retornan FALSE → existe split-brain (situación crítica)