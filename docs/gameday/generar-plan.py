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
# Interlineado 1,5 y no doble: el enunciado pide 4-5 paginas y redaccion
# tecnica, no formato APA. Con doble espacio el contenido que la rubrica puntua
# —20 criterios— no cabe sin mutilarlo. 1,5 es profesional y legible.
pf.line_spacing = 1.5; pf.space_after = Pt(0); pf.space_before = Pt(0)
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
    if sen: f.line_spacing_rule = WD_LINE_SPACING.SINGLE
    else: f.line_spacing = 1.5
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
p("Plan de Game Day: experimentos de caos sobre un pipeline de observabilidad "
  "con OpenTelemetry", neg=True, al=WD_ALIGN_PARAGRAPH.CENTER)
for a in ("Fredy Orlando Pulido Quintero", "Myriam Andrea Martínez Fontecha",
          "Juan Francisco Javier Pérez Rivero", "Nicolás Felipe Torres Amaya"):
    p(a, al=WD_ALIGN_PARAGRAPH.CENTER)
p("Maestría en Arquitectura de Software", al=WD_ALIGN_PARAGRAPH.CENTER)
p("MASS – OBAP20264: Observabilidad en Ambientes Productivos",
  al=WD_ALIGN_PARAGRAPH.CENTER)
p("Maria Fernanda Ochoa Paipilla", al=WD_ALIGN_PARAGRAPH.CENTER)
p("26 de agosto de 2026", al=WD_ALIGN_PARAGRAPH.CENTER)

h2("Arquitectura Objetivo")
p("El sistema es el pipeline de la actividad anterior: dos microservicios "
  "FastAPI instrumentados con OpenTelemetry, PostgreSQL y un Collector que "
  "distribuye las tres señales a Jaeger, Prometheus y Loki. El servicio A recibe "
  "el checkout y el servicio B reserva inventario con sentencias SQL.")

p("El servicio A depende del B y este de PostgreSQL, así que una degradación "
  "aguas abajo alcanza al checkout. La dependencia hacia el Collector es, en "
  "cambio, deliberadamente débil: la telemetría no debe estar en la ruta crítica, "
  "y el experimento 3 pone a prueba esa afirmación.")
p("El estado estable se define con los cuatro indicadores ya establecidos: "
  "disponibilidad superior al 99 %, percentil 95 por debajo de 500 ms, tasa de "
  "error inferior al 1 % y caudal mayor que cero. Sin tráfico no hay estado "
  "estable que perturbar, así que todos los experimentos generan carga.")

h2("Hipótesis de Fallo")
p("Siguen el formato de los Principios del Caos y se apoyan en comportamiento "
  "observable: cada una se acepta o rechaza con una consulta concreta.")

p("Hipótesis 1 (latencia).", neg=True, sang=False, esp=True)
p("En estado estable, cuando se inyectan 200 ms de latencia en la red de salida "
  "del servicio A, esperamos que el percentil 95 aumente en esa magnitud, que la "
  "disponibilidad siga por encima del 99 % y que la traza localice el retardo en "
  "el span del cliente HTTP y no en los de negocio o base de datos.")

p("Hipótesis 2 (agotamiento de recursos).", neg=True, sang=False, esp=True)
p("En estado estable, cuando el conjunto de conexiones del servicio B se reduce "
  "por debajo del número de hilos que atienden funciones síncronas, esperamos "
  "errores del lado del servidor bajo concurrencia, una tasa de error sobre el "
  "1 % y registros correlacionados que atribuyan el fallo al módulo de acceso a "
  "datos en la petición concreta.")

p("Hipótesis 3 (partición de red).", neg=True, sang=False, esp=True)
p("En estado estable, cuando se corta el tráfico entre el servicio A y el "
  "Collector, esperamos que la aplicación siga atendiendo checkouts sin "
  "degradación medible, y que la única consecuencia sea la ausencia de datos "
  "nuevos en los backends junto con errores de exportación.")

h2("Diseño de los Experimentos")
p("Cada experimento delimita su radio de impacto, fija una duración justificada "
  "e incorpora reversión automática, armada antes de inyectar el fallo para que "
  "una interrupción no deje el sistema degradado.")

p("Tabla 1", neg=True, sang=False, esp=True)
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
  "red del objetivo, sin modificar las imágenes: así el sistema bajo experimento "
  "es el mismo que se ejecuta normalmente.", sang=False, size=10, sen=True, esp=True)

p("El experimento 2 no es especulativo: ese fallo ocurrió realmente durante el "
  "análisis de sobrecosto de la actividad anterior, con más de once mil "
  "excepciones, e invalidó la medición hasta corregirlo. Persigue por tanto "
  "reproducir un fallo documentado y verificar que la corrección resiste las "
  "condiciones que lo provocaron, lo que es más honesto que fingir desconocer el "
  "resultado.")

h2("Métricas de Observabilidad")
p("Cada hipótesis se valida con un indicador principal y las señales "
  "existentes. No se añade instrumentación: necesitarla sería, en sí mismo, un "
  "hallazgo sobre la observabilidad del sistema.")

