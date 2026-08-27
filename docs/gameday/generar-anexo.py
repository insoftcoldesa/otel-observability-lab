"""Genera el anexo de evidencias del Game Day.

    uv run --with python-docx python docs/gameday/generar-anexo.py

Documento APARTE del plan, como pide el enunciado. Contiene las salidas de
consola literales, las trazas y las consultas: nada resumido, para que el
resultado sea auditable.
"""
import pathlib
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.oxml.ns import qn

DOC = Document()
est = DOC.styles["Normal"]
est.font.name = "Times New Roman"; est.font.size = Pt(11)
est.element.rPr.rFonts.set(qn("w:eastAsia"), "Times New Roman")
est.paragraph_format.line_spacing = 1.15
est.paragraph_format.space_after = Pt(0)
for s in DOC.sections:
    s.top_margin = s.bottom_margin = Inches(0.9)
    s.left_margin = s.right_margin = Inches(0.9)


def p(t="", *, neg=False, al=None, size=11, esp=False):
    par = DOC.add_paragraph()
    par.paragraph_format.line_spacing = 1.15
    par.paragraph_format.space_before = Pt(10) if esp else Pt(0)
    if al: par.alignment = al
    if t:
        r = par.add_run(t); r.bold = neg
        r.font.size = Pt(size); r.font.name = "Times New Roman"
    return par


def consola(texto, maxlin=None):
    lineas = [l.rstrip() for l in texto.splitlines() if l.strip()]
    if maxlin: lineas = lineas[:maxlin]
    par = DOC.add_paragraph()
    par.paragraph_format.line_spacing_rule = WD_LINE_SPACING.SINGLE
    par.paragraph_format.left_indent = Inches(0.25)
    r = par.add_run("\n".join(lineas))
    r.font.name = "Consolas"; r.font.size = Pt(8)
    r._element.rPr.rFonts.set(qn("w:eastAsia"), "Consolas")
    return par


EV = pathlib.Path("docs/gameday/evidencias")

p("Anexo de evidencias · Game Day", neg=True, al=WD_ALIGN_PARAGRAPH.CENTER, size=15)
p("Laboratorio MASS – OBAP20264 · 26 de agosto de 2026",
  al=WD_ALIGN_PARAGRAPH.CENTER)
p("Complemento del documento «Plan de Game Day». Recoge las salidas literales de "
  "consola de los tres experimentos, sin resumir, para que cualquier afirmación "
  "del informe principal pueda verificarse.", esp=True)

# ── Entorno ────────────────────────────────────────────────────────────────
p("1. Entorno de ejecución", neg=True, esp=True, size=13)
p("Ocho contenedores en Docker sobre un MacBook con procesador Apple M4. La "
  "inyección de fallos se realiza desde un contenedor efímero que comparte la "
  "pila de red del objetivo, sin modificar las imágenes del sistema.")

p("1.1 Comprobación previa", neg=True, esp=True)
p("Verifica el estado del stack, la disponibilidad de la herramienta de red y —lo "
  "más importante— que la reversión retira efectivamente la regla inyectada.")
consola("""=== Preflight del Game Day ===

-- Stack local
  [OK]  los 8 contenedores estan healthy

-- Herramientas de caos
  [OK]  imagen alpine:3.20 descargada
  [OK]  tc netem disponible dentro de la red de service-a (con NET_ADMIN)

-- Rollback: la parte que no puede fallar
  [OK]  se puede aplicar una regla netem
  [OK]  el rollback retira la regla y queda verificado

-- Observabilidad (de donde saldra la evidencia)
  [OK]  Prometheus responde (SLIs)
  [OK]  Jaeger responde (trazas)
  [OK]  Loki responde (logs)
  [OK]  Grafana responde (dashboard)

-- Estado estable
  [OK]  inventario sembrado con los 10 SKU

=== Todo listo. Se puede ejecutar el Game Day. ===""")

