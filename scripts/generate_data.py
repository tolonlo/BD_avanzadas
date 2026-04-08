#!/usr/bin/env python3
"""
SI3009 | Proyecto 2 | Generador de datos sintéticos
Genera archivos SQL para cargar en los 3 nodos de PostgreSQL y en CockroachDB/YugabyteDB.

Uso:
  pip install faker
  python generate_data.py --users 10000 --posts 50000 --follows 30000 --likes 100000 --out ./data
"""

import argparse
import os
import random
from datetime import datetime, timedelta

from faker import Faker

# ─── Configuración de shards ────────────────────────────────────────────────
SHARDS = {
    1: (1, 3000),
    2: (3001, 6000),
    3: (6001, 10000),
}

fake = Faker("es_CO")  # Locale colombiano para datos más realistas
Faker.seed(42)
random.seed(42)


# ─── Utilidades ──────────────────────────────────────────────────────────────

def get_shard(user_id: int) -> int:
    for shard_id, (lo, hi) in SHARDS.items():
        if lo <= user_id <= hi:
            return shard_id
    raise ValueError(f"user_id {user_id} fuera del rango definido (1–10000)")


def random_ts(days_back: int = 365) -> str:
    dt = datetime.now() - timedelta(
        days=random.randint(0, days_back),
        hours=random.randint(0, 23),
        minutes=random.randint(0, 59),
        seconds=random.randint(0, 59),
    )
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def escape(s: str) -> str:
    return s.replace("'", "''")


# ─── Generadores ─────────────────────────────────────────────────────────────

def generate_users(n: int) -> dict[int, list[str]]:
    """
    Genera INSERT statements para la tabla users.
    Devuelve dict: shard_id → lista de líneas SQL.
    """
    lines: dict[int, list[str]] = {1: [], 2: [], 3: []}
    used_usernames: set[str] = set()
    used_emails: set[str] = set()

    for user_id in range(1, n + 1):
        # Generar username único
        base = fake.user_name()[:40]
        username = base
        suffix = 1
        while username in used_usernames:
            username = f"{base}_{suffix}"
            suffix += 1
        used_usernames.add(username)

        # Generar email único
        email = fake.email()
        while email in used_emails:
            email = fake.email()
        used_emails.add(email)

        bio = escape(fake.sentence(nb_words=8))
        ts = random_ts(730)

        line = (
            f"INSERT INTO users (id, username, email, bio, created_at) "
            f"VALUES ({user_id}, '{escape(username)}', '{email}', '{bio}', '{ts}') "
            f"ON CONFLICT DO NOTHING;"
        )
        lines[get_shard(user_id)].append(line)

        if user_id % 1000 == 0:
            print(f"  users: {user_id}/{n}")

    return lines


def generate_posts(n: int, max_user_id: int) -> dict[int, list[str]]:
    """
    Genera INSERT statements para la tabla posts.
    Cada post se asigna al mismo nodo que su user_id (data locality).
    """
    lines: dict[int, list[str]] = {1: [], 2: [], 3: []}

    sample_contents = [
        "Explorando arquitecturas distribuidas con PostgreSQL y CockroachDB",
        "El teorema CAP: entre la consistencia y la disponibilidad",
        "EXPLAIN ANALYZE me salvó de un índice faltante en producción",
        "Sharding manual vs auto-sharding: la experiencia no miente",
        "Two-Phase Commit: elegante en teoría, complicado en producción",
        "Replicación sincrónica: +10ms de latencia = 0 pérdida de datos",
        "Split-brain: el enemigo silencioso de los sistemas distribuidos",
        "Raft consensus: cómo CockroachDB logra failover en segundos",
        "PACELC: el modelo que va más allá del teorema CAP",
        "Data locality en sharding: mantener los datos cerca del usuario",
        "pgbench results: 3 nodos vs 1 nodo vs CockroachDB cluster",
        "Hot spots en hash sharding: el problema que nadie anticipa",
        "Patroni + etcd: high availability para PostgreSQL sin dolor",
        "SAGA vs 2PC: cuándo sacrificar atomicidad por disponibilidad",
        "synchronous_commit=remote_apply: la opción más conservadora",
        "PostgreSQL logical replication para CDC en microservicios",
        "YugabyteDB o CockroachDB: diferencias que importan en producción",
        "CQRS con eventos: separar lecturas de escrituras a escala",
        "Costos reales de una base distribuida vs servicio administrado",
        "Migración de MySQL sharded a CockroachDB: lecciones aprendidas",
    ]

    for post_id in range(1, n + 1):
        user_id = random.randint(1, max_user_id)
        content = escape(random.choice(sample_contents) + f" #{post_id}")
        ts = random_ts(365)

        line = (
            f"INSERT INTO posts (id, user_id, content, created_at) "
            f"VALUES ({post_id}, {user_id}, '{content}', '{ts}') "
            f"ON CONFLICT DO NOTHING;"
        )
        lines[get_shard(user_id)].append(line)

        if post_id % 10000 == 0:
            print(f"  posts: {post_id}/{n}")

    return lines


