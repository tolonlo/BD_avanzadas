-- =============================================================================
-- SI3009 | Proyecto 2 | Script 03: Datos de prueba mínimos
-- Propósito: validar el schema antes de cargar generate_data.py
-- IMPORTANTE: ejecutar cada bloque SOLO en el nodo correspondiente
-- =============================================================================
-- Orden de ejecución:
--   1. Nodo 1 (10.0.0.1): bloque NODO 1
--   2. Nodo 2 (10.0.0.2): bloque NODO 2
--   3. Nodo 3 (10.0.0.3): bloque NODO 3
--   4. Cualquier nodo:    bloque CROSS-SHARD (follows y likes)
-- =============================================================================


-- =============================================================================
-- NODO 1 — user_id 1 a 3000 (ejecutar en 10.0.0.1)
-- =============================================================================

INSERT INTO users (id, username, email, bio, created_at) VALUES
  (1,  'alice_ux',    'alice@socialdb.co',   'Diseñadora UX en Medellín',              NOW() - INTERVAL '300 days'),
  (2,  'bob_dev',     'bob@socialdb.co',     'Backend engineer, Python lover',          NOW() - INTERVAL '280 days'),
  (3,  'carol_pm',    'carol@socialdb.co',   'Product manager, café adicta',            NOW() - INTERVAL '260 days'),
  (4,  'david_ml',    'david@socialdb.co',   'ML engineer, fan de Kaggle',              NOW() - INTERVAL '240 days'),
  (5,  'eva_data',    'eva@socialdb.co',     'Data analyst, SQL nerd',                  NOW() - INTERVAL '220 days'),
  (6,  'frank_sre',   'frank@socialdb.co',   'SRE, Kubernetes everywhere',              NOW() - INTERVAL '200 days'),
  (7,  'grace_fe',    'grace@socialdb.co',   'Frontend con React y amor',               NOW() - INTERVAL '180 days'),
  (8,  'henry_dba',   'henry@socialdb.co',   'DBA PostgreSQL 10+ años',                 NOW() - INTERVAL '160 days'),
  (9,  'iris_sec',    'iris@socialdb.co',    'Security researcher',                     NOW() - INTERVAL '140 days'),
  (10, 'jack_arch',   'jack@socialdb.co',    'Software architect, DDD fan',             NOW() - INTERVAL '120 days'),
  (11, 'karen_bi',    'karen@socialdb.co',   'Business intelligence analyst',           NOW() - INTERVAL '100 days'),
  (12, 'luis_cloud',  'luis@socialdb.co',    'Cloud architect AWS y GCP',               NOW() - INTERVAL '90 days'),
  (13, 'marta_api',   'marta@socialdb.co',   'API-first siempre',                       NOW() - INTERVAL '80 days'),
  (14, 'nico_qa',     'nico@socialdb.co',    'QA automation engineer',                  NOW() - INTERVAL '70 days'),
  (15, 'olivia_ios',  'olivia@socialdb.co',  'iOS developer, Swift lover',              NOW() - INTERVAL '60 days'),
  (500,  'maria_mid', 'maria@socialdb.co',   'Usuario mitad del shard 1',               NOW() - INTERVAL '50 days'),
  (1500, 'pedro_1500','pedro1500@socialdb.co','Usuario representativo nodo 1',           NOW() - INTERVAL '40 days'),
  (2999, 'ultimo_n1', 'ultimo_n1@socialdb.co','Último usuario válido del nodo 1',       NOW() - INTERVAL '30 days')
ON CONFLICT (id) DO NOTHING;

