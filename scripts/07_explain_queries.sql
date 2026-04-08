-- =============================================================================
-- SI3009 | Proyecto 2 | Script 07: Consultas con EXPLAIN ANALYZE
-- =============================================================================

-- =============================================================================
-- CONSULTA 1: Feed de un usuario (OLTP — shard local)
-- =============================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.content, p.created_at, u.username
FROM posts p
JOIN users u ON p.user_id = u.id
WHERE p.user_id = 1500
ORDER BY p.created_at DESC
LIMIT 20;

-- =============================================================================
-- CONSULTA 2: Full scan sin índice (búsqueda por texto)
-- =============================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.content, p.created_at
FROM posts p
WHERE p.content ILIKE '%PostgreSQL%'
ORDER BY p.created_at DESC;

-- Recomendación (no ejecutar si ya existe):
-- CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- CREATE INDEX idx_posts_content_trgm ON posts USING gin(content gin_trgm_ops);

-- =============================================================================
-- CONSULTA 3: OLAP — usuarios con más publicaciones
-- =============================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    u.username,
    COUNT(p.id) AS total_posts,
    MAX(p.created_at) AS ultimo_post
FROM users u
JOIN posts p ON u.id = p.user_id
GROUP BY u.id, u.username
ORDER BY total_posts DESC
LIMIT 10;

-- Importante antes de ejecutar:
-- ANALYZE users;
-- ANALYZE posts;

-- =============================================================================
-- CONSULTA 4: Posts más populares (likes)
-- =============================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    p.id AS post_id,
    p.content,
    p.user_id,
    COUNT(l.user_id) AS total_likes
FROM posts p
LEFT JOIN likes l ON p.id = l.post_id
GROUP BY p.id, p.content, p.user_id
ORDER BY total_likes DESC
LIMIT 10;

-- Asegurar índice:
-- CREATE INDEX IF NOT EXISTS idx_likes_post_id ON likes(post_id);

-- =============================================================================
-- CONSULTA 5: Cross-shard simulado
-- =============================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.content, p.created_at, u.username
FROM posts p
JOIN users u ON p.user_id = u.id
WHERE p.user_id IN (100, 3500, 7200)
ORDER BY p.created_at DESC;

-- NOTA:
-- idx correcto debe ser:
-- CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id);

-- =============================================================================
-- RESUMEN DE RESULTADOS (llenar con datos reales)
-- =============================================================================
SELECT
    'CONSULTA 1: Feed local (Index Scan)' AS consulta,
    'PostgreSQL Nodo 1' AS motor,
    '~0.8 ms' AS latencia_p50,
    '~2 ms' AS latencia_p99
UNION ALL
SELECT 'CONSULTA 3: OLAP GROUP BY (Full Scan)', 'PostgreSQL Nodo 1', '~40 ms', '~90 ms'
UNION ALL
SELECT 'CONSULTA 5: Cross-shard (app merge)', 'PostgreSQL 3 nodos', '~80 ms', '~200 ms'
UNION ALL
SELECT 'CONSULTA 5: Cross-shard', 'CockroachDB', '~35 ms', '~90 ms';