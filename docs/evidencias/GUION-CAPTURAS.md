# Guion de capturas — Fases 1 y 3

Seis pasos. Al final tienes las seis capturas que piden R1 y R3, y las tres de
R3 son **de la misma traza**, que es lo que califica el criterio.

Tiempo estimado: 10 minutos.

**Convención de nombres:** `RX-NN-descripcion.png` en esta misma carpeta.

---

## Paso 0 · Preparar

```bash
make local-up          # espera a los 8 healthy
make traces            # genera trafico y te da los trace_id ya elegidos
```

`make traces` imprime los enlaces armados. **No cierres esa terminal**: vas a
copiar de ahí durante todo el guion.

> Los `trace_id` caducan: Jaeger guarda las trazas en memoria y `make local-down`
> las borra. Si te interrumpes más de una hora, vuelve a correr `make traces` y
> usa los nuevos.

---

## Paso 1 · `R1-01-traza-ok.png` — la traza exitosa

Abre el enlace de **R1-01-traza-ok** que imprimió `make traces`.

**Antes de capturar, despliega todos los spans** (botón `Expand All` arriba a la
derecha de la cascada). Lo que tiene que verse:

- El árbol completo con los dos servicios: `service-a` y `service-b`.
- Los spans manuales (`checkout.validate_cart`, `checkout.apply_discount`,
  `inventory.reserve_stock`) **entrelazados** con los automáticos (`SELECT`,
  `UPDATE`, `POST`).
- Que `SELECT` y `UPDATE` cuelgan de `inventory.reserve_stock`.

Eso último es lo que demuestra auto **y** custom instrumentation en un solo
árbol, que es literalmente lo que pide R1.

## Paso 2 · `R1-02-traza-error.png` — la traza con error

Abre el enlace de **R1-02-traza-error**.

Despliega el span `inventory.injected_failure` y **abre su pestaña `Logs`**
(dentro del span, no la de Grafana): ahí está el evento `exception` con el
traceback.

Lo que tiene que verse:

- Los iconos rojos de error subiendo por la cadena: `inventory.injected_failure`
  → `POST /inventory/reserve` → `POST` (cliente) → `POST /checkout`.
- El evento `exception` desplegado.

**El punto de esta captura es que el error atraviesa los dos servicios**, no que
un span esté rojo.

## Paso 3 · `R1-03-traza-lenta.png` — la traza lenta

Abre el enlace de **R1-03-traza-lenta** (~810 ms).

Lo que tiene que verse: el span `inventory.injected_delay` ocupando casi toda la
barra. La comparación con el paso 1 (13 ms) es el argumento: **se ve dónde se fue
el tiempo**, no solo que fue lento.

---

## Paso 4 · `R3-01-traza.png` — la traza de la correlación

Ahora empieza R3, y a partir de aquí **todo es sobre el mismo `trace_id`**.

Copia el `trace_id` que `make traces` marcó bajo *CAPTURAS DE R3* y abre su
enlace de Jaeger.

**Asegúrate de que el `trace_id` se lee en la captura** — arriba, junto al nombre
de la traza. Es la prueba de que las tres capturas son la misma petición; sin él,
las tres imágenes no demuestran correlación.

## Paso 5 · `R3-02-log.png` — los logs de esa traza

1. Abre **Grafana → Explore** (http://localhost:3000/explore).
2. Datasource: **Loki**.
3. Pega la consulta que imprimió `make traces`:

   ```logql
   {service_namespace="otel-lab"} | trace_id="<el mismo trace_id>"
   ```

4. `Run query`. Salen ~7 líneas de **los dos servicios**.
5. **Despliega una línea** (clic en la flecha). Aparecen los campos, y entre
   ellos `TraceID` con el botón **`Ver traza en Jaeger`**.

Lo que tiene que verse: la consulta con el `trace_id`, las líneas de los dos
servicios, y **el botón del derived field desplegado**. Ese botón es T3.6: el
salto log → traza.

> Si en vez del botón ves el `trace_id` como texto plano, el derived field no se
> aplicó: reinicia Grafana con `docker compose restart grafana`.

## Paso 6 · `R3-03-exemplar.png` — el exemplar

1. Abre el dashboard: http://localhost:3000/d/otel-lab-slo
2. Rango de tiempo: **Last 30 minutes**.
3. Ve al panel **SLI-2 · Latencia de /checkout**.
4. Busca los **rombos** sobre las líneas (son los exemplars). El de la traza que
   estás siguiendo está a la altura del valor que imprimió `make traces`, ~810 ms.
5. **Pasa el cursor por encima del rombo.** El tooltip muestra el `trace_id` y un
   enlace **`Query with Jaeger`**.

Lo que tiene que verse: el tooltip abierto **con el mismo `trace_id`** de los
pasos 4 y 5. Eso es T3.7, el puente métrica → traza, y es el punto donde más se
suele perder nota.

> Si no ves rombos: sube el rango a *Last 1 hour*, o corre `make smoke` otra vez
> y espera 20 s. Los exemplars solo aparecen si hubo tráfico en la ventana.

---

## Comprobación final

Las tres capturas de R3 deben mostrar **el mismo `trace_id`**. Ábrelas una al
lado de la otra y verifícalo carácter a carácter antes de darlas por buenas — es
lo primero que va a mirar quien califique.

| Archivo | Herramienta | Qué demuestra |
|---|---|---|
| `R1-01-traza-ok.png` | Jaeger | Auto + custom instrumentation en un árbol |
| `R1-02-traza-error.png` | Jaeger | Error propagado entre servicios, con `exception` |
| `R1-03-traza-lenta.png` | Jaeger | La latencia aislada en su propio span |
| `R3-01-traza.png` | Jaeger | La traza de referencia |
| `R3-02-log.png` | Grafana + Loki | Log → traza (T3.6) |
| `R3-03-exemplar.png` | Grafana + Prometheus | Métrica → traza (T3.7) |