INSERT INTO posts (id, user_id, content, created_at) VALUES
  (1,  1,  'PostgreSQL distribuido: más complejo de lo que parece',        NOW() - INTERVAL '290 days'),
  (2,  1,  'EXPLAIN ANALYZE es tu mejor amigo en producción',               NOW() - INTERVAL '285 days'),
  (3,  2,  'Python + psycopg2 para enrutar entre shards manualmente',       NOW() - INTERVAL '279 days'),
  (4,  2,  '2PC en PostgreSQL: funciona pero es frágil bajo fallos',        NOW() - INTERVAL '270 days'),
  (5,  3,  'El teorema CAP no es binario, es un espectro en la práctica',   NOW() - INTERVAL '260 days'),
  (6,  4,  'CockroachDB vs YugabyteDB: ambos usan Raft, diferencias en SQL',NOW() - INTERVAL '250 days'),
  (7,  5,  'synchronous_commit=on: +10ms de latencia pero 0 pérdida datos', NOW() - INTERVAL '240 days'),
  (8,  6,  'Failover manual en PostgreSQL: Patroni lo hace más llevadero',  NOW() - INTERVAL '230 days'),
  (9,  7,  'Hot spots en sharding por hash: el problema que nadie te cuenta',NOW() - INTERVAL '220 days'),
  (10, 8,  'Split-brain: el escenario de pesadilla en sistemas distribuidos',NOW() - INTERVAL '210 days'),
  (11, 9,  'Raft consensus: el algoritmo que hace posibles los NewSQL',     NOW() - INTERVAL '200 days'),
  (12, 10, 'SAGA pattern > 2PC cuando puedes aceptar consistencia eventual', NOW() - INTERVAL '190 days'),
  (13, 11, 'Data locality: mantener user_id juntos reduce latencia cross-shard', NOW() - INTERVAL '180 days'),
  (14, 12, 'S3 + RDS vs EC2 + PostgreSQL: el análisis de costos real',     NOW() - INTERVAL '170 days'),
  (15, 13, 'API Gateway con múltiples bases: reto de consistencia eventual', NOW() - INTERVAL '160 days'),
  (16, 14, 'Tests de carga con pgbench sobre cluster de 3 nodos: resultados',NOW() - INTERVAL '150 days'),
  (17, 15, 'Replicación lógica en PostgreSQL: flexible pero compleja',      NOW() - INTERVAL '140 days'),
  (18, 1,  'Post adicional: impacto de índices compuestos en shard local',  NOW() - INTERVAL '30 days'),
  (19, 2,  'Post adicional: benchmark synchronous_commit off vs on',        NOW() - INTERVAL '20 days'),
  (20, 5,  'Post adicional: OLAP en nodo 1, GROUP BY con 50k registros',    NOW() - INTERVAL '10 days')
ON CONFLICT (id) DO NOTHING;


-- =============================================================================
-- NODO 2 — user_id 3001 a 6000 (ejecutar en 10.0.0.2)
-- =============================================================================

INSERT INTO users (id, username, email, bio, created_at) VALUES
  (3001, 'ana_n2',     'ana_n2@socialdb.co',    'Primera usuaria del nodo 2',            NOW() - INTERVAL '300 days'),
  (3002, 'bruno_n2',   'bruno_n2@socialdb.co',  'Desarrollador full stack nodo 2',       NOW() - INTERVAL '280 days'),
  (3003, 'camila_n2',  'camila_n2@socialdb.co', 'Data scientist, pandas expert',         NOW() - INTERVAL '260 days'),
  (3004, 'diego_n2',   'diego_n2@socialdb.co',  'DevOps engineer, CI/CD fan',            NOW() - INTERVAL '240 days'),
  (3005, 'elena_n2',   'elena_n2@socialdb.co',  'Frontend developer, Vue.js',            NOW() - INTERVAL '220 days'),
  (3006, 'Felipe_n2',  'felipe_n2@socialdb.co', 'Backend Golang, microservicios',        NOW() - INTERVAL '200 days'),
  (3007, 'gabriela_n2','gabriela_n2@socialdb.co','UX researcher, design systems',        NOW() - INTERVAL '180 days'),
  (3008, 'hector_n2',  'hector_n2@socialdb.co', 'Arquitecto de soluciones cloud',        NOW() - INTERVAL '160 days'),
  (3500, 'mid_n2',     'mid_n2@socialdb.co',    'Usuario mitad del shard 2',             NOW() - INTERVAL '120 days'),
  (5999, 'penult_n2',  'penult_n2@socialdb.co', 'Penúltimo usuario del nodo 2',          NOW() - INTERVAL '60 days'),
  (6000, 'ultimo_n2',  'ultimo_n2@socialdb.co', 'Último usuario válido del nodo 2',      NOW() - INTERVAL '30 days')
ON CONFLICT (id) DO NOTHING;

