-- =============================================================================
-- SI3009 | Proyecto 2 | Script 05: Two-Phase Commit (2PC) - CORREGIDO
-- =============================================================================

-- -----------------------------------------------------------------------------
-- PREREQUISITO (EJECUTAR UNA VEZ POR NODO)
-- -----------------------------------------------------------------------------
-- ALTER SYSTEM SET max_prepared_transactions = 10;
-- SELECT pg_reload_conf();

-- Verificar:
SHOW max_prepared_transactions;

-- =============================================================================
-- CASO 1: FOLLOW CROSS-SHARD
-- =============================================================================

-- ── NODO 1 ────────────────────────────────────────────────────────────────────
BEGIN;

INSERT INTO follows (follower_id, followed_id)
VALUES (100, 4500)
ON CONFLICT (follower_id, followed_id) DO NOTHING;

-- ⚠️ GID único global (IMPORTANTE)
PREPARE TRANSACTION '2pc_follow_100_4500_n1';

-- ── NODO 2 ────────────────────────────────────────────────────────────────────
BEGIN;

INSERT INTO follows (follower_id, followed_id)
VALUES (100, 4500)
ON CONFLICT (follower_id, followed_id) DO NOTHING;

PREPARE TRANSACTION '2pc_follow_100_4500_n2';

-- ── COORDINADOR (FASE 2) ──────────────────────────────────────────────────────
-- Ejecutar en cada nodo por separado

-- Nodo 1:
COMMIT PREPARED '2pc_follow_100_4500_n1';

-- Nodo 2:
COMMIT PREPARED '2pc_follow_100_4500_n2';

-- -----------------------------------------------------------------------------
-- Alternativa en caso de fallo:
-- ROLLBACK PREPARED '2pc_follow_100_4500_n1';
-- ROLLBACK PREPARED '2pc_follow_100_4500_n2';
-- -----------------------------------------------------------------------------

-- =============================================================================
-- CASO 2: LIKE CROSS-SHARD
-- =============================================================================

-- ── NODO 1 ────────────────────────────────────────────────────────────────────
BEGIN;

INSERT INTO likes (user_id, post_id)
VALUES (200, 9999)
ON CONFLICT (user_id, post_id) DO NOTHING;

PREPARE TRANSACTION '2pc_like_200_9999_n1';

-- ── NODO 3 ────────────────────────────────────────────────────────────────────
BEGIN;

-- Simulación (auditoría o desnormalización)
INSERT INTO likes (user_id, post_id)
VALUES (200, 9999)
ON CONFLICT (user_id, post_id) DO NOTHING;

PREPARE TRANSACTION '2pc_like_200_9999_n3';

-- Commit coordinado:

-- Nodo 1:
COMMIT PREPARED '2pc_like_200_9999_n1';

-- Nodo 3:
COMMIT PREPARED '2pc_like_200_9999_n3';

-- =============================================================================
-- MONITOREO
-- =============================================================================
SELECT
    gid,
    prepared,
    owner,
    database
FROM pg_prepared_xacts
ORDER BY prepared;

-- =============================================================================
-- LIMPIEZA (si hay transacciones huérfanas)
-- =============================================================================
-- ROLLBACK PREPARED 'gid_aqui';