-- =============================================================================
-- SI3009 | Proyecto 2 | Script 07: Consultas con EXPLAIN ANALYZE
-- Propósito: documentar el plan de ejecución y medir latencia real
--
-- INSTRUCCIONES DE USO:
--   1. Ejecutar cada bloque por separado (no todo junto)
--   2. Copiar el output completo del EXPLAIN al README (sección 7)
--   3. Comparar los planes entre PostgreSQL y CockroachDB
--   4. Las consultas marcadas CROSS-SHARD requieren combinar resultados
--      en la aplicación (PostgreSQL no hace joins entre nodos nativamente)
--
-- Antes de ejecutar: asegurar estadísticas actualizadas
-- =============================================================================
ANALYZE users;
ANALYZE posts;
ANALYZE follows;
ANALYZE likes;


-- =============================================================================
-- CONSULTA 1: Feed local de un usuario (OLTP — Index Scan esperado)
-- Propósito: operación más frecuente de una red social
-- Ejecutar en: nodo donde vive el user_id (nodo 1 para user_id 1500)
-- Resultado esperado: Index Scan sobre idx_posts_user_created
-- =============================================================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    p.id,
    p.content,
    p.created_at,
    u.username
FROM posts p
JOIN users u ON p.user_id = u.id
WHERE p.user_id = 1500
ORDER BY p.created_at DESC
LIMIT 20;

-- ─── PEGAR OUTPUT AQUÍ (ejemplo de referencia) ────────────────────────────
-- Index Scan Backward using idx_posts_user_created on posts
--   Index Cond: (user_id = 1500)
--   Buffers: shared hit=4
-- Nested Loop
--   ->  Index Scan on users  (cost=0.15..8.17) (actual time=0.012..0.013)
-- Planning Time: 0.3 ms
-- Execution Time: 0.X ms   ← REEMPLAZAR CON VALOR REAL
-- ──────────────────────────────────────────────────────────────────────────


-- =============================================================================
-- CONSULTA 2: Búsqueda full-text sin índice especializado (Seq Scan)
-- Propósito: mostrar el costo de un Seq Scan y motivar el índice trgm
-- Ejecutar en: cualquier nodo
-- Resultado esperado: Seq Scan (sin índice trgm) — costoso a escala
-- =============================================================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    p.id,
    p.content,
    p.created_at,
    u.username
FROM posts p
JOIN users u ON p.user_id = u.id
WHERE p.content ILIKE '%PostgreSQL%'
ORDER BY p.created_at DESC;

-- ─── PEGAR OUTPUT AQUÍ ────────────────────────────────────────────────────
-- Gather Merge  (cost=...) (actual time=X..X rows=X loops=1)
--   ->  Sort  (cost=...)
--         ->  Seq Scan on posts  (cost=...) (actual time=... rows=X loops=1)
--               Filter: (content ~~* '%PostgreSQL%')
-- Planning Time: X ms
-- Execution Time: X ms   ← REEMPLAZAR CON VALOR REAL
-- ──────────────────────────────────────────────────────────────────────────

-- SOLUCIÓN: crear índice GIN para búsqueda de texto
-- CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- CREATE INDEX idx_posts_content_trgm ON posts USING gin(content gin_trgm_ops);
-- Luego re-ejecutar y comparar: el plan cambia a Bitmap Index Scan


-- =============================================================================
-- CONSULTA 3: OLAP — usuarios con más publicaciones (Hash Aggregate + Sort)
-- Propósito: medir costo de agregación sobre tabla grande
-- Ejecutar en: cualquier nodo (resultados parciales por nodo)
-- Resultado esperado: Hash Join + HashAggregate + Sort
-- =============================================================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    u.id,
    u.username,
    COUNT(p.id)          AS total_posts,
    MAX(p.created_at)    AS ultimo_post,
    MIN(p.created_at)    AS primer_post
FROM users u
JOIN posts p ON u.id = p.user_id
GROUP BY u.id, u.username
ORDER BY total_posts DESC
LIMIT 10;

-- ─── PEGAR OUTPUT AQUÍ ────────────────────────────────────────────────────
-- Limit  (cost=...) (actual time=X..X rows=10 loops=1)
--   ->  Sort  (cost=...) (actual time=...)
--         Sort Key: (count(p.id)) DESC
--         ->  HashAggregate  (cost=...) (actual time=... rows=X loops=1)
--               Group Key: u.id, u.username
--               ->  Hash Join  (cost=...) (actual time=...)
--                     Hash Cond: (p.user_id = u.id)
-- Planning Time: X ms
-- Execution Time: X ms   ← REEMPLAZAR CON VALOR REAL
-- ──────────────────────────────────────────────────────────────────────────


