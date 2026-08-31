# Autoevaluación de madurez de observabilidad

Módulo E del proyecto integrador · 30 de agosto de 2026

## De dónde salen los ocho dominios

El enunciado pide autoevaluar contra el *Observability Foundation Blueprint*
(8 dominios) pero no los enumera. Sí nombra seis en su objetivo general: **Tres
Pilares, OpenTelemetry, AIOps, Network Observability, DataOps y SRE**. Los dos
restantes se derivan de los módulos que el propio enunciado califica y que
ninguno de esos seis cubre: el módulo C exige un dominio de **Seguridad** y el
módulo D uno de **Resiliencia**.

Se deja dicho para que quien lea esto sepa qué es cita y qué es derivación.

## La escala

Una escala de 1 a 5 solo sirve si cada nivel se puede distinguir del de al lado
sin discutir. Estos son los cortes que se aplican:

| Nivel | Nombre | Criterio |
|---|---|---|
| 1 | Ausente | No existe, o existe por accidente |
| 2 | Inicial | Existe pero es manual, puntual y no reproducible |
| 3 | Definido | Está documentado y versionado; se reproduce a voluntad |
| 4 | Gestionado | Se mide, tiene objetivos y su incumplimiento dispara acción |
| 5 | Optimizado | Se retroalimenta solo: los datos cambian el sistema sin intervención |

El salto que más cuesta es **de 3 a 4**, y es donde está casi todo este
laboratorio. Tener algo versionado y reproducible (3) es trabajo de ingeniería;
que además tenga un objetivo numérico cuyo incumplimiento obligue a actuar (4)
es trabajo de organización. La diferencia no es técnica.

---

## Puntuación

| # | Dominio | Nivel | Techo alcanzable hoy |
|---|---|---|---|
| 1 | Tres Pilares | **4** | 5 |
| 2 | OpenTelemetry | **4** | 5 |
| 3 | AIOps | **3** | 4 |
| 4 | Network Observability | **3** | 4 |
| 5 | DataOps | **3** | 4 |
| 6 | SRE | **3** | 4 |
| 7 | Seguridad | **2** | 3 |
| 8 | Resiliencia | **4** | 4 |

**Media: 3,25 sobre 5.**

La media importa menos que la forma del perfil: hay dos dominios en 4 que
arrastran al resto y uno en 2 que es el cuello de botella real.

---

## Dominio por dominio

### 1 · Tres Pilares — nivel 4

Los tres se emiten desde los tres servicios y **se cruzan entre sí**, que es lo
que separa el 4 del 3. Un log lleva `trace_id` y `span_id`; una métrica lleva
exemplars que apuntan a la traza concreta; desde un panel se salta a la traza y
de la traza al log.

Lo que impide el 5: la correlación se navega a mano. Nadie ha automatizado el
"dado este síntoma, tráeme las tres señales de la ventana afectada".

### 2 · OpenTelemetry — nivel 4

Auto-instrumentación y instrumentación manual conviviendo, convenciones
semánticas de base de datos explícitas en `data-service`, y —lo más
significativo— el mismo pipeline corriendo en local y en GCP donde **solo
cambian los exporters**. Esa diferencia mínima entre `otel-collector-local.yaml`
y `otel-collector-gcp.yaml` es la prueba de que no hay dependencia de proveedor.

Lo que impide el 5: no hay muestreo adaptativo. Se exporta todo y se filtra
después, que funciona a escala de laboratorio y no a escala real.

### 3 · AIOps — nivel 3

Existe detección estadística real: línea base móvil de una hora, umbral de dos
sigmas, correlación de dos señales independientes y guarda de volumen para no
disparar con tráfico mínimo. Está versionada y se reproduce.

No llega a 4 porque **no se ha medido su tasa de falsos positivos contra la del
umbral estático**. La alerta de contraste está escrita y desplegada precisamente
para poder medirlo, pero mientras el número no exista, la afirmación "reduce
ruido" es una hipótesis, no un resultado. No se le pone 4 a una hipótesis.

### 4 · Network Observability — nivel 3

VPC Flow Logs al 50 % de muestreo con metadatos completos, registro de firewall
en la regla de denegación, y malla de servicios sobre GKE.

No llega a 4 porque no hay objetivo numérico sobre ninguna señal de red. Se
observa el tráfico; no se ha declarado qué valor sería inaceptable.

### 5 · DataOps — nivel 3

El pipeline de telemetría es código versionado, con orden de procesadores
justificado, filtros de ruido en dos capas y límites de memoria.

