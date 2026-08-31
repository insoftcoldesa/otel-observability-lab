# Libreto del vídeo de demostración

Proyecto integrador · MASS OBAP20264 · duración objetivo **10-12 minutos**

## Antes de grabar

Todo esto tiene que estar abierto en pestañas, **en este orden**, porque durante
la grabación no da tiempo a buscar nada:

1. `docs/integrador/trazas-navegables.md` — con los tres enlaces resueltos
2. Explorador de trazas de Cloud Trace
3. Panel *Golden Signals de Seguridad*
4. Políticas de alerta de Cloud Monitoring
5. Cloud Service Mesh → Servicios
6. Terminal con `kubectl get pods -n otel-lab` ya ejecutado
7. El repositorio en GitHub

**Comprobar que el clúster sigue en pie.** Si ya se ejecutó el `destroy`, el
panel y las alertas habrán desaparecido y medio vídeo no se puede grabar.

---

## Guion

### 0:00 – 0:45 · Qué se construyó

> «Tres microservicios instrumentados con OpenTelemetry, desplegados en GKE con
> Cloud Service Mesh, enviando trazas, métricas y logs a Google Cloud. Encima de
> eso, detección de anomalías por desviación estándar, cuatro señales de
> seguridad y dos experimentos de caos.»

**En pantalla:** diagrama de arquitectura.

No enumerar los módulos del enunciado. Contar qué hace el sistema.

---

### 0:45 – 2:00 · Está vivo (módulo A)

**Terminal:**
```
kubectl get pods -n otel-lab
```

> «Seis pods de aplicación, todos con dos contenedores: la aplicación y su
> sidecar Envoy. El Collector es el único con uno solo, y está excluido a
> propósito: si Envoy interceptara el tráfico de telemetría, generaría trazas
> sobre el envío de trazas.»

**Luego una petición real:**
```
curl -X POST http://<IP>/checkout -H 'Content-Type: application/json' \
  -d '{"cart_id":"demo","items":[{"sku":"SKU-003","qty":1,"unit_price":349.0}]}'
```

> «El nombre y el precio de la respuesta no los tiene service-a. Vienen de
> data-service, que los lee de Cloud SQL. Con eso queda demostrada la cadena de
> tres saltos.»

Señalar `"nombre":"Monitor 27 pulgadas"` con el cursor.

---

### 2:00 – 4:00 · Correlación entre pilares (módulo A + tres pilares)

**Esta es la parte importante del vídeo. No acelerar.**

> «No voy a elegir una traza de una lista. Voy a partir de un identificador de
> negocio, el cart_id, y llegar hasta la traza distribuida.»

Abrir Cloud Logging, filtrar por el `cart_id`, señalar el `trace_id` del log,
copiarlo y pegarlo en Cloud Trace.

> «Del log a la traza sin anotar nada por el camino. Eso es la correlación: el
> log lleva el trace_id porque se emitió dentro del span, no al lado.»

**En la traza sana**, señalar:
- los tres servicios en la misma línea de tiempo
- los spans de negocio: `cart.validate`, `inventory.reserve_stock`
- el span de base de datos, y ahí abrir los atributos:

> «Aquí están las convenciones semánticas: db.system.name, db.collection.name y
> db.query.text. Y fijaos en que la consulta está parametrizada, con el
> marcador, no con el valor. Si aquí fuera el valor, cada consulta sería un texto
> distinto y no se podrían agrupar, además de estar escribiendo datos de cliente
> en la telemetría.»

**Traza lenta:** señalar que un solo span se come el tiempo.
**Traza fallida:** señalar el span en ERROR y que su log lleva `trace_id`, no
`null`.

---

### 4:00 – 6:00 · Detección de anomalías (módulo B)

Abrir la política *Checkout: anomalía correlacionada*.

> «Esto no es un umbral. Compara contra la media móvil de la última hora más dos
> desviaciones estándar.»

Explicar **por qué** con el caso concreto:

> «Un umbral fijo del uno por ciento falla en las dos direcciones a la vez. De
> día, con tráfico alto, el uno por ciento son cientos de peticiones rotas y
> avisa tarde. De noche, dos peticiones fallidas de veinte ya son un diez por
> ciento y avisa sin que pase nada.»

Luego la segunda condición:

> «Y solo salta si además el p99 se sale del SLO. Dos señales independientes
> rotas a la vez son un incidente; una sola es casi siempre ruido.»

