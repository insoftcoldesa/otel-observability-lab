"""Genera el Plan de Game Day en Word con formato APA 7.

    uv run --with python-docx python docs/gameday/generar-plan.py

Estado: DISENO COMPLETO. Los apartados de ejecucion y reflexion quedan como
PENDIENTE hasta el miercoles 26; nada se rellena con resultados inventados.
"""
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

DOC = Document()
est = DOC.styles["Normal"]
est.font.name = "Times New Roman"; est.font.size = Pt(12)
est.element.rPr.rFonts.set(qn("w:eastAsia"), "Times New Roman")
pf = est.paragraph_format
pf.line_spacing_rule = WD_LINE_SPACING.DOUBLE; pf.space_after = Pt(0); pf.space_before = Pt(0)
for s in DOC.sections:
    s.top_margin = s.bottom_margin = s.left_margin = s.right_margin = Inches(1)

hdr = DOC.sections[0].header.paragraphs[0]
hdr.alignment = WD_ALIGN_PARAGRAPH.RIGHT
run = hdr.add_run()
for tipo in ("begin", None, "end"):
    el = OxmlElement("w:fldChar") if tipo else OxmlElement("w:instrText")
    if tipo: el.set(qn("w:fldCharType"), tipo)
    else: el.set(qn("xml:space"), "preserve"); el.text = " PAGE "
    run._r.append(el)
hdr.runs[0].font.name = "Times New Roman"; hdr.runs[0].font.size = Pt(12)


def p(t="", *, neg=False, cur=False, al=None, sang=True, esp=False, size=12, sen=False):
    par = DOC.add_paragraph()
    f = par.paragraph_format
    f.line_spacing_rule = WD_LINE_SPACING.SINGLE if sen else WD_LINE_SPACING.DOUBLE
    f.space_before = Pt(12) if esp else Pt(0)
    if al: par.alignment = al
    elif sang: f.first_line_indent = Inches(0.5)
    if t:
        r = par.add_run(t); r.bold, r.italic = neg, cur
        r.font.size = Pt(size); r.font.name = "Times New Roman"
    return par


def h1(t): p(t, neg=True, al=WD_ALIGN_PARAGRAPH.CENTER, esp=True)
def h2(t): p(t, neg=True, sang=False, esp=True)


def tabla(filas, anchos=None):
    t = DOC.add_table(rows=len(filas), cols=len(filas[0]))
    t.style = "Table Grid"
    for i, fila in enumerate(filas):
        for j, celda in enumerate(fila):
            c = t.cell(i, j); c.text = celda
            par = c.paragraphs[0]
            par.paragraph_format.line_spacing_rule = WD_LINE_SPACING.SINGLE
            r = par.runs[0]; r.font.size = Pt(10); r.font.name = "Times New Roman"
            if i == 0: r.bold = True
    return t


# ── PORTADA ────────────────────────────────────────────────────────────────
for _ in range(4): p()
p("Plan de Game Day: diseño de experimentos de caos sobre un pipeline de "
  "observabilidad con OpenTelemetry", neg=True, al=WD_ALIGN_PARAGRAPH.CENTER)
p()
for a in ("Fredy Orlando Pulido Quintero", "Myriam Andrea Martínez Fontecha",
          "Juan Francisco Javier Pérez Rivero", "Nicolás Felipe Torres Amaya"):
    p(a, al=WD_ALIGN_PARAGRAPH.CENTER)
p("Maestría en Arquitectura de Software", al=WD_ALIGN_PARAGRAPH.CENTER)
p("MASS – OBAP20264: Observabilidad en Ambientes Productivos",
  al=WD_ALIGN_PARAGRAPH.CENTER)
p("Maria Fernanda Ochoa Paipilla", al=WD_ALIGN_PARAGRAPH.CENTER)
p("26 de agosto de 2026", al=WD_ALIGN_PARAGRAPH.CENTER)
DOC.add_page_break()

# ── CUERPO ─────────────────────────────────────────────────────────────────
p("Plan de Game Day", neg=True, al=WD_ALIGN_PARAGRAPH.CENTER)

