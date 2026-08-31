# Experimento 3 — degradación correlacionada · RESULTADO

Ejecutado el 30/08/2026 sobre GKE con Cloud Service Mesh activo.

## Resultado

| Dato | Valor |
|---|---|
| Inicio de la degradación | 22:39:47 |
| Fin | 22:46:47 |
| Mezcla de tráfico | 15 % fallos · 25 % latencia 900 ms · 60 % limpio |
| Tasa de error máxima | **15,1 %** |
| p99 máximo | **1.278 ms** |
| Condición de alerta cierta a las | 22:39:50 |
| **MTTD (condición)** | **3 s** |
| **MTTD (hasta notificar)** | **~63 s** |
| Objetivo | < 120 s |

**Objetivo cumplido**, pero el número necesita tres matices para no ser engañoso.

## Matiz 1 — el 2σ no está haciendo trabajo estadístico

La línea base de la última hora era de errores prácticamente nulos. Con μ ≈ 0 y
σ ≈ 0, el umbral μ + 2σ también es ≈ 0, así que **cualquier error lo supera**.
En este experimento la regla se comportó de hecho como «cualquier error, más una
brecha de p99», no como una detección de anomalías propiamente dicha.

Esto no invalida la regla: en un sistema con línea base ruidosa —que es donde se
justifica— el 2σ sí discriminaría. Pero sobre un laboratorio limpio no se puede
afirmar que el mecanismo estadístico esté demostrado. Está desplegado y es
correcto; no está *ejercitado*.

## Matiz 2 — 3 s está por debajo de la resolución de muestreo

La consulta se hizo con paso de 10 s. Un MTTD de 3 s significa, honestamente,
**«por debajo de la primera muestra»**. Afirmar 3 s como cifra exacta sería
darle una precisión que el método no tiene. La lectura correcta es *detección
prácticamente inmediata*.

## Matiz 3 — el número que le importa a un operador es 63 s, no 3 s

Los 3 s son el tiempo hasta que la condición es cierta. La política de alerta
lleva `duration = 60s`: exige que la condición se mantenga un minuto antes de
disparar, precisamente para no alertar de picos transitorios. El tiempo real
hasta que se emite la notificación es por tanto **~63 s**.

Y aun así es una cota inferior: no incluye el `group_wait` de Alertmanager ni la
entrega del correo, que no son propiedades del sistema observado.

## Por qué hicieron falta tres experimentos

| Exp | Inyección | Resultado | Qué enseñó |
|---|---|---|---|
| 1 | 200 ms de latencia (NetworkChaos) | p99 247 → **4.900 ms**, cero errores, **sin alerta** | La regla es **ciega** a una degradación pura de latencia. Es el precio, ahora medido, de exigir dos señales. |
| 2 | 10 % de errores (HTTPChaos) | Chaos Mesh reportó éxito, **efecto nulo** | El sidecar de Istio intercepta el tráfico antes del proxy de HTTPChaos. La herramienta dijo que funcionó y no funcionó. |
| 3 | 15 % fallos + 25 % latencia (aplicación) | Ambas señales rotas, **alerta activada** | La regla detecta lo que dice detectar, y en cuánto tiempo. |

## Dos defectos encontrados por los experimentos

**El vector vacío.** Sin ningún 5xx,
`sum(rate(checkout_requests_total{status="server_error"}[5m]))` no devuelve cero:
devuelve un vector **vacío**. Una división vacía deja la condición sin evaluar —
no en falso, en nada. Corregido con `or vector(0)` en cada numerador. Es el mismo
patrón que ya mordió en el indicador de disponibilidad de la fase 3.

**El parser del decimal.** La condición no devuelve `1` cuando es cierta:
devuelve el valor del lado izquierdo, la tasa de error. El script comprobaba
`"${val%.*}" != "0"`, que trunca `0.009` a `0` y da por falsa una condición
verdadera. El experimento 3 llegó a reportarse como «no detectado» cuando la
detección había funcionado en 3 segundos.

Los dos son fallos de la instrumentación de medida, no del sistema medido. Y los
dos habrían pasado inadvertidos si los experimentos hubieran salido «bien» a la
primera: un experimento que confirma lo que esperabas no te enseña dónde está
roto tu instrumento.