Mostrar la guarda de volumen y decir por qué existe:

> «Sin esto, a las cuatro de la mañana con dos peticiones en cinco minutos, una
> sola fallida da un cincuenta por ciento y supera cualquier sigma. Es el modo de
> fallo clásico de la detección estadística: con muestras minúsculas todo parece
> anómalo.»

---

### 6:00 – 8:00 · Caos y MTTD (módulo D)

Abrir `docs/integrador/evidencias/exp1-*.md` y `exp2-*.md`.

> «Dos experimentos: doscientos milisegundos de latencia en service-b y un diez
> por ciento de errores en data-service. El MTTD medido fue de X segundos contra
> un objetivo de dos minutos.»

**Decir cómo se midió, no solo el número:**

> «El MTTD se calcula sobre la serie temporal, no sobre cuándo llegó el correo.
> Medir el correo sería medir el group_wait de Alertmanager y la latencia de
> Gmail, que no son propiedades del sistema. Y lo declaramos como cota inferior:
> es el tiempo hasta que la condición es cierta, no hasta que una persona se
> entera.»

Mostrar el manifiesto y señalar el `duration: 5m`:

> «Reversión automática. Si se corta la sesión o alguien cierra el portátil, el
> experimento se deshace solo. Nunca se depende de que alguien ejecute el
> rollback a mano.»

---

### 8:00 – 9:30 · Seguridad (módulo C)

Abrir el panel *Golden Signals de Seguridad*.

> «Los cuatro golden signals de SRE trasladados a seguridad: tráfico son las
> conexiones externas, errores son las que rechaza el firewall, saturación es el
> egreso hacia internet —la señal de exfiltración— y latencia es el tiempo hasta
> detectar un cambio de IAM.»

**Y decir lo que no funcionó:**

> «Security Command Center no se pudo activar. Se activa a nivel de organización
> y este proyecto cuelga de una cuenta personal que no pertenece a ninguna. Está
> verificado con el comando, no supuesto. Lo sustituimos por métricas basadas en
> registros, que sí operan a nivel de proyecto, pero la cobertura no es la misma:
> SCC además correlaciona con la inteligencia de amenazas de Google, y eso no
> tiene reemplazo.»

Esto **suma**, no resta. Reconocer un límite con la evidencia delante es más
sólido que enseñar un panel y callarse.

---

### 9:30 – 11:00 · Madurez (módulo E)

Mostrar la tabla de los ocho dominios.

> «Media de 3,25 sobre 5. Pero la media importa menos que la forma: cinco de los
> ocho dominios están clavados en el nivel 3 por el mismo motivo. Existen, están
> versionados, se reproducen… y nadie les ha puesto un número cuyo
> incumplimiento obligue a actuar.»

> «La nota más baja es seguridad, un 2, y es la más honesta del informe: los
> umbrales de las alertas son cifras que salieron de mi criterio, no de observar
> semanas de comportamiento real.»

> «Y AIOps se queda en 3 y no en 4 aunque la detección funcione, porque todavía
> no hemos medido su tasa de falsos positivos contra la del umbral estático. La
> alerta de contraste está desplegada para poder medirlo. Mientras el número no
> exista, "reduce ruido" es una hipótesis, y no se le pone un 4 a una hipótesis.»

---

### 11:00 – 12:00 · Cierre

Mostrar el repositorio: IaC, instrumentación, scripts, ADR, documentación.

> «Todo lo que se ha visto está en el repositorio y se levanta con un Terraform y
> un script. Y se desmonta con otro, que borra el balanceador antes que el
> clúster: al revés, la regla de reenvío se queda huérfana fuera del estado de
> Terraform, facturando sin que nadie la vea.»

Ejecutar `scripts/integrador-destruir.sh` en cámara si da tiempo. Cerrar el
laboratorio en pantalla es un buen final y demuestra disciplina de costos.

---

## Reglas de tono

- **Decir por qué, no solo qué.** Que algo funcione se ve en pantalla; por qué
  se decidió así, no.
- **Contar lo que falló.** El pool de conexiones, SCC, el Docker bloqueado. Un
  laboratorio donde todo salió a la primera no se lo cree nadie.
- **No leer este guion.** Son puntos de apoyo, no un texto.
- Si algo se rompe en directo, explicarlo y seguir. Es una demo de
  observabilidad: diagnosticar en vivo es el mejor material posible.
