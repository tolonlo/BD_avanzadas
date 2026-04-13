# Análisis Crítico — SI3009 Proyecto 2
## Arquitecturas Distribuidas: lo que la teoría no cuenta

---

## 1. La brecha entre teoría y práctica operativa

Los conceptos de sharding, replicación y 2PC se explican en clase con diagramas limpios y flujos de tres pasos. La realidad de implementarlos es otra cosa.

Durante este proyecto, antes de escribir una sola línea de SQL distribuido, hubo que resolver: un sistema operativo que bloquea la instalación de paquetes Python (Kali Linux con PEP 668), security groups de AWS que silenciosamente descartaban tráfico entre nodos en la misma VPC, un usuario de sistema (`postgres`) que no puede acceder al directorio home del usuario ubuntu, y slots de replicación que deben crearse manualmente antes del `pg_basebackup` o el proceso falla sin un mensaje de error claro.

Ninguno de estos problemas aparece en la documentación oficial de PostgreSQL. Todos requirieron debugging real. En conjunto, representaron más tiempo que la configuración técnica en sí. Esto no es una queja — es el punto central del análisis: **la complejidad operativa de los sistemas distribuidos vive en los detalles que los papers y tutoriales omiten.**

CockroachDB, en contraste, se inicializó con cuatro comandos. El mismo cluster de tres nodos que tomó horas en PostgreSQL tomó minutos en CockroachDB. Esa diferencia no está en el rendimiento — está en dónde vive la complejidad: en el motor o en el equipo de operaciones.

---

## 2. Lo que los números no dicen

Los benchmarks de este proyecto muestran que PostgreSQL es ~100x más rápido que CockroachDB en consultas OLTP locales (0.069 ms vs 7 ms). Ese número es real y correcto en el contexto del experimento. Pero omite variables críticas:

**Datos locales vs datos distribuidos.** PostgreSQL fue ~100x más rápido porque la consulta accedió datos que estaban en el mismo nodo, en caché, sin ningún salto de red. Si el usuario 1500 hubiera estado en otro shard, el tiempo habría incluido una conexión TCP adicional, serialización, y deserialización — fácilmente 10–50ms extra. CockroachDB manejó eso automáticamente con `distribution: full`.

**Consistencia implícita.** CockroachDB corrió cada consulta con `isolation level: serializable` sin configuración adicional. Para obtener el mismo nivel de aislamiento en PostgreSQL distribuido se requiere 2PC manual, que en este proyecto tomó múltiples pasos en dos terminales simultáneas. El "costo" de consistencia en CockroachDB ya está incluido en los 7ms — en PostgreSQL está escondido en la complejidad del código de la aplicación.

**Escalabilidad futura.** Agregar un cuarto nodo a PostgreSQL requiere decidir qué rango de `user_id` le corresponde, modificar la función de routing, migrar los datos existentes, actualizar `pg_hba.conf` y `shard_metadata`, y redistribuir las réplicas. En CockroachDB es un `docker run` adicional y el motor redistribuye los rangos automáticamente.

---

## 3. El failover como experimento de verdad

El failover fue el experimento más revelador del proyecto. El proceso de promover pg-s2 a Primary tomó aproximadamente 20 minutos e involucró:

1. Detectar la caída manualmente (no hay alertas automáticas configuradas)
2. Ejecutar `pg_ctl promote` en el nodo correcto
3. Crear los slots de replicación que no se transfirieron
4. Redirigir pg-s3 que seguía apuntando al Primary caído editando `postgresql.auto.conf`
5. Hacer `pg_basebackup` para reintegrar pg-s1 como réplica
6. Actualizar `shard_metadata` para que el router apunte al nuevo Primary

En ningún momento hubo riesgo de split-brain porque pg-s1 estaba completamente apagado antes de iniciar la promoción. En un escenario real — donde el Primary está en un estado indefinido, respondiendo a algunas conexiones pero no a otras — la decisión de cuándo promover y cómo evitar que el Primary original vuelva a aceptar escrituras simultáneamente es exactamente el problema que Patroni + etcd resuelven con quórum distribuido.

CockroachDB resolvió el mismo escenario con `docker stop roach1`. El cluster detectó la caída, eligió un nuevo leaseholder, y siguió operando. `docker start roach1` reincorporó el nodo automáticamente en ~5 segundos. No hubo intervención, no hubo riesgo de split-brain, no hubo comandos adicionales.

**La pregunta correcta no es cuál motor es más rápido. Es: ¿cuánto cuesta una hora de downtime en tu sistema, y cuánto cuesta el equipo que previene ese downtime?**

---

## 4. Casos reales que validan la experiencia

### Rappi (Colombia)
Entre 2017 y 2020, Rappi pasó de una base de datos centralizada a una arquitectura distribuida a medida que su base de usuarios creció exponencialmente. El problema más difícil no fue técnico — fue operativo: ¿cómo se garantiza que un pedido no se marca como disponible en Bogotá mientras ya fue tomado por un repartidor en Medellín? Exactamente el problema de consistencia eventual que este proyecto experimentó con el sharding manual de `follows` y `likes` entre nodos.

