-- =============================================================================
-- SI3009 | Proyecto 2 | Script 01 (NewSQL): Creacion de tablas base
-- Para CockroachDB / YugabyteDB en cluster unico (sin check por shard manual)
-- =============================================================================

CREATE TABLE IF NOT EXISTS users (
    id         INT PRIMARY KEY,
    username   VARCHAR(50)  NOT NULL UNIQUE,
    email      VARCHAR(100) NOT NULL UNIQUE,
    bio        TEXT,
    created_at TIMESTAMP    DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS posts (
    id         INT PRIMARY KEY,
    user_id    INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content    TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS follows (
    follower_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    followed_id INT NOT NULL,
    created_at  TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (follower_id, followed_id)
);

CREATE TABLE IF NOT EXISTS likes (
    user_id    INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id    INT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (user_id, post_id)
);