No llega a 4 porque **no hay gobierno de costo por señal**. Se sabe cuánto
cuesta el laboratorio en total, no cuánto cuesta cada pilar. Es la pregunta que
aparece en cuanto esto crece: "¿qué parte de la factura son las trazas?".

### 6 · SRE — nivel 3

Cuatro SLI con sus SLO documentados, un panel que los muestra y alertas
enganchadas a ellos.

No llega a 4 porque el **presupuesto de error no se consume ni se agota**: está
definido conceptualmente pero nada ocurre cuando se gasta. Un SLO sin
consecuencia es una cifra en un documento.

### 7 · Seguridad — nivel 2, y es el cuello de botella

Es la puntuación más baja y la más honesta. Las cuatro señales de seguridad
están definidas y desplegadas, pero:

- **Security Command Center no se pudo activar**: exige organización y el
  proyecto cuelga de una cuenta personal. Está verificado y documentado, no
  supuesto.
- Los umbrales son **cifras inventadas**, no calibradas. "100 denegaciones por
  minuto" y "10 MB de egreso" salieron del criterio de quien escribió el
  Terraform, no de observar semanas de comportamiento normal. Una alerta con un
  umbral no calibrado avisará de más o de menos, y no se sabe de cuál.

Sube a 3 en cuanto los umbrales se calibren contra datos reales. No pasa de ahí
sin una herramienta que correlacione con inteligencia de amenazas.

### 8 · Resiliencia — nivel 4

El dominio más maduro, y no por casualidad: es el único donde el sistema se ha
roto a propósito y se ha medido qué pasaba. Game Day ejecutado con tres
hipótesis, experimentos con radio de explosión acotado y **reversión automática
por tiempo**, más los dos experimentos de este proyecto sobre GKE.

Y hay algo que vale más que los experimentos que salieron bien: uno salió mal.
El experimento del pool de conexiones **no inyectó nada** porque faltaba
declarar la variable, y el resultado de "cero errores" se interpretó primero
como que la remediación funcionaba. Detectar esa lectura falsa es lo que
distingue un ejercicio de caos de un teatro de caos.

---

## Roadmap a tres meses

El criterio de selección: **primero lo que convierte una hipótesis en un número**,
después lo que sube nivel. Se atacan los tres dominios más bajos.

### Mes 1 — cerrar lo que ya está a medias

| Acción | Dominio | De → a |
|---|---|---|
| Medir falsos positivos: alerta 2σ contra umbral estático, 30 días de datos | AIOps | 3 → 4 |
| Calibrar los umbrales de seguridad contra tráfico real observado | Seguridad | 2 → 3 |
| Implementar consumo de presupuesto de error, con congelación de despliegues al agotarse | SRE | 3 → 4 |

El primero es el de mayor retorno y el más barato: la instrumentación ya está
puesta, solo falta dejar correr el reloj y contar. Convierte la afirmación
central del módulo B en un dato.

### Mes 2 — cerrar los huecos estructurales

| Acción | Dominio | De → a |
|---|---|---|
| Atribución de costo por pilar, con etiquetas de facturación por tipo de señal | DataOps | 3 → 4 |
| Declarar SLO de red (latencia entre servicios, tasa de reintentos) | Network | 3 → 4 |
| Migrar el proyecto a una organización y activar SCC | Seguridad | 3 → 4 |

El tercero es de gestión, no de ingeniería: alguien tiene que crear la
organización. Es el único punto del roadmap que no depende del equipo técnico, y
por eso conviene arrancarlo el primer día aunque se ejecute el segundo mes.

### Mes 3 — automatizar

| Acción | Dominio | De → a |
|---|---|---|
| Muestreo adaptativo por cola en el Collector | OpenTelemetry | 4 → 5 |
| Correlación automática de las tres señales al abrirse una alerta | Tres Pilares | 4 → 5 |
| Game Days en calendario fijo, con experimentos en integración continua | Resiliencia | consolidar |

### Meta

Media de **3,25 → 4,1**. Ningún dominio por debajo de 4 salvo Seguridad, que
queda en 4 solo si la migración a organización se aprueba fuera del equipo.

## La lectura de fondo

El perfil dice algo consistente: **lo que se construyó está bien construido, y lo
que falta es casi todo de la misma naturaleza**. Cinco de los ocho dominios están
clavados en 3 por el mismo motivo —existe, es reproducible, pero nadie le ha
puesto un número que obligue a actuar—. No es un problema de instrumentación,
que está resuelta. Es que medir es la parte fácil y decidir qué es inaceptable
es la difícil.