La solución de Rappi requirió equipos dedicados a infraestructura de datos que desarrollaron lógica de compensación y reconciliación — el equivalente empresarial del 2PC manual que este proyecto implementó con `PREPARE TRANSACTION`.

### Twitter / X
Twitter operó durante años con sharding manual de MySQL, el modelo exacto que este proyecto implementa con PostgreSQL. El equipo de ingeniería documentó públicamente cómo el crecimiento obligó a desarrollar herramientas propias de redistribución de shards — una inversión de meses de ingeniería que sistemas como CockroachDB proveen nativamente. La lección que Twitter aprendió: el costo del sharding manual no está en el hardware sino en el talento de ingeniería dedicado a mantenerlo.

### Stack Overflow
Significativamente, Stack Overflow sigue operando con SQL Server centralizado sirviendo millones de requests diarios. Su argumento: la complejidad operativa de una base distribuida no se justifica cuando la optimización cuidadosa de índices y queries en un sistema centralizado puede escalar mucho más de lo que la mayoría asume. Este proyecto lo confirma: PostgreSQL en un solo nodo con los índices del Script 02 respondió en 0.069 ms — más rápido que cualquier sistema distribuido puede aspirar a ser.

---

## 5. PACELC aplicado a lo experimentado

El modelo PACELC es más útil que CAP para describir lo que este proyecto midió:

**PostgreSQL con `synchronous_commit=off`:**
- En partición (P): elige disponibilidad (A) — el Primary acepta escrituras aunque las réplicas no confirmen.
- En operación normal (E): elige latencia (L) — 0.054ms promedio, pero con riesgo de pérdida de datos.

**PostgreSQL con `synchronous_commit=on`:**
- En partición (P): elige consistencia (C) — el Primary puede bloquearse esperando réplicas.
- En operación normal (E): elige consistencia (C) — 0.035ms promedio con garantía de durabilidad.

**CockroachDB:**
- En partición (P): siempre elige consistencia (C) — rechaza escrituras si no hay quórum.
- En operación normal (E): elige consistencia (C) con overhead de ~7ms por consenso Raft.

La paradoja que este benchmark reveló: en red local (misma VPC AWS), `synchronous_commit=on` fue más rápido que `off` (0.035ms vs 0.054ms). Esto ocurre porque el overhead de sincronización es menor que la varianza del sistema async. La diferencia entre modos se vuelve significativa solo con latencia de red alta — exactamente cuando la consistencia más importa.

---

## 6. Administración: centralizada vs distribuida vs managed

La experiencia de este proyecto permite comparar los tres modelos con datos concretos, no solo teoría:

**Base de datos centralizada** (un solo nodo PostgreSQL):
- Setup: minutos.
- Operación: un DBA puede manejarlo solo.
- Límite: escala vertical. Cuando el servidor llega al tope, no hay salida fácil.
- Adecuado para: la mayoría de proyectos universitarios, startups tempranas, sistemas internos.

**Base de datos distribuida manual** (este proyecto):
- Setup: horas a días, con problemas inesperados en cada paso.
- Operación: requiere conocimiento profundo de PostgreSQL, AWS, networking, y herramientas como Patroni.
- Límite: la complejidad escala con cada nodo agregado.
- Adecuado para: equipos con DBA dedicado, requisitos regulatorios de soberanía de datos, o cuando el control total es no negociable.

**Servicio administrado** (RDS, Cloud SQL, CockroachDB Cloud):
- Setup: minutos, similar al centralizado.
- Operación: el proveedor gestiona failover, backups, parches, y escalamiento.
- Límite: vendor lock-in, costo a escala, menos control sobre configuración.
- Adecuado para: equipos que quieren escalar sin invertir en infraestructura.

**NewSQL self-hosted** (CockroachDB Docker, este proyecto):
- Setup: ~10 minutos vs ~3 horas de PostgreSQL distribuido.
- Operación: significativamente más simple que PostgreSQL manual, más complejo que managed.
- Límite: mínimo 3 nodos para quórum, recursos mínimos más altos.
- Adecuado para: equipos que necesitan distribución nativa sin depender de un proveedor cloud.

---

## 7. Reflexión final

Este proyecto confirmó algo que los papers de bases de datos distribuidas raramente dicen explícitamente: **la distribución es un costo, no una característica**. Se distribuye cuando el beneficio (escala, disponibilidad, localidad geográfica) supera el costo (complejidad, latencia adicional, riesgo operativo).

PostgreSQL en un solo nodo respondió en 0.069ms. CockroachDB distribuido respondió en 7ms. La diferencia no es un defecto de CockroachDB — es el precio exacto de la distribución automática, el failover en 5 segundos, y la consistencia serializable global. Ese precio puede valer completamente dependiendo del contexto.

Lo que este proyecto enseñó que ningún benchmark enseña: la diferencia entre un sistema que funciona en un tutorial y uno que funciona en producción son exactamente los problemas que no están en el tutorial.

---

*Documento complementario al README.md — SI3009 Bases de Datos Avanzadas · 2026-1*