INSERT INTO posts (id, user_id, content, created_at) VALUES
  (1001, 3001, 'Nodo 2 activo: sharding por rango funciona correctamente',       NOW() - INTERVAL '290 days'),
  (1002, 3002, 'Full stack con PostgreSQL distribuido: la experiencia',           NOW() - INTERVAL '270 days'),
  (1003, 3003, 'Pandas + psycopg2: leer de múltiples shards en paralelo',         NOW() - INTERVAL '250 days'),
  (1004, 3004, 'CI/CD con migraciones en cluster distribuido: los retos',         NOW() - INTERVAL '230 days'),
  (1005, 3005, 'Vue.js + WebSockets sobre arquitectura con múltiples replicas',   NOW() - INTERVAL '210 days'),
  (1006, 3006, 'Golang + pgx: pool de conexiones en sharding manual',             NOW() - INTERVAL '190 days'),
  (1007, 3007, 'Design systems para dashboards de monitoreo de BD distribuidas',  NOW() - INTERVAL '170 days'),
  (1008, 3008, 'Arquitectura cloud: cuándo usar RDS vs self-managed PostgreSQL',  NOW() - INTERVAL '150 days'),
  (1009, 3500, 'Post desde la mitad del shard 2: latencia cross-shard medida',    NOW() - INTERVAL '90 days'),
  (1010, 6000, 'Post desde el límite del shard 2: consistencia verificada',       NOW() - INTERVAL '15 days')
ON CONFLICT (id) DO NOTHING;


-- =============================================================================
-- NODO 3 — user_id 6001 a 10000 (ejecutar en 10.0.0.3)
-- =============================================================================

INSERT INTO users (id, username, email, bio, created_at) VALUES
  (6001, 'sofia_n3',   'sofia_n3@socialdb.co',  'Primera usuaria del nodo 3',            NOW() - INTERVAL '300 days'),
  (6002, 'tomas_n3',   'tomas_n3@socialdb.co',  'Backend Rust, performance obsessed',    NOW() - INTERVAL '280 days'),
  (6003, 'ursula_n3',  'ursula_n3@socialdb.co', 'ML ops engineer, MLflow expert',        NOW() - INTERVAL '260 days'),
  (6004, 'victor_n3',  'victor_n3@socialdb.co', 'Platform engineer, Terraform',          NOW() - INTERVAL '240 days'),
  (6005, 'wendy_n3',   'wendy_n3@socialdb.co',  'Data engineer, Spark y Airflow',        NOW() - INTERVAL '220 days'),
  (6006, 'xavier_n3',  'xavier_n3@socialdb.co', 'Security engineer, pentesting',         NOW() - INTERVAL '200 days'),
  (6007, 'yolanda_n3', 'yolanda_n3@socialdb.co','Product analyst, growth hacking',       NOW() - INTERVAL '180 days'),
  (6008, 'zeus_n3',    'zeus_n3@socialdb.co',   'CTO startup deep tech',                 NOW() - INTERVAL '160 days'),
  (7000, 'mid_n3',     'mid_n3@socialdb.co',    'Usuario mitad del shard 3',             NOW() - INTERVAL '120 days'),
  (9999, 'penult_n3',  'penult_n3@socialdb.co', 'Penúltimo usuario del nodo 3',          NOW() - INTERVAL '60 days'),
  (10000,'ultimo_n3',  'ultimo_n3@socialdb.co', 'Último usuario del cluster completo',   NOW() - INTERVAL '30 days')
ON CONFLICT (id) DO NOTHING;

INSERT INTO posts (id, user_id, content, created_at) VALUES
  (2001, 6001, 'Nodo 3: el shard más grande del cluster, user_id 6001–10000',    NOW() - INTERVAL '290 days'),
  (2002, 6002, 'Rust + tokio-postgres: máximo rendimiento en lecturas locales',  NOW() - INTERVAL '270 days'),
  (2003, 6003, 'MLflow sobre PostgreSQL distribuido: experimentos reproducibles',NOW() - INTERVAL '250 days'),
  (2004, 6004, 'Terraform para provisionar 3 nodos PostgreSQL en EC2 en minutos',NOW() - INTERVAL '230 days'),
  (2005, 6005, 'Airflow DAG para sincronizar datos entre shards periódicamente', NOW() - INTERVAL '210 days'),
  (2006, 6006, 'Auditoría de seguridad en cluster PostgreSQL: lo que encontré',  NOW() - INTERVAL '190 days'),
  (2007, 6007, 'Métricas de growth con consultas OLAP cross-shard: el costo',    NOW() - INTERVAL '170 days'),
  (2008, 6008, 'Decisión técnica: PostgreSQL distribuido vs CockroachDB en 2026',NOW() - INTERVAL '150 days'),
  (2009, 7000, 'Post desde mitad del shard 3: test de join local vs cross-shard',NOW() - INTERVAL '90 days'),
  (2010, 10000,'Post del último usuario: validación del extremo del cluster',    NOW() - INTERVAL '10 days')