h2("Arquitectura Objetivo")
p("El sistema bajo experimento es el pipeline de la actividad anterior: dos "
  "microservicios FastAPI instrumentados con OpenTelemetry, PostgreSQL y un "
  "Collector que distribuye las tres señales a Jaeger, Prometheus y Loki. El "
  "servicio A recibe el checkout y el servicio B reserva inventario con "
  "sentencias SQL. Ambos exportan por OTLP a una única dirección, sin conocer el "
  "destino final.")

p("Tabla 1", neg=True, sang=False, esp=True)
p("Componentes y dependencias del sistema objetivo", cur=True, sang=False)
tabla([
    ("Componente", "Depende de", "Efecto de su fallo"),
    ("service-a", "service-b, Collector", "Sin checkout: fallo total del negocio"),
    ("service-b", "PostgreSQL, Collector", "Sin reservas: el checkout falla al final"),
    ("PostgreSQL", "—", "service-b no puede reservar inventario"),
    ("Collector", "Jaeger, Prometheus, Loki", "Pérdida de visibilidad, no de servicio"),
])
p("Nota. La dependencia hacia el Collector es deliberadamente débil: la "
  "telemetría no debe formar parte de la ruta crítica. El experimento 3 pone a "
  "prueba precisamente esa afirmación.", sang=False, size=10, sen=True, esp=True)

p("El estado estable se define con los cuatro indicadores ya establecidos: "
  "disponibilidad superior al 99 %, percentil 95 por debajo de 500 ms, tasa de "
  "error inferior al 1 % y caudal mayor que cero. Sin tráfico no hay estado "
  "estable que perturbar, así que todos los experimentos generan carga.")

h2("Hipótesis de Fallo")
p("Las tres siguen el formato de los Principios del Caos y se apoyan en "
  "comportamiento observable: cada una se acepta o rechaza con una consulta "
  "concreta sobre las señales que el sistema ya emite.")

p("Hipótesis 1 (latencia).", neg=True, sang=False, esp=True)
p("En estado estable, cuando se inyectan 200 ms de latencia en la red de salida "
  "del servicio A, esperamos que el percentil 95 de la latencia de checkout "
  "aumente aproximadamente en esa magnitud, que la disponibilidad se mantenga por "
  "encima del 99 % y que la traza distribuida localice el retardo en el span del "
  "cliente HTTP, no en los spans de negocio ni en los de base de datos.")

p("Hipótesis 2 (agotamiento de recursos).", neg=True, sang=False, esp=True)
p("En estado estable, cuando el conjunto de conexiones del servicio B se reduce "
  "por debajo del número de hilos con que el servidor atiende funciones síncronas, "
  "esperamos que bajo concurrencia aparezcan errores del lado del servidor, que la "
  "tasa de error supere el objetivo del 1 % y que los registros correlacionados "
  "permitan atribuir el fallo al módulo de acceso a datos en la petición concreta.")

p("Hipótesis 3 (partición de red).", neg=True, sang=False, esp=True)
p("En estado estable, cuando se corta por completo el tráfico entre el servicio A "
  "y el Collector, esperamos que la aplicación siga atendiendo checkouts sin "
  "degradación medible, y que la única consecuencia observable sea la ausencia de "
  "datos nuevos en los tres backends junto con errores de exportación en los "
  "registros del servicio.")

h2("Diseño de los Experimentos")
p("Cada experimento delimita su radio de impacto, fija una duración justificada e "
  "incorpora reversión automática. La reversión se arma antes de inyectar el "
  "fallo, de modo que una interrupción no deje el sistema degradado.")

p("Tabla 2", neg=True, sang=False, esp=True)
p("Diseño de los tres experimentos de caos", cur=True, sang=False)
tabla([
    ("", "Experimento 1", "Experimento 2", "Experimento 3"),
    ("Tipo de fallo", "Latencia de red", "Agotamiento de recursos", "Partición de red"),
    ("Herramienta", "tc netem", "Reconfiguración del pool", "tc netem con filtro de puerto"),
    ("Radio de impacto", "Salida de red del servicio A", "Servicio B", "Solo el tráfico al puerto 4317"),
    ("Duración", "120 s", "90 s", "90 s"),
    ("Justificación", "Dos ventanas de raspado de métricas", "Suficiente para saturar el conjunto", "Más del doble del reintento del exportador"),
    ("Reversión", "trap retira la regla y verifica", "trap restaura el pool y reinicia", "trap retira el filtro y verifica"),
])
p("Nota. El caos se inyecta desde un contenedor efímero que comparte la pila de "
  "red del objetivo, sin modificar las imágenes del sistema. Así el sistema bajo "
  "experimento es el mismo que se ejecuta normalmente, y no una variante "
  "preparada para ser atacada.", sang=False, size=10, sen=True, esp=True)

