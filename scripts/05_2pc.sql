-- =============================================================================
-- SI3009 | Proyecto 2 | Script 05: Two-Phase Commit (2PC) - ESTABLE
-- =============================================================================
--
-- Nota clave:
-- En este modelo con sharding manual, las FK locales hacen que insertar la misma
-- fila de follows/likes en nodos distintos pueda fallar por integridad.
-- Para demostrar 2PC de forma robusta, se usa una tabla de auditoria sin FK.
--
-- Este script se ejecuta por pasos en dos terminales psql (nodo A y nodo B).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0) Prerrequisito (una vez por nodo)
-- -----------------------------------------------------------------------------
-- ALTER SYSTEM SET max_prepared_transactions = 20;
-- SELECT pg_reload_conf();
SHOW max_prepared_transactions;

-- -----------------------------------------------------------------------------
-- 1) Tabla de apoyo para demostrar transaccion distribuida (ejecutar en cada nodo)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS distributed_ops_log (
    gid         TEXT PRIMARY KEY,
    op_name     TEXT NOT NULL,
    source_node TEXT NOT NULL,
    created_at  TIMESTAMP DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 2) Caso principal: operacion distribuida NODO1 + NODO2
-- -----------------------------------------------------------------------------
-- GID logico global de la transaccion:
--   2pc_demo_2026_01
--
-- Paso A (en NODO 1):
-- BEGIN;
-- INSERT INTO distributed_ops_log (gid, op_name, source_node)
-- VALUES ('2pc_demo_2026_01_n1', 'follow_cross_shard', 'nodo1')
-- ON CONFLICT (gid) DO NOTHING;
-- PREPARE TRANSACTION '2pc_demo_2026_01_n1';
--
-- Paso B (en NODO 2):
-- BEGIN;
-- INSERT INTO distributed_ops_log (gid, op_name, source_node)
-- VALUES ('2pc_demo_2026_01_n2', 'follow_cross_shard', 'nodo2')
-- ON CONFLICT (gid) DO NOTHING;
-- PREPARE TRANSACTION '2pc_demo_2026_01_n2';
--
-- Paso C (coordinador, fase 2):
-- Si ambos PREPARE fueron exitosos:
--   En NODO 1: COMMIT PREPARED '2pc_demo_2026_01_n1';
--   En NODO 2: COMMIT PREPARED '2pc_demo_2026_01_n2';
--
-- Si alguno falla:
--   En NODO 1: ROLLBACK PREPARED '2pc_demo_2026_01_n1';
--   En NODO 2: ROLLBACK PREPARED '2pc_demo_2026_01_n2';

-- -----------------------------------------------------------------------------
-- 3) Monitoreo y verificacion
-- -----------------------------------------------------------------------------
SELECT gid, prepared, owner, database
FROM pg_prepared_xacts
ORDER BY prepared;

-- Verificar resultados locales despues del COMMIT PREPARED:
SELECT *
FROM distributed_ops_log
ORDER BY created_at DESC
LIMIT 20;

-- -----------------------------------------------------------------------------
-- 4) Limpieza de transacciones huerfanas (si aplica)
-- -----------------------------------------------------------------------------
-- ROLLBACK PREPARED '2pc_demo_2026_01_n1';
-- ROLLBACK PREPARED '2pc_demo_2026_01_n2';