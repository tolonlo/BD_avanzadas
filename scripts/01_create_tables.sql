-- =============================================================================
-- SI3009 | Proyecto 2 | Script 01: Creación de tablas base (CORREGIDO)
-- Ejecutar en cada nodo ajustando el CHECK de rango
-- =============================================================================

-- -----------------------------------------------------------------------------
-- CONFIGURACIÓN POR NODO (EDITAR)
-- -----------------------------------------------------------------------------
-- Nodo 1:
-- CHECK (id BETWEEN 1 AND 3000)

-- Nodo 2:
-- CHECK (id BETWEEN 3001 AND 6000)

-- Nodo 3:
-- CHECK (id BETWEEN 6001 AND 10000)

-- -----------------------------------------------------------------------------
-- Tabla: users
-- IDs controlados por la aplicación (NO SERIAL)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id         INT PRIMARY KEY CHECK (id BETWEEN 1 AND 3000), -- 🔥 CAMBIAR POR NODO
    username   VARCHAR(50)  NOT NULL UNIQUE,
    email      VARCHAR(100) NOT NULL UNIQUE,
    bio        TEXT,
    created_at TIMESTAMP    DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- Tabla: posts
-- Data locality: user y posts viven en el mismo nodo
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS posts (
    id         INT PRIMARY KEY,
    user_id    INT NOT NULL,
    content    TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    
    CONSTRAINT fk_posts_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
);

-- Índice clave
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id);

-- -----------------------------------------------------------------------------
-- Tabla: follows
-- Solo FK en follower (local), seguido puede estar en otro nodo
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS follows (
    follower_id INT NOT NULL,
    followed_id INT NOT NULL,
    created_at  TIMESTAMP DEFAULT NOW(),

    PRIMARY KEY (follower_id, followed_id),

    CONSTRAINT fk_follows_follower
        FOREIGN KEY (follower_id)
        REFERENCES users(id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_follows_followed_id ON follows(followed_id);

-- -----------------------------------------------------------------------------
-- Tabla: likes
-- Solo FK en user (local)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS likes (
    user_id    INT NOT NULL,
    post_id    INT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),

    PRIMARY KEY (user_id, post_id),

    CONSTRAINT fk_likes_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_likes_post_id ON likes(post_id);

-- -----------------------------------------------------------------------------
-- Tabla: shard_metadata (opcional replicada)
-- Idealmente manejada por la app, pero se deja para simplicidad
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS shard_metadata (
    shard_id    INT PRIMARY KEY,
    host        VARCHAR(50) NOT NULL,
    port        INT NOT NULL DEFAULT 5432,
    user_id_min INT NOT NULL,
    user_id_max INT NOT NULL,
    is_active   BOOLEAN DEFAULT TRUE,
    updated_at  TIMESTAMP DEFAULT NOW()
);

-- Poblar metadata (idempotente)
INSERT INTO shard_metadata (shard_id, host, port, user_id_min, user_id_max)
VALUES
  (1, '10.0.0.1', 5432, 1,    3000),
  (2, '10.0.0.2', 5432, 3001, 6000),
  (3, '10.0.0.3', 5432, 6001, 10000)
ON CONFLICT (shard_id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Verificación (más confiable)
-- -----------------------------------------------------------------------------
SELECT 'Nodo activo en IP: ' || inet_server_addr() AS status;

SELECT tablename 
FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY tablename;