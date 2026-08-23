# ADR-003 · CPU siempre asignada en Cloud Run, y por qué la telemetría se perdía

- **Fecha:** 23 de agosto de 2026
- **Estado:** Aceptada
- **Afecta a:** criterio R2 (Collector desplegado en la nube)

## Contexto

Tras desplegar en Cloud Run, la aplicación funcionaba —los checkouts respondían
200 y el inventario se descontaba— y los logs aparecían en Cloud Logging con su
`trace_id`. Pero **Cloud Trace no recibía ni una sola traza.**

El diagnóstico descartó las causas evidentes en este orden:

1. **Permisos.** El primer arranque sí registró `IAM_PERMISSION_DENIED` en
   `logging.logEntries.create`, pero era propagación: los roles se concedieron
   segundos antes de que arrancara el servicio. Minutos después, los tres roles
   estaban activos y el error había desaparecido.
2. **El SDK no exportaba.** Descartado: se añadió temporalmente un exporter
   `debug` al pipeline de trazas y el Collector registró
   `resource spans: 1, spans: 7`. Los spans **sí llegaban** al Collector.
3. **El Collector no alcanzaba a Google.** Descartado: el exporter `googlecloud`
   no registró ni un error, y una traza suelta sí había llegado.

El dato que resolvió el caso fue el ritmo. Con seis peticiones seguidas llegaban
8 spans de las 42 esperadas. Con **las mismas seis peticiones espaciadas cinco
segundos, llegaron 6 trazas de 6**.

## El problema

Cloud Run, por defecto, **asigna CPU solo mientras se atiende una petición**. Al
enviar la respuesta, la CPU se congela hasta la siguiente.

El `BatchSpanProcessor` del SDK no exporta en línea: encola los spans y los envía
desde un hilo en segundo plano unos segundos después. Ese hilo **necesita CPU que
Cloud Run ya no está dando**. Los spans se quedan en la cola y, cuando la
instancia se recicla, se pierden sin un solo mensaje de error.

Es un fallo silencioso en los dos extremos: el SDK cree haber encolado bien y el
Collector nunca recibe nada que reportar. Por eso ninguna de las hipótesis
iniciales daba señal.

## Decisión

**Fijar `cpu_idle = false` en todos los contenedores** de los dos servicios de
Cloud Run, es decir, CPU siempre asignada y no solo durante la petición.

Como refuerzo, se acorta la ventana en la que puede perderse telemetría:

- `OTEL_BSP_SCHEDULE_DELAY = 1000` en el SDK, frente a los 5 000 ms por defecto.
- `batch.timeout: 1s` en el Collector, frente a los 5 s de la configuración local.

## Consecuencias

**Costo.** Con CPU siempre asignada se factura durante toda la vida de la
instancia, no solo durante las peticiones. El impacto se acota con
`min_instance_count = 0` —las instancias desaparecen tras unos minutos de
inactividad— y `max_instance_count = 2`. Para el volumen de un laboratorio, el
consumo queda muy por debajo de los 180 000 vCPU-s mensuales del nivel gratuito.

**Sigue habiendo pérdida bajo ráfagas.** Con CPU asignada la entrega mejora
mucho, pero enviar decenas de peticiones sin pausa contra instancias que se
crean y destruyen sigue perdiendo lotes. Para capturar evidencia hay que
**espaciar el tráfico**. Es una limitación del entorno, no de la instrumentación:
en local, con los mismos servicios, la entrega fue del 100 % bajo 50 usuarios
concurrentes.

**Lo que esto enseña.** Una arquitectura de telemetría que funciona
perfectamente en un contenedor de larga vida puede perder datos en silencio en
una plataforma sin servidor, y por un motivo que no aparece en ningún log. Es
exactamente el tipo de diferencia entre entornos que justifica desplegar de
verdad en la nube en lugar de dar por bueno lo que funciona en local.

## Alternativas descartadas

**Exportación síncrona (`SimpleSpanProcessor`).** Garantiza la entrega porque
exporta dentro de la petición, con CPU disponible. Rechazada: añade la latencia
del exportador a cada petición, que es justo el sobrecosto que la Fase 4 midió y
recomendó evitar.

**`min_instance_count = 1`.** Mantiene una instancia siempre viva y elimina el
problema del reciclado. Rechazada: factura de forma continua y contradice la
razón por la que se eligió Cloud Run —escala a cero— en el ADR-002.
