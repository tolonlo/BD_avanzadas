-- =============================================================================
-- SI3009 | Proyecto 2 | Script 04: Enrutamiento y funciones (CORREGIDO)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Función: get_shard_for_user
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_shard_for_user(p_user_id INT)
RETURNS INT AS $$
BEGIN
    IF p_user_id BETWEEN 1 AND 3000 THEN
        RETURN 1;
    ELSIF p_user_id BETWEEN 3001 AND 6000 THEN
        RETURN 2;
    ELSIF p_user_id BETWEEN 6001 AND 10000 THEN
        RETURN 3;
    ELSE
        RAISE EXCEPTION 'user_id % fuera del rango definido (1–10000)', p_user_id;
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- -----------------------------------------------------------------------------
-- Función: get_connection_string
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_connection_string(p_user_id INT)
RETURNS TEXT AS $$
DECLARE
    v_shard INT;
    v_host  TEXT;
    v_port  INT;
BEGIN
    v_shard := get_shard_for_user(p_user_id);

    SELECT host, port INTO v_host, v_port
    FROM shard_metadata
    WHERE shard_id = v_shard
      AND is_active = TRUE;

    IF v_host IS NULL THEN
        RAISE EXCEPTION 'Shard % no encontrado o inactivo', v_shard;
    END IF;

    RETURN format('host=%s port=%s dbname=socialdb', v_host, v_port);
END;
$$ LANGUAGE plpgsql STABLE;

-- -----------------------------------------------------------------------------
-- Función: is_local_user
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_local_user(p_user_id INT)
RETURNS BOOLEAN AS $$
DECLARE
    v_local_shard INT;
BEGIN
    BEGIN
        v_local_shard := current_setting('app.shard_id', true)::INT;
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'app.shard_id no configurado. Asumiendo shard 1.';
        v_local_shard := 1;
    END;

    RETURN get_shard_for_user(p_user_id) = v_local_shard;
END;
$$ LANGUAGE plpgsql STABLE;

-- -----------------------------------------------------------------------------
-- Vista: v_posts_with_likes
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_posts_with_likes AS
SELECT
    p.id            AS post_id,
    p.user_id,
    u.username,
    p.content,
    p.created_at,
    COUNT(l.user_id) AS total_likes
FROM posts p
JOIN users u ON p.user_id = u.id
LEFT JOIN likes l ON p.id = l.post_id
GROUP BY p.id, p.user_id, u.username, p.content, p.created_at;

-- -----------------------------------------------------------------------------
-- Vista: v_user_stats (CORREGIDA)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_user_stats AS
SELECT
    u.id AS user_id,
    u.username,
    u.created_at AS member_since,

    COUNT(DISTINCT p.id) AS total_posts,
    COUNT(DISTINCT f_out.followed_id) AS following_count,
    COUNT(DISTINCT f_in.follower_id) AS followers_count

FROM users u
LEFT JOIN posts p ON u.id = p.user_id
LEFT JOIN follows f_out ON u.id = f_out.follower_id
LEFT JOIN follows f_in ON u.id = f_in.followed_id

GROUP BY u.id, u.username, u.created_at;

-- -----------------------------------------------------------------------------
-- Función: simulate_routing_decision
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION simulate_routing_decision(p_user_ids INT[])
RETURNS TABLE(user_id INT, shard_id INT, connection_string TEXT) AS $$
DECLARE
    v_uid INT;
BEGIN
    FOREACH v_uid IN ARRAY p_user_ids LOOP
        user_id := v_uid;
        shard_id := get_shard_for_user(v_uid);
        connection_string := get_connection_string(v_uid);
        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql STABLE;

-- -----------------------------------------------------------------------------
-- Demo
-- -----------------------------------------------------------------------------
SELECT * FROM simulate_routing_decision(ARRAY[100, 3500, 7200, 1, 6000, 10000]);