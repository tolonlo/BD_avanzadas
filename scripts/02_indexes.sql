-- =============================================================================
-- SI3009 | Proyecto 2 | Script 02: Índices por partición (CORREGIDO)
-- Aplicar en CADA nodo después de Script 01
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Índices sobre posts
-- -----------------------------------------------------------------------------

-- 🔥 CLAVE: índice compuesto (cubre el simple de user_id)
CREATE INDEX IF NOT EXISTS idx_posts_user_created
    ON posts (user_id, created_at DESC);

-- Índice para consultas por fecha (OLAP)
CREATE INDEX IF NOT EXISTS idx_posts_created_at
    ON posts (created_at DESC);

-- -----------------------------------------------------------------------------
-- Índices sobre follows
-- -----------------------------------------------------------------------------

-- Para: ¿Quién me sigue?
CREATE INDEX IF NOT EXISTS idx_follows_followed_id
    ON follows (followed_id);

-- Para: orden cronológico de seguidos
CREATE INDEX IF NOT EXISTS idx_follows_follower_created
    ON follows (follower_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- Índices sobre likes
-- -----------------------------------------------------------------------------

-- Para: conteo de likes por post
CREATE INDEX IF NOT EXISTS idx_likes_post_id
    ON likes (post_id);

-- Para: likes recientes por post
CREATE INDEX IF NOT EXISTS idx_likes_post_created
    ON likes (post_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- Índices sobre users
-- -----------------------------------------------------------------------------

-- ⚠️ username ya es UNIQUE → índice implícito (NO necesario)
-- CREATE INDEX idx_users_username ON users(username);

-- Para: usuarios recientes
CREATE INDEX IF NOT EXISTS idx_users_created_at
    ON users (created_at DESC);

-- -----------------------------------------------------------------------------
-- Verificación: índices y tamaños
-- -----------------------------------------------------------------------------
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;