ON CONFLICT (id) DO NOTHING;


-- =============================================================================
-- FOLLOWS CROSS-SHARD — ejecutar en TODOS los nodos relevantes
-- Estas relaciones cruzan shards intencionalmente para probar 2PC y joins
-- NOTA: insertar follower_id en el nodo donde vive ese usuario
-- =============================================================================

-- Follows intra-shard (nodo 1 → nodo 1)
INSERT INTO follows (follower_id, followed_id, created_at) VALUES
  (1,  2,   NOW() - INTERVAL '200 days'),
  (1,  3,   NOW() - INTERVAL '199 days'),
  (2,  1,   NOW() - INTERVAL '198 days'),
  (2,  5,   NOW() - INTERVAL '197 days'),
  (3,  8,   NOW() - INTERVAL '196 days'),
  (5,  10,  NOW() - INTERVAL '195 days'),
  (8,  4,   NOW() - INTERVAL '194 days'),
  (10, 15,  NOW() - INTERVAL '193 days')
ON CONFLICT DO NOTHING;

-- Follows cross-shard nodo 1 → nodo 2 (ejecutar en nodo 1)
INSERT INTO follows (follower_id, followed_id, created_at) VALUES
  (1,    3001, NOW() - INTERVAL '180 days'),
  (2,    3002, NOW() - INTERVAL '179 days'),
  (5,    3500, NOW() - INTERVAL '178 days'),
  (8,    6000, NOW() - INTERVAL '177 days'),
  (10,   3003, NOW() - INTERVAL '176 days'),
  (1500, 3001, NOW() - INTERVAL '175 days')
ON CONFLICT DO NOTHING;

-- Follows cross-shard nodo 1 → nodo 3 (ejecutar en nodo 1)
INSERT INTO follows (follower_id, followed_id, created_at) VALUES
  (1,    6001, NOW() - INTERVAL '160 days'),
  (3,    7000, NOW() - INTERVAL '159 days'),
  (7,    10000,NOW() - INTERVAL '158 days'),
  (1500, 6005, NOW() - INTERVAL '157 days')
ON CONFLICT DO NOTHING;

-- Follows intra-shard (nodo 2 → nodo 2) — ejecutar en nodo 2
INSERT INTO follows (follower_id, followed_id, created_at) VALUES
  (3001, 3002, NOW() - INTERVAL '140 days'),
  (3002, 3003, NOW() - INTERVAL '139 days'),
  (3003, 3500, NOW() - INTERVAL '138 days'),
  (3500, 6000, NOW() - INTERVAL '137 days')
ON CONFLICT DO NOTHING;

-- Follows cross-shard nodo 2 → nodo 3 (ejecutar en nodo 2)
INSERT INTO follows (follower_id, followed_id, created_at) VALUES
  (3001, 6001, NOW() - INTERVAL '120 days'),
  (3002, 7000, NOW() - INTERVAL '119 days'),
  (3500, 10000,NOW() - INTERVAL '118 days')
ON CONFLICT DO NOTHING;

-- Follows intra-shard (nodo 3 → nodo 3) — ejecutar en nodo 3
INSERT INTO follows (follower_id, followed_id, created_at) VALUES
  (6001, 6002, NOW() - INTERVAL '100 days'),
  (6002, 7000, NOW() - INTERVAL '99 days'),
  (7000, 10000,NOW() - INTERVAL '98 days')
ON CONFLICT DO NOTHING;


-- =============================================================================
-- LIKES CROSS-SHARD — ejecutar en el nodo donde vive el user_id
-- post_id puede pertenecer a cualquier nodo (cross-shard intencionalmente)
-- =============================================================================