def generate_follows(n: int, max_user_id: int) -> list[str]:
    """
    Genera INSERT statements para follows.
    Incluye relaciones cross-shard intencionalmente.
    Los follows van al archivo del nodo del follower_id,
    pero aquí los ponemos todos en un archivo (follows_all.sql).
    """
    lines: list[str] = []
    pairs: set[tuple[int, int]] = set()

    attempts = 0
    while len(pairs) < n and attempts < n * 10:
        follower_id = random.randint(1, max_user_id)
        followed_id = random.randint(1, max_user_id)
        attempts += 1
        if follower_id == followed_id:
            continue
        if (follower_id, followed_id) in pairs:
            continue
        pairs.add((follower_id, followed_id))

        ts = random_ts(365)
        line = (
            f"INSERT INTO follows (follower_id, followed_id, created_at) "
            f"VALUES ({follower_id}, {followed_id}, '{ts}') "
            f"ON CONFLICT DO NOTHING;"
        )
        lines.append(line)

        if len(pairs) % 10000 == 0:
            print(f"  follows: {len(pairs)}/{n}")

    return lines


def generate_likes(n: int, max_user_id: int, max_post_id: int) -> list[str]:
    """
    Genera INSERT statements para likes.
    Incluye likes a posts de otros nodos (cross-shard).
    """
    lines: list[str] = []
    pairs: set[tuple[int, int]] = set()

    attempts = 0
    while len(pairs) < n and attempts < n * 10:
        user_id = random.randint(1, max_user_id)
        post_id = random.randint(1, max_post_id)
        attempts += 1
        if (user_id, post_id) in pairs:
            continue
        pairs.add((user_id, post_id))

        ts = random_ts(365)
        line = (
            f"INSERT INTO likes (user_id, post_id, created_at) "
            f"VALUES ({user_id}, {post_id}, '{ts}') "
            f"ON CONFLICT DO NOTHING;"
        )
        lines.append(line)

        if len(pairs) % 25000 == 0:
            print(f"  likes: {len(pairs)}/{n}")

    return lines


# ─── Escritura de archivos ────────────────────────────────────────────────────

