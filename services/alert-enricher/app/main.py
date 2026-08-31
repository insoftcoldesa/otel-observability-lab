"""alert-enricher — pega el trace_id a la alerta. MODULO B.

EL HUECO QUE TAPA. Prometheus sabe que el p99 se disparo pero no que peticion
concreta fue lenta. Jaeger tiene esa peticion pero no sabe que hubo una alerta.
El puente entre ambos son los *exemplars*: cuando el SDK registra un valor en el
histograma dentro de un span muestreado, adjunta el trace_id de ese span. Ese
dato viaja hasta Prometheus y se puede consultar.

Asi que cuando llega una alerta, este servicio pregunta a Prometheus "dame los
exemplars del histograma de checkout en la ventana en que la alerta estaba
activa, ordenados por valor" y se queda con el mas lento. El resultado es que el
operador recibe un enlace a la traza del caso peor, no una descripcion generica.

Sin esto el modulo B seria una regla bonita que no lleva a ninguna parte.
"""

import logging
import os
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import FastAPI, Request

logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp":"%(asctime)s","severity":"%(levelname)s","message":%(message)s}',
)
log = logging.getLogger("alert-enricher")

PROMETHEUS = os.environ.get("PROMETHEUS_URL", "http://prometheus:9090")
JAEGER_UI = os.environ.get("JAEGER_UI_URL", "http://localhost:16686")

# Se busca sobre el histograma de duracion porque es donde el SDK adjunta los
# exemplars. El contador no los lleva: un contador no tiene un valor por
# peticion al que colgarlos.
CONSULTA_EXEMPLARS = "checkout_duration_ms_bucket"

app = FastAPI(title="alert-enricher")


async def buscar_traza(inicio: datetime, fin: datetime) -> dict | None:
    """Devuelve el exemplar de mayor latencia en la ventana, o None.

    Se toma el MAS LENTO y no el primero a proposito: la alerta habla del p99,
    asi que la traza util para diagnosticar es la del caso peor. Adjuntar una
    peticion rapida elegida al azar dentro de la ventana seria peor que no
    adjuntar nada, porque induce a pensar que el sistema iba bien.
    """
    parametros = {
        "query": CONSULTA_EXEMPLARS,
        "start": inicio.timestamp(),
        "end": fin.timestamp(),
    }
    try:
        async with httpx.AsyncClient(timeout=5.0) as cliente:
            resp = await cliente.get(
                f"{PROMETHEUS}/api/v1/query_exemplars", params=parametros
            )
            resp.raise_for_status()
            datos = resp.json().get("data", [])
    except Exception as exc:
        # Que falle la busqueda del exemplar NO puede tumbar la notificacion.
        # Una alerta sin trace_id sigue siendo una alerta util; una alerta que
        # nunca se entrega porque el enriquecedor reviento es un incidente
        # invisible. La degradacion aqui es deliberada.
        log.warning('"no se pudieron leer exemplars: %s"', exc)
        return None

    peor = None
    for serie in datos:
        for ejemplo in serie.get("exemplars", []):
            if peor is None or ejemplo.get("value", 0) > peor.get("value", 0):
                peor = ejemplo

    if peor is None:
        return None

    etiquetas = peor.get("labels", {})
    trace_id = etiquetas.get("trace_id") or etiquetas.get("traceID")
    if not trace_id:
        return None

    return {
        "trace_id": trace_id,
        "latencia_ms": round(peor.get("value", 0), 1),
        "enlace": f"{JAEGER_UI}/trace/{trace_id}",
    }


@app.post("/alerta")
async def recibir(request: Request) -> dict:
    cuerpo = await request.json()
    enriquecidas = []

    for alerta in cuerpo.get("alerts", []):
        nombre = alerta.get("labels", {}).get("alertname", "desconocida")
        estado = alerta.get("status", "firing")

        # La ventana se ancla en cuando la alerta EMPEZO, no en "ahora". Para
        # cuando el webhook se ejecuta ya han pasado el group_wait y el `for`
        # de la regla —minuto y medio largo— y el pico que la disparo podria
        # haber quedado fuera de una ventana centrada en el presente.
        crudo = alerta.get("startsAt", "")
        try:
            inicio = datetime.fromisoformat(crudo.replace("Z", "+00:00"))
        except ValueError:
            inicio = datetime.now(timezone.utc) - timedelta(minutes=5)

        traza = None
        if estado == "firing":
            traza = await buscar_traza(inicio - timedelta(minutes=5), inicio + timedelta(minutes=2))

        alerta.setdefault("annotations", {})
        if traza:
            alerta["annotations"]["trace_id"] = traza["trace_id"]
            alerta["annotations"]["traza_url"] = traza["enlace"]
            alerta["annotations"]["peor_latencia_ms"] = str(traza["latencia_ms"])
            log.info(
                '"alerta %s enriquecida con trace_id %s (%s ms)"',
                nombre, traza["trace_id"], traza["latencia_ms"],
            )
        else:
            alerta["annotations"]["trace_id"] = "no disponible"
            log.info('"alerta %s sin exemplar en la ventana"', nombre)

        enriquecidas.append(alerta)

    return {"recibidas": len(enriquecidas), "alertas": enriquecidas}


@app.get("/ultimas")
def ultimas() -> dict:
    """Punto de inspeccion para la evidencia del laboratorio."""
    return {"status": "ok", "prometheus": PROMETHEUS}


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "alert-enricher"}