-- Likes desde nodo 1 (user_id 1–15) a posts locales y remotos
INSERT INTO likes (user_id, post_id, created_at) VALUES
  -- likes a posts locales (mismo nodo)
  (1,  1,    NOW() - INTERVAL '289 days'),
  (1,  2,    NOW() - INTERVAL '284 days'),
  (2,  3,    NOW() - INTERVAL '278 days'),
  (3,  5,    NOW() - INTERVAL '259 days'),
  (4,  6,    NOW() - INTERVAL '249 days'),
  (5,  7,    NOW() - INTERVAL '239 days'),
  (6,  8,    NOW() - INTERVAL '229 days'),
  (7,  9,    NOW() - INTERVAL '219 days'),
  (8,  10,   NOW() - INTERVAL '209 days'),
  (9,  11,   NOW() - INTERVAL '199 days'),
  (10, 12,   NOW() - INTERVAL '189 days'),
  -- likes cross-shard: usuario nodo 1 → post nodo 2
  (1,  1001, NOW() - INTERVAL '150 days'),
  (2,  1002, NOW() - INTERVAL '149 days'),
  (5,  1005, NOW() - INTERVAL '148 days'),
  (8,  1009, NOW() - INTERVAL '147 days'),
  -- likes cross-shard: usuario nodo 1 → post nodo 3
  (1,  2001, NOW() - INTERVAL '130 days'),
  (3,  2003, NOW() - INTERVAL '129 days'),
  (10, 2008, NOW() - INTERVAL '128 days')
ON CONFLICT DO NOTHING;

-- Likes desde nodo 2 (user_id 3001–6000) — ejecutar en nodo 2
INSERT INTO likes (user_id, post_id, created_at) VALUES
  -- likes a posts locales
  (3001, 1001, NOW() - INTERVAL '288 days'),
  (3002, 1002, NOW() - INTERVAL '268 days'),
  (3003, 1003, NOW() - INTERVAL '248 days'),
  (3500, 1009, NOW() - INTERVAL '88 days'),
  -- likes cross-shard: usuario nodo 2 → post nodo 1
  (3001, 1,    NOW() - INTERVAL '200 days'),
  (3002, 5,    NOW() - INTERVAL '199 days'),
  (3500, 12,   NOW() - INTERVAL '170 days'),
  -- likes cross-shard: usuario nodo 2 → post nodo 3
  (3001, 2001, NOW() - INTERVAL '120 days'),
  (3003, 2005, NOW() - INTERVAL '110 days')
ON CONFLICT DO NOTHING;

-- Likes desde nodo 3 (user_id 6001–10000) — ejecutar en nodo 3
INSERT INTO likes (user_id, post_id, created_at) VALUES
  -- likes a posts locales
  (6001, 2001, NOW() - INTERVAL '285 days'),
  (6002, 2002, NOW() - INTERVAL '265 days'),
  (7000, 2009, NOW() - INTERVAL '85 days'),
  (10000,2010, NOW() - INTERVAL '8 days'),
  -- likes cross-shard: usuario nodo 3 → post nodo 1
  (6001, 1,    NOW() - INTERVAL '200 days'),
  (6002, 11,   NOW() - INTERVAL '190 days'),
  (7000, 17,   NOW() - INTERVAL '130 days'),
  -- likes cross-shard: usuario nodo 3 → post nodo 2
  (6001, 1001, NOW() - INTERVAL '110 days'),
  (7000, 1008, NOW() - INTERVAL '100 days')
ON CONFLICT DO NOTHING;


-- =============================================================================
-- VERIFICACIÓN FINAL (ejecutar en cada nodo)
-- =============================================================================
SELECT
    'users'   AS tabla, COUNT(*) AS registros FROM users
UNION ALL SELECT
    'posts',   COUNT(*) FROM posts
UNION ALL SELECT
    'follows', COUNT(*) FROM follows
UNION ALL SELECT
    'likes',   COUNT(*) FROM likes;

-- Verificar distribución de follows cross-shard
SELECT
    CASE
        WHEN follower_id BETWEEN 1    AND 3000  THEN 'nodo1'
        WHEN follower_id BETWEEN 3001 AND 6000  THEN 'nodo2'
        WHEN follower_id BETWEEN 6001 AND 10000 THEN 'nodo3'
    END AS shard_follower,
    CASE
        WHEN followed_id BETWEEN 1    AND 3000  THEN 'nodo1'
        WHEN followed_id BETWEEN 3001 AND 6000  THEN 'nodo2'
        WHEN followed_id BETWEEN 6001 AND 10000 THEN 'nodo3'
    END AS shard_followed,
    COUNT(*) AS total
FROM follows
GROUP BY 1, 2
ORDER BY 1, 2;