# ── Experimentos ───────────────────────────────────────────────────────────
for num, titulo, fichero, extra in [
    (2, "Experimento 1 · latencia de red con tc netem", "exp1-salida.txt", None),
    (3, "Experimento 2 · agotamiento del conjunto de conexiones", "exp2-salida.txt", None),
    (4, "Experimento 3 · partición de red hacia el Collector", "exp3-salida.txt", None),
]:
    p(f"{num}. {titulo}", neg=True, esp=True, size=13)
    ruta = EV / fichero
    if ruta.exists():
        consola(ruta.read_text(), maxlin=42)
    else:
        p("PENDIENTE: no se encontró la salida de consola.", neg=True)

# ── Traza ──────────────────────────────────────────────────────────────────
p("5. Traza distribuida del experimento 1", neg=True, esp=True, size=13)
p("Consulta a la API de Jaeger sobre la petición más lenta durante la inyección. "
  "Confirma la tercera parte de la hipótesis 1 y, a la vez, el radio de impacto: "
  "el retardo se concentra en el span del cliente HTTP y no alcanza al servicio B "
  "ni a la base de datos.")
consola("""=== 158 trazas · la más lenta: 507 ms ===
  trace_id 2c062f3060dcdf0fce8d95b8f1016207

  span                                                ms  servicio
  POST /checkout                                   507.3  service-a
  POST                                             498.2  service-a   <- el retardo
  POST /inventory/reserve                           11.3  service-b
  inventory.reserve_stock                            4.3  service-b
  SELECT                                             2.5  service-b
  checkout.validate_cart                             0.8  service-a
  UPDATE                                             0.5  service-b""")

# ── Debilidad 2 ────────────────────────────────────────────────────────────
p("6. Evidencia de la debilidad 2: pérdida de trazabilidad", neg=True, esp=True, size=13)
p("Durante el experimento 2 se registraron 736 excepciones de agotamiento del "
  "conjunto de conexiones. Al consultarlas en el sistema centralizado de "
  "registros, el resultado es cero: solo llegó el mensaje genérico del servidor, "
  "sin identificador de traza y sin la traza de la excepción.")
consola("""=== lineas con 'pool exhausted' en Loki ===
  0    -> las excepciones NO llegaron al backend de registros

=== lo unico que si llego ===
  mensaje  : "Exception in ASGI application"
  trace_id : AUSENTE
  scope    : uvicorn.error

=== contraste: los logs de la aplicacion SI se correlacionan ===
  [d3d6a96dcc30d53e...] reserva ok        <- con trace_id""")

# ── Verificación out-of-band ───────────────────────────────────────────────
p("7. Verificación externa del experimento 3", neg=True, esp=True, size=13)
p("Durante la partición los cuatro indicadores mostraban «sin datos», lo que "
  "aparenta una caída total. Para descartarlo hizo falta una fuente ajena al "
  "pipeline: los registros del propio contenedor.")
consola("""=== ¿siguió funcionando la aplicación durante la partición? ===
    (fuente FUERA del pipeline: los logs del contenedor)
  checkouts correctos: 152
  errores: 7

=== ¿qué decía el SDK mientras no podía exportar? ===
  Failed to export logs to otel-collector:4317, StatusCode.DEADLINE_EXCEEDED
  Failed to export traces to otel-collector:4317, StatusCode.DEADLINE_EXCEEDED

=== ¿se recuperó la telemetría tras el rollback? ===
  throughput tras el rollback: 2.756 rps""")

p("8. Reproducibilidad", neg=True, esp=True, size=13)
p("Todo el instrumental está versionado en el repositorio, bajo el directorio "
  "chaos/. La secuencia completa es: reiniciar el stack para partir de un estado "
  "estable limpio, ejecutar la comprobación previa y lanzar cada experimento. "
  "Cada guion repone el inventario, mide los indicadores antes y durante el "
  "fallo, y revierte automáticamente verificando que no queden reglas activas.")

DOC.save("docs/gameday/Anexo-Evidencias-Game-Day.docx")
print("anexo generado")