-- =============================================================================
-- CONSULTA 4: Posts más populares por likes (Hash Join + GroupAggregate)
-- Propósito: OLAP típico para ranking; mide uso de idx_likes_post_id
-- Ejecutar en: cualquier nodo (resultados parciales)
-- Resultado esperado: Hash Join entre posts y likes, Index Scan en likes
-- =============================================================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    p.id          AS post_id,
    p.content,
    u.username    AS autor,
    COUNT(l.user_id) AS total_likes
FROM posts p
JOIN users u ON p.user_id = u.id
LEFT JOIN likes l ON p.id = l.post_id
GROUP BY p.id, p.content, u.username, u.id
ORDER BY total_likes DESC
LIMIT 10;

-- ─── PEGAR OUTPUT AQUÍ ────────────────────────────────────────────────────
-- Limit  (cost=...) (actual time=X..X rows=10 loops=1)
--   ->  Sort
--         ->  HashAggregate
--               ->  Hash Left Join
--                     Hash Cond: (p.id = l.post_id)
--                     ->  Hash Join
--                           Hash Cond: (p.user_id = u.id)
-- Planning Time: X ms
-- Execution Time: X ms   ← REEMPLAZAR CON VALOR REAL
-- ──────────────────────────────────────────────────────────────────────────


-- =============================================================================
-- CONSULTA 5: Followers de un usuario (quién me sigue) — Index Scan
-- Propósito: operación OLTP frecuente, debe usar idx_follows_followed_id
-- Ejecutar en: nodo del followed_id (nodo 1 para user_id 1)
-- =============================================================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    f.follower_id,
    u.username   AS follower_username,
    f.created_at AS since
FROM follows f
JOIN users u ON f.follower_id = u.id
WHERE f.followed_id = 1
ORDER BY f.created_at DESC;

-- ─── PEGAR OUTPUT AQUÍ ────────────────────────────────────────────────────
-- Nested Loop  (cost=...) (actual time=X..X rows=X loops=1)
--   ->  Index Scan using idx_follows_followed_id on follows
--         Index Cond: (followed_id = 1)
--   ->  Index Scan using users_pkey on users
--         Index Cond: (id = f.follower_id)
-- Planning Time: X ms
-- Execution Time: X ms   ← REEMPLAZAR CON VALOR REAL
-- ──────────────────────────────────────────────────────────────────────────


-- =============================================================================
-- CONSULTA 6: JOIN CROSS-SHARD SIMULADO
-- Propósito: documentar el impacto de cruzar datos de nodos distintos
-- En PostgreSQL manual NO hay join nativo entre nodos.
-- Esta consulta simula el resultado que la aplicación debe combinar.
--
-- ESTRATEGIA DOCUMENTADA:
--   Paso A — ejecutar en nodo 1: obtener datos de user_ids 1–3000
--   Paso B — ejecutar en nodo 2: obtener datos de user_ids 3001–6000
--   Paso C — combinar en la aplicación (Python, por ejemplo)
--
-- Contrastar con CockroachDB donde la misma consulta se ejecuta una sola vez
-- =============================================================================

-- PASO A: ejecutar en NODO 1
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    p.id,
    p.content,
    p.created_at,
    u.username,
    1 AS source_shard
FROM posts p
JOIN users u ON p.user_id = u.id
WHERE p.user_id IN (1, 2, 5, 8, 10)   -- user_ids del nodo 1
ORDER BY p.created_at DESC;

-- PASO B: ejecutar en NODO 2
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    p.id,
    p.content,
    p.created_at,
    u.username,
    2 AS source_shard
FROM posts p
JOIN users u ON p.user_id = u.id
WHERE p.user_id IN (3001, 3002, 3500)   -- user_ids del nodo 2
ORDER BY p.created_at DESC;

-- ─── PEGAR AMBOS OUTPUTS AQUÍ ─────────────────────────────────────────────
-- Nodo 1: Planning Time X ms / Execution Time X ms
-- Nodo 2: Planning Time X ms / Execution Time X ms
-- Latencia total (app merge): X ms   ← suma + overhead de red
-- CockroachDB misma consulta: X ms   ← REEMPLAZAR CON VALOR REAL
-- ──────────────────────────────────────────────────────────────────────────