p("El experimento 2 merece una precisión metodológica: no es especulativo. Ese "
  "fallo ocurrió realmente durante el análisis de sobrecosto de la actividad "
  "anterior, con más de once mil excepciones en una sola corrida, e invalidó la "
  "medición hasta corregirlo. Persigue por tanto dos objetivos declarados: "
  "reproducir de forma controlada un fallo real documentado y verificar que la "
  "corrección resiste las condiciones que provocaron el incidente. Validar una "
  "remediación bajo el escenario que la motivó es práctica reconocida, y más "
  "honesto que fingir desconocer el resultado.")

h2("Métricas de Observabilidad")
p("Cada hipótesis se valida con un indicador principal y se confirma con las "
  "señales existentes. No se añade instrumentación para el Game Day: necesitarla "
  "sería, en sí mismo, un hallazgo sobre la observabilidad del sistema.")

p("Tabla 3", neg=True, sang=False, esp=True)
p("Señales que validan cada hipótesis", cur=True, sang=False)
tabla([
    ("Hipótesis", "SLI principal", "Trazas", "Registros y métricas"),
    ("1 · Latencia", "Percentil 95 de checkout", "El span cliente HTTP concentra el retardo", "Histograma de duración por estado"),
    ("2 · Recursos", "Tasa de error", "Span de reserva en estado de error", "Registros con el identificador de traza y la excepción"),
    ("3 · Partición", "Disponibilidad (sin cambio esperado)", "Ausencia de trazas nuevas", "Errores de exportación; caída de métricas del Collector"),
])
p("Nota. La correlación por identificador de traza, verificada en la actividad "
  "anterior, es lo que permite pasar del indicador agregado a la petición "
  "concreta que lo produjo.", sang=False, size=10, sen=True, esp=True)

h2("Ejecución")
p("PENDIENTE. Programada para el miércoles 26 de agosto de 2026. Se ejecutará al "
  "menos el experimento 1, por ser el que emplea la herramienta indicada en la "
  "actividad, y los resultados, capturas y registros se recogerán en el anexo de "
  "evidencias, en documento aparte.", neg=True)
p("Los prerequisitos están construidos y verificados: los guiones de los tres "
  "experimentos, la biblioteca común de inyección y reversión, y una comprobación "
  "previa que valida el stack, la herramienta de red y —lo más importante— que la "
  "reversión retira efectivamente la regla inyectada. Esa comprobación se ejecutó "
  "y quedó en verde.")

h2("Resultados y Reflexión")
p("PENDIENTE hasta la ejecución. Este apartado comparará el resultado esperado "
  "frente al observado para cada hipótesis, identificará la debilidad sistémica "
  "revelada y propondrá remediaciones concretas.", neg=True)

DOC.add_page_break()
p("Referencias", neg=True, al=WD_ALIGN_PARAGRAPH.CENTER)
for r in [
    "Basiri, A., Behnam, N., de Rooij, R., Hochstein, L., Kosewski, L., Reynolds, "
    "J., & Rosenthal, C. (2016). Chaos engineering. IEEE Software, 33(3), 35–41. "
    "https://doi.org/10.1109/MS.2016.60",
    "Beyer, B., Murphy, N. R., Rensin, D. K., Kawahara, K., & Thorne, S. (2018). "
    "The site reliability workbook: Practical ways to implement SRE. O'Reilly Media.",
    "OpenTelemetry Authors. (2025). OpenTelemetry documentation. Cloud Native "
    "Computing Foundation. https://opentelemetry.io/docs/",
    "Rosenthal, C., & Jones, N. (2020). Chaos engineering: System resiliency in "
    "practice. O'Reilly Media.",
]:
    par = p(r, sang=False)
    par.paragraph_format.left_indent = Inches(0.5)
    par.paragraph_format.first_line_indent = Inches(-0.5)

DOC.save("docs/gameday/Plan-Game-Day-MASS-OBAP20264.docx")
print("plan generado")