p("Tabla 2", neg=True, sang=False, esp=True)
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

h2("Ejecución y Resultados")
p("Los tres se ejecutaron el 26 de agosto de 2026 en el entorno local, desde un "
  "estado estable limpio. En los tres la reversión automática retiró el fallo y "
  "se verificó que no quedaran reglas activas. Las evidencias completas —salidas "
  "de consola, trazas y consultas— se recogen en el anexo.")

p("Tabla 3", neg=True, sang=False, esp=True)
p("Resultado esperado frente a resultado observado", cur=True, sang=False)
tabla([
    ("Hipótesis", "Esperado", "Observado", "Veredicto"),
    ("1 · Latencia", "p95 sube ~200 ms; retardo en el span cliente", "p95 de 23,9 a 487,5 ms; 498 de 507 ms en el span cliente", "Parcialmente refutada"),
    ("2 · Recursos", "Errores 5xx; tasa sobre el 1 %; logs atribuyen la causa", "736 excepciones; disponibilidad 1,00 a 0,57; tasa 43,5 %; logs SIN causa", "Parcialmente refutada"),
    ("3 · Partición", "La aplicación sigue; solo se pierde visibilidad", "152 checkouts correctos; los indicadores quedan sin datos", "Confirmada"),
])
p("Nota. Las dos refutaciones parciales son el resultado valioso del ejercicio: "
  "un experimento que solo confirma lo que ya se creía no enseña nada.",
  sang=False, size=10, sen=True, esp=True)

p("Experimento 1.", neg=True, sang=False, esp=True)
p("El percentil 95 pasó de 23,9 a 487,5 ms, más del doble de los 200 inyectados. "
  "La traza explica la discrepancia y valida el radio de impacto: de los 507 ms "
  "de la petición más lenta, 498 están en el span del cliente HTTP, mientras el "
  "servicio B responde en 11 ms y las sentencias SQL en menos de 3.")

p("Experimento 2.", neg=True, sang=False, esp=True)
p("La disponibilidad cayó de 1,00 a 0,57 y la tasa de error alcanzó el 43,5 %, "
  "con 736 excepciones. Una corrida previa ejecutada por error sin inyectar el "
  "fallo resultó ser un grupo de control involuntario: con el conjunto en su "
  "valor por defecto y la misma carga, cero excepciones. La remediación aplicada "
  "tras el incidente original resiste.")

p("Experimento 3.", neg=True, sang=False, esp=True)
p("La aplicación atendió 152 checkouts correctos mientras el Collector era "
  "inalcanzable, y el exportador registró fallos con el código DEADLINE_EXCEEDED. "
  "Al retirar la partición la telemetría se restableció sola: no está en la ruta "
  "crítica, como se esperaba.")
p("Dejó además una lección metodológica: durante la partición los cuatro "
  "indicadores mostraban «sin datos», lo que aparenta una caída total. No lo era. "
  "No se puede medir el fallo del sistema de observabilidad usando ese mismo "
  "sistema; hizo falta una fuente externa para saber que la aplicación seguía "
  "atendiendo peticiones.")

h2("Debilidades Sistémicas y Remediación")
p("Debilidad 1: no hay reutilización de conexiones HTTP.", neg=True, sang=False, esp=True)
p("El servicio A abre una conexión nueva en cada llamada al servicio B. Bajo "
  "latencia, el establecimiento de la conexión paga el retardo dos veces más y "
  "multiplica por 2,5 el impacto esperado: una vulnerabilidad invisible en "
  "condiciones normales y amplificadora en cuanto la red se degrada. La "
  "remediación es una sesión persistente con agrupación de conexiones, que "
  "reduciría el impacto a un único trayecto de ida y vuelta.")

p("Debilidad 2: las excepciones no controladas pierden su trazabilidad.", neg=True, sang=False, esp=True)
p("Es el hallazgo más grave. Las 736 excepciones de agotamiento del conjunto "
  "**nunca llegaron al sistema centralizado de registros**. Solo llegó el "
  "mensaje genérico del servidor, sin identificador de traza y sin la traza de "
  "la excepción. Un operador que investigara el incidente consultando los "
  "registros vería que algo falló, pero no qué ni en qué petición.")
p("La causa es conocida: una excepción que escapa hacia el servidor se registra "
  "después de que el span se haya cerrado y pierde el contexto. Ya se corrigió "
  "para el fallo inyectado de forma deliberada, capturándolo dentro del span; el "
  "experimento revela que esa corrección debe generalizarse a toda excepción no "
  "controlada, con un manejador global que la registre dentro del contexto de la "
  "traza. La paradoja merece subrayarse: el sistema correlaciona los errores que "
  "sabe manejar y pierde los inesperados, que son los que más falta hace "
  "investigar.")

p("Referencias", neg=True, al=WD_ALIGN_PARAGRAPH.CENTER, esp=True)
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