-- =============================================================================
-- CONSULTA 7: Vista v_user_stats (complejidad de múltiples JOINs)
-- Propósito: medir plan de ejecución de la vista materializada
-- =============================================================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT *
FROM v_user_stats
WHERE user_id BETWEEN 1 AND 100
ORDER BY total_posts DESC;

-- ─── PEGAR OUTPUT AQUÍ ────────────────────────────────────────────────────
-- Planning Time: X ms
-- Execution Time: X ms   ← REEMPLAZAR CON VALOR REAL
-- ──────────────────────────────────────────────────────────────────────────


-- =============================================================================
-- CONSULTA 8: Benchmark comparativo — misma consulta en PG vs CockroachDB
-- Ejecutar primero en PostgreSQL Nodo 1, luego en CockroachDB
-- Documentar diferencia en planning time y execution time
-- =============================================================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    u.username,
    COUNT(DISTINCT p.id)   AS posts,
    COUNT(DISTINCT f.followed_id) AS following,
    COUNT(DISTINCT l.post_id)     AS likes_dado
FROM users u
LEFT JOIN posts  p ON u.id = p.user_id
LEFT JOIN follows f ON u.id = f.follower_id
LEFT JOIN likes  l ON u.id = l.user_id
WHERE u.id BETWEEN 1 AND 500
GROUP BY u.id, u.username
ORDER BY posts DESC
LIMIT 20;

-- ─── PEGAR OUTPUT AQUÍ ────────────────────────────────────────────────────
-- [PostgreSQL Nodo 1]
-- Planning Time: X ms
-- Execution Time: X ms
--
-- [CockroachDB — misma consulta]
-- Planning Time: X ms
-- Execution Time: X ms
-- ──────────────────────────────────────────────────────────────────────────


-- =============================================================================
-- TABLA RESUMEN DE RESULTADOS
-- Completar con valores reales después de ejecutar todas las consultas
-- Copiar esta tabla al README.md (sección 7 — Experimentos y resultados)
-- =============================================================================

SELECT
    'C1: Feed local (Index Scan)'              AS consulta,
    'Nodo 1 PostgreSQL'                         AS motor,
    'X ms'                                      AS latencia_p50,
    'X ms'                                      AS latencia_p99,
    'Index Scan (idx_posts_user_created)'       AS plan
UNION ALL SELECT
    'C2: Full-text sin índice (Seq Scan)',
    'Nodo 1 PostgreSQL', 'X ms', 'X ms',
    'Seq Scan — sin índice trgm'
UNION ALL SELECT
    'C3: OLAP GROUP BY usuarios',
    'Nodo 1 PostgreSQL', 'X ms', 'X ms',
    'HashAggregate + Hash Join'
UNION ALL SELECT
    'C4: Posts más populares (likes)',
    'Nodo 1 PostgreSQL', 'X ms', 'X ms',
    'Hash Left Join + Sort'
UNION ALL SELECT
    'C5: Followers de usuario (Index Scan)',
    'Nodo 1 PostgreSQL', 'X ms', 'X ms',
    'Index Scan (idx_follows_followed_id)'
UNION ALL SELECT
    'C6: Cross-shard (2 nodos, app merge)',
    '2 nodos PostgreSQL', 'X ms', 'X ms',
    'Seq paralelo + merge en app'
UNION ALL SELECT
    'C6: Cross-shard equivalente',
    'CockroachDB 3 nodos', 'X ms', 'X ms',
    'Distributed scan (automático)'
UNION ALL SELECT
    'C8: Benchmark perfil usuario',
    'Nodo 1 PostgreSQL', 'X ms', 'X ms',
    'Hash Join múltiple'
UNION ALL SELECT
    'C8: Benchmark perfil usuario',
    'CockroachDB 3 nodos', 'X ms', 'X ms',
    'Distributed Hash Join';

-- =============================================================================
-- NOTAS PARA EL README
-- =============================================================================
-- Al documentar cada EXPLAIN ANALYZE en el README, incluir:
--   1. El plan completo (texto o imagen)
--   2. Los campos clave: Planning Time, Execution Time, tipo de scan
--   3. Buffers: shared hit vs shared read (indica uso de caché)
--   4. Comparación entre nodos (¿varía el plan entre nodo 1, 2 y 3?)
--   5. Para CockroachDB: mencionar si aparece "distributed" en el plan
-- =============================================================================