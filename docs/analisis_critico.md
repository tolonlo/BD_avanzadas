# Análisis Crítico — SI3009 Proyecto 2
## Arquitecturas Distribuidas: Reflexiones desde la Implementación

> **Grupo:** [nombre del grupo]  
> **Curso:** Bases de Datos Avanzadas · 2026-1

---

## 1. La brecha entre teoría y operación real

Implementar este proyecto reveló una diferencia fundamental que los libros de texto no transmiten bien: la distancia entre *entender* un concepto y *operarlo* bajo presión.

El teorema CAP se explica en un párrafo. Configurar `synchronous_standby_names` correctamente en tres nodos con latencia de red simulada, verificar que ninguno cree erróneamente ser el Primary, y luego medir que el failover efectivamente ocurre en segundos y no en minutos, es un ejercicio completamente distinto. En ese proceso aparecen preguntas que ningún diagrama responde: ¿qué sucede si la réplica se atrasa durante el proceso de promote? ¿El router de la aplicación detecta el cambio de Primary o sigue enviando escrituras al nodo caído?

Estas preguntas tienen respuesta, pero la respuesta requiere operar el sistema, no solo leerlo. Eso es exactamente lo que este proyecto aporta.

---

## 2. El costo oculto de la distribución manual

### 2.1 Lo que los benchmarks no muestran

Las tablas de latencia en el README muestran números limpios. Lo que no muestran es el tiempo que tomó llegar a esos números:

- Detectar que `max_prepared_transactions = 0` (el default) impedía ejecutar 2PC, y que cambiar ese parámetro requería reiniciar el nodo.
- Entender que las foreign keys entre tablas de nodos distintos no son posibles, y que la integridad referencial cross-shard es responsabilidad de la aplicación.
- Descubrir que un `PREPARE TRANSACTION` no confirmado bloquea filas indefinidamente y que la consulta para detectarlo (`pg_prepared_xacts`) no es intuitiva.

Cada uno de estos obstáculos, trivial en retrospectiva, representa tiempo de ingeniería en producción. Y en producción, ese tiempo tiene un costo directo.

### 2.2 El caso Rappi (Colombia)

Rappi es un ejemplo particularmente relevante porque ilustra los mismos trade-offs de este proyecto a escala real y en contexto latinoamericano. Entre 2017 y 2020, durante su expansión acelerada a múltiples países, Rappi enfrentó exactamente el problema que describe la Sección 9 del README: la base de datos centralizada que funcionaba bien en Colombia comenzó a mostrar limitaciones cuando el volumen de pedidos simultáneos creció exponencialmente.

La solución no fue inmediata ni elegante. Rappi adoptó una arquitectura de microservicios progresivamente, separando primero el servicio de pedidos del catálogo, luego el de pagos del de notificaciones. Cada separación implicaba decidir dónde vivía la fuente de verdad de cada entidad y cómo se mantenía la consistencia entre servicios. El patrón SAGA, mencionado como bonus en este proyecto, no es un concepto académico para Rappi: es la forma en que un pedido puede fallar en el pago pero no dejar el inventario del restaurante en un estado inconsistente.

Lo que no se documenta públicamente, pero es razonable inferir, es cuántos incidentes de producción ocurrieron en el camino. Esos incidentes son el precio real de la distribución.

### 2.3 El caso Twitter/X

Twitter operó durante años con particionamiento manual de MySQL, el equivalente a lo que este proyecto implementa con PostgreSQL. El equipo de infraestructura documentó públicamente cómo el crecimiento de la plataforma los obligó a construir herramientas propias: **Gizzard** para el enrutamiento de shards, **Finagle** para la comunicación entre servicios, **Manhattan** como base de datos distribuida propia.

La inversión fue de meses de ingeniería de élite. Los sistemas NewSQL como CockroachDB o YugabyteDB proveen esa funcionalidad de forma nativa. La pregunta no es si usar NewSQL es "mejor" en abstracto, sino si la inversión en construir la infraestructura de enrutamiento se justifica cuando existe una alternativa madura.

Para Twitter en 2010, la respuesta era sí: las soluciones NewSQL no existían. Para un equipo de ingeniería en 2026, la respuesta casi siempre es no.

---

## 3. Análisis de costos: lo que brilla no siempre es oro

### 3.1 La paradoja del costo aparente

PostgreSQL es gratuito. CockroachDB tiene un tier gratuito. Pero el costo de operar un sistema distribuido no está en las licencias, sino en el tiempo humano requerido para mantenerlo.

| Componente | PostgreSQL distribuido manual | CockroachDB Dedicated | RDS Multi-AZ |
|---|---|---|---|
| Licencia | $0 | ~$200–400/nodo/mes | ~$150–300/instancia/mes |
| Tiempo DBA (setup) | 40–80 horas | 4–8 horas | 1–2 horas |
| Tiempo DBA (mantenimiento mensual) | 20–40 horas | 2–5 horas | 0–2 horas |
| Costo DBA senior en Colombia (mercado 2024–2025) | ~$10–15M COP/mes | — | — |
| Costo efectivo mensual (infraestructura + DBA) | $500 + labor | $800 + mínima labor | $400 + mínima labor |

El punto de equilibrio se desplaza dependiendo del tamaño del equipo. Para una startup con 2–3 ingenieros de backend que también hacen DBA, el costo oculto de PostgreSQL distribuido manual puede superar fácilmente el de un servicio administrado en los primeros 12 meses de operación.

### 3.2 El costo del incidente

Una consideración que los análisis de costo frecuentemente omiten es el costo de los incidentes. Un bloqueo de 2PC en producción que dura 2 horas tiene un costo difícil de cuantificar: pérdida de transacciones, tiempo de ingenieros en guardia, impacto en la confianza del usuario.

CockroachDB y YugabyteDB no eliminan los incidentes, pero reducen la categoría de incidentes relacionados con consenso y failover. El tradeoff es aceptar mayor latencia base (~4–12 ms vs ~2 ms en PostgreSQL asincrónico) a cambio de no tener que manejar split-brain o transacciones preparadas huérfanas.

---

## 4. Transparencia real en la industria

### 4.1 Lo que el desarrollador promedio no sabe

En plataformas como Instagram (Meta) o TikTok, el desarrollador promedio escribe SQL estándar o usa un ORM sin saber:

- En qué nodo físico ejecuta su query
- Si la lectura que acaba de hacer es de un leaseholder o de una réplica con posible staleness
- Qué protocolo de consenso garantizó que su escritura fue durable

Esta abstracción es poderosa y productiva. Permite que cientos de ingenieros escriban código de producto sin necesitar expertise en sistemas distribuidos.

Pero tiene un lado oscuro: un desarrollador que no comprende estos fundamentos puede introducir un `SELECT *` sin `LIMIT` sobre una tabla particionada, una transacción que mantiene un lock abierto durante una llamada HTTP, o un join que cruza shards en cada request del feed. En un sistema de baja escala, esos errores son invisibles. En producción con millones de usuarios, se convierten en incidentes.

### 4.2 El valor pedagógico de la dificultad

La implementación manual que propone este proyecto tiene un valor que ningún tutorial de CockroachDB puede replicar: obliga a *sentir* la complejidad.

Cuando se escribe el código de enrutamiento `get_shard_for_user()` manualmente, se entiende visceralmente por qué el auto-sharding de un sistema NewSQL es una abstracción valiosa. Cuando se ejecuta `PREPARE TRANSACTION` y `COMMIT PREPARED` en dos terminales distintas coordinados a mano, se comprende por qué el 2PC nativo de CockroachDB justifica su overhead de latencia. Cuando se simula la caída del Primary y se ejecuta `pg_ctl promote` manualmente, se aprecia el valor del failover automático de Raft.

Sin haber operado el sistema difícil, es imposible valorar correctamente el sistema fácil.

---

## 5. Conclusión: el mapa y el territorio

Los modelos CAP y PACELC son mapas. Como todo mapa, simplifican la realidad para hacerla navegable. En el territorio real, las decisiones no son binarias entre CP y AP: son graduales, dependientes del contexto, y cambian con el tiempo a medida que el sistema crece.

La pregunta correcta no es "¿PostgreSQL o CockroachDB?" sino "¿cuánta complejidad operativa puede absorber nuestro equipo, y cuánta de esa complejidad es necesaria para el problema que estamos resolviendo?".

Para una red social en sus primeros 6 meses con 10.000 usuarios, la respuesta es probablemente: RDS Multi-AZ, SQL estándar, y no pensar en sharding todavía. Para esa misma red social con 10 millones de usuarios y operación en 5 países, la respuesta cambia. Lo importante es saber reconocer cuándo cambia, y tener el conocimiento para tomar esa decisión con criterio.

Ese es, en última instancia, el objetivo de este proyecto.

---

*Análisis elaborado para SI3009 Bases de Datos Avanzadas · Universidad · 2026-1*