def write_sql_file(path: str, header: str, lines: list[str]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(header + "\n")
        f.write(f"-- Total de registros: {len(lines)}\n\n")
        # Agrupar en transacciones de 500 para mejorar rendimiento de carga
        batch = 500
        for i in range(0, len(lines), batch):
            f.write("BEGIN;\n")
            for line in lines[i:i + batch]:
                f.write(line + "\n")
            f.write("COMMIT;\n\n")
    print(f"  → {path} ({len(lines)} registros)")


# ─── Punto de entrada ─────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Generador de datos sintéticos para SI3009 P2")
    parser.add_argument("--users",   type=int, default=10000)
    parser.add_argument("--posts",   type=int, default=50000)
    parser.add_argument("--follows", type=int, default=30000)
    parser.add_argument("--likes",   type=int, default=100000)
    parser.add_argument("--out",     type=str, default="./data")
    args = parser.parse_args()

    print(f"\n{'='*60}")
    print(f"SI3009 Proyecto 2 — Generador de datos sintéticos")
    print(f"  users={args.users}, posts={args.posts}, "
          f"follows={args.follows}, likes={args.likes}")
    print(f"  output: {args.out}")
    print(f"{'='*60}\n")

    # Usuarios
    print("Generando usuarios...")
    user_lines = generate_users(args.users)
    for shard_id in [1, 2, 3]:
        lo, hi = SHARDS[shard_id]
        header = (
            f"-- Nodo {shard_id} | users | user_id {lo}–{hi}\n"
            f"-- Generado: {datetime.now().isoformat()}\n"
            f"-- Aplicar en: nodo{shard_id} (10.0.0.{shard_id}:5432)\n"
        )
        write_sql_file(
            f"{args.out}/users_nodo{shard_id}.sql",
            header,
            user_lines[shard_id]
        )

    # Posts
    print("\nGenerando posts...")
    post_lines = generate_posts(args.posts, args.users)
    for shard_id in [1, 2, 3]:
        lo, hi = SHARDS[shard_id]
        header = (
            f"-- Nodo {shard_id} | posts | posts de usuarios {lo}–{hi}\n"
            f"-- PREREQUISITO: users_nodo{shard_id}.sql ya fue cargado\n"
            f"-- Generado: {datetime.now().isoformat()}\n"
        )
        write_sql_file(
            f"{args.out}/posts_nodo{shard_id}.sql",
            header,
            post_lines[shard_id]
        )

    # Follows (cross-shard, un archivo por nodo según follower_id)
    print("\nGenerando follows...")
    all_follows = generate_follows(args.follows, args.users)

    # Separar por nodo del follower_id para carga distribuida
    follows_by_shard: dict[int, list[str]] = {1: [], 2: [], 3: []}
    for line in all_follows:
        # Extraer follower_id del INSERT statement
        try:
            follower_id = int(line.split("VALUES (")[1].split(",")[0])
            follows_by_shard[get_shard(follower_id)].append(line)
        except Exception:
            follows_by_shard[1].append(line)  # fallback

    for shard_id in [1, 2, 3]:
        header = (
            f"-- Nodo {shard_id} | follows | follower_id en rango del nodo {shard_id}\n"
            f"-- Incluye follows cross-shard (followed_id en otros nodos)\n"
            f"-- Generado: {datetime.now().isoformat()}\n"
        )
        write_sql_file(
            f"{args.out}/follows_nodo{shard_id}.sql",
            header,
            follows_by_shard[shard_id]
        )

    # También generar follows_all.sql para CockroachDB (un solo endpoint)
    header = (
        f"-- ALL NODES | follows | todos los follows del cluster\n"
        f"-- Usar para CockroachDB/YugabyteDB (un solo endpoint)\n"
        f"-- Generado: {datetime.now().isoformat()}\n"
    )
    write_sql_file(f"{args.out}/follows_all.sql", header, all_follows)

    # Likes
    print("\nGenerando likes...")
    all_likes = generate_likes(args.likes, args.users, args.posts)

    likes_by_shard: dict[int, list[str]] = {1: [], 2: [], 3: []}
    for line in all_likes:
        try:
            user_id = int(line.split("VALUES (")[1].split(",")[0])
            likes_by_shard[get_shard(user_id)].append(line)
        except Exception:
            likes_by_shard[1].append(line)

    for shard_id in [1, 2, 3]:
        header = (
            f"-- Nodo {shard_id} | likes | user_id en rango del nodo {shard_id}\n"
            f"-- Generado: {datetime.now().isoformat()}\n"
        )
        write_sql_file(
            f"{args.out}/likes_nodo{shard_id}.sql",
            header,
            likes_by_shard[shard_id]
        )

    header = (
        f"-- ALL NODES | likes | para CockroachDB/YugabyteDB\n"
        f"-- Generado: {datetime.now().isoformat()}\n"
    )
    write_sql_file(f"{args.out}/likes_all.sql", header, all_likes)

    print(f"\n{'='*60}")
    print("✓ Generación completada")
    print(f"\nArchivos generados en {args.out}/:")
    for f in sorted(os.listdir(args.out)):
        path = os.path.join(args.out, f)
        size = os.path.getsize(path) / 1024
        print(f"  {f:<30} {size:>8.1f} KB")
    print(f"\nCarga en PostgreSQL:")
    for shard_id in [1, 2, 3]:
        ip = f"10.0.0.{shard_id}"
        print(f"  # Nodo {shard_id} ({ip})")
        print(f"  psql -h {ip} -U postgres -d socialdb -f {args.out}/users_nodo{shard_id}.sql")
        print(f"  psql -h {ip} -U postgres -d socialdb -f {args.out}/posts_nodo{shard_id}.sql")
        print(f"  psql -h {ip} -U postgres -d socialdb -f {args.out}/follows_nodo{shard_id}.sql")
        print(f"  psql -h {ip} -U postgres -d socialdb -f {args.out}/likes_nodo{shard_id}.sql")
    print(f"\nCarga en CockroachDB/YugabyteDB:")
    print(f"  for f in users_nodo1 users_nodo2 users_nodo3 posts_nodo1 posts_nodo2 posts_nodo3; do")
    print(f"    psql -h localhost -p 26257 -U root -d socialdb -f {args.out}/$f.sql")
    print(f"  done")
    print(f"  psql -h localhost -p 26257 -U root -d socialdb -f {args.out}/follows_all.sql")
    print(f"  psql -h localhost -p 26257 -U root -d socialdb -f {args.out}/likes_all.sql")


if __name__ == "__main__":
    main()
