-- =============================================================================
-- SI3009 | Proyecto 2 | Script 03: Datos de prueba mínimos (CORREGIDO)
-- Insertar solo en el nodo correspondiente según el rango de user_id.
-- =============================================================================

-- =============================================================================
-- NODO 1: user_id 1–20
-- =============================================================================

INSERT INTO users (id, username, email, bio) VALUES
  (1,  'alice_n1',   'alice@example.com',   'Diseñadora UX en Medellín'),
  (2,  'bob_dev',    'bob@example.com',     'Backend engineer, Python lover'),
  (3,  'carol_pm',   'carol@example.com',   'Product manager, café adicta'),
  (4,  'david_ml',   'david@example.com',   'ML engineer, fan de Kaggle'),
  (5,  'eva_data',   'eva@example.com',     'Data analyst, SQL nerd'),
  (6,  'frank_ops',  'frank@example.com',   'SRE, Kubernetes everywhere'),
  (7,  'grace_fe',   'grace@example.com',   'Frontend con React y amor'),
  (8,  'henry_db',   'henry@example.com',   'DBA PostgreSQL 10+ años'),
  (9,  'iris_sec',   'iris@example.com',    'Security researcher'),
  (10, 'jack_arch',  'jack@example.com',    'Software architect, DDD'),
  (11, 'karen_ux',   'karen@example.com',   'UX researcher'),
  (12, 'luis_cloud', 'luis@example.com',    'Cloud architect AWS/GCP'),
  (13, 'marta_bi',   'marta@example.com',   'Business Intelligence'),
  (14, 'nico_api',   'nico@example.com',    'API first siempre'),
  (15, 'olivia_qa',  'olivia@example.com',  'QA automation engineer'),
  (16, 'pablo_ios',  'pablo@example.com',   'iOS developer, Swift'),
  (17, 'quinn_and',  'quinn@example.com',   'Android dev, Kotlin'),
  (18, 'rosa_devrel','rosa@example.com',    'Developer relations'),
  (19, 'sam_sre',    'sam@example.com',     'SRE on-call siempre'),
  (20, 'tina_cto',   'tina@example.com',    'CTO startup FinTech')
ON CONFLICT (id) DO NOTHING;

-- ⚠️ IMPORTANTE: agregar ID manual (porque quitamos SERIAL)
INSERT INTO posts (id, user_id, content, created_at) VALUES
  (1, 1,  'PostgreSQL distribuido: más complejo de lo que parece 🤯', NOW() - INTERVAL '10 days'),
  (2, 1,  'EXPLAIN ANALYZE es tu mejor amigo en producción', NOW() - INTERVAL '8 days'),
  (3, 2,  'Python + psycopg2 para enrutar entre shards manualmente', NOW() - INTERVAL '9 days'),
  (4, 2,  '2PC en PostgreSQL: funciona pero es frágil bajo fallos del coordinador', NOW() - INTERVAL '7 days'),
  (5, 3,  'El teorema CAP no es binario, es un espectro en la práctica', NOW() - INTERVAL '6 days'),
  (6, 4,  'CockroachDB vs YugabyteDB: ambos usan Raft, diferencias en SQL compat.', NOW() - INTERVAL '5 days'),
  (7, 5,  'synchronous_commit=on: +10ms de latencia pero 0 pérdida de datos', NOW() - INTERVAL '4 days'),
  (8, 6,  'Failover manual en PostgreSQL: Patroni lo hace más llevadero', NOW() - INTERVAL '3 days'),
  (9, 7,  'React + WebSockets para notificaciones en tiempo real en redes sociales', NOW() - INTERVAL '2 days'),
  (10, 8, 'Hot spots en sharding por hash: el problema que nadie te cuenta', NOW() - INTERVAL '1 day'),
  (11, 9, 'Split-brain: el escenario de pesadilla en sistemas distribuidos', NOW() - INTERVAL '12 hours'),
  (12, 10,'SAGA pattern > 2PC cuando puedes aceptar consistencia eventual', NOW() - INTERVAL '6 hours'),
  (13, 11,'Raft consensus: el algoritmo que hace posibles los NewSQL', NOW() - INTERVAL '3 hours'),
  (14, 12,'S3 + RDS vs EC2 + PostgreSQL manual: el análisis de costos que te sorprenderá', NOW() - INTERVAL '1 hour'),
  (15, 13,'Data locality en sharding: mantener user_id juntos reduce latencia cross-shard', NOW()),
  (16, 14,'API Gateway + múltiples bases de datos: el reto de consistencia eventual', NOW() - INTERVAL '45 minutes'),
  (17, 15,'Tests de carga con pgbench sobre un cluster de 3 nodos: resultados', NOW() - INTERVAL '30 minutes'),
  (18, 16,'Replicación lógica en PostgreSQL: más flexible que la física, más compleja', NOW() - INTERVAL '20 minutes'),
  (19, 17,'CockroachDB sobrevivió la caída de un nodo sin que yo hiciera nada 🚀', NOW() - INTERVAL '15 minutes'),
  (20, 18,'Developer relations: explicar CAP/PACELC a equipos no técnicos es el reto', NOW() - INTERVAL '10 minutes'),
  (21, 19,'On-call con una base distribuida mal configurada: no le deseo eso a nadie', NOW() - INTERVAL '5 minutes'),
  (22, 20,'Migrar de monolito a microservicios con CQRS: la experiencia de Rappi Colombia', NOW() - INTERVAL '2 minutes')
ON CONFLICT (id) DO NOTHING;

-- Follows (igual)
INSERT INTO follows (follower_id, followed_id) VALUES
  (1, 2), (1, 3), (1, 4), (1, 8),
  (2, 1), (2, 5), (2, 10),
  (3, 1), (3, 7), (3, 20),
  (4, 5), (4, 8), (4, 12),
  (5, 4), (5, 13), (5, 3001),
  (6, 1), (6, 19), (6, 6001),
  (7, 1), (7, 3), (7, 3500),
  (8, 2), (8, 4), (8, 7000),
  (9, 10), (9, 6), (9, 4000),
  (10, 9), (10, 11), (10, 5000)
ON CONFLICT DO NOTHING;

-- Likes (igual)
INSERT INTO likes (user_id, post_id) VALUES
  (1, 1), (1, 2), (1, 5), (1, 10),
  (2, 1), (2, 3), (2, 7),
  (3, 2), (3, 4), (3, 8),
  (4, 5), (4, 6), (4, 9),
  (5, 3), (5, 7), (5, 11),
  (6, 8), (6, 12), (6, 15),
  (7, 9), (7, 13), (7, 16),
  (8, 10), (8, 14), (8, 17),
  (9, 11), (9, 15), (9, 18),
  (10, 12), (10, 16), (10, 19)
ON CONFLICT DO NOTHING;

-- Verificación
SELECT 'users' AS tabla, COUNT(*) FROM users
UNION ALL
SELECT 'posts', COUNT(*) FROM posts
UNION ALL
SELECT 'follows', COUNT(*) FROM follows
UNION ALL
SELECT 'likes', COUNT(*) FROM likes;