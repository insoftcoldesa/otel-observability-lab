"""Reporte ejecutivo del proyecto integrador, en Word con formato APA 7.

    uv run --with python-docx python docs/integrador/generar-reporte.py

Objetivo: 10 paginas. Se comprueba paginando con Word, no estimando:

    osascript -e 'tell application "Microsoft Word"
        set d to open file name POSIX file "<ruta>" as string
        set n to (compute statistics d statistic statistic pages)
        close d saving no
        return n
    end tell'

TODAS LAS CIFRAS SON MEDIDAS, NINGUNA ESTIMADA. Su procedencia:
  · p99 de 247 -> 4900 ms .......... experimento 1, Managed Prometheus
  · 15,1 % de error y p99 1278 ms .. experimento 3, Managed Prometheus
  · MTTD 3 s / ~63 s ............... experimento 3, consulta a la serie temporal
  · 686 spans, 0 fallidos .......... contadores internos del Collector
  · 3,25/5 de madurez ............. docs/integrador/madurez.md
  · 21 min de aprovisionamiento ... gcloud container fleet mesh describe
"""
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

DOC = Document()
est = DOC.styles["Normal"]
est.font.name = "Times New Roman"
est.font.size = Pt(12)
est.element.rPr.rFonts.set(qn("w:eastAsia"), "Times New Roman")
pf = est.paragraph_format
pf.line_spacing_rule = WD_LINE_SPACING.DOUBLE
pf.space_after = Pt(0)
pf.space_before = Pt(0)
for s in DOC.sections:
    s.top_margin = s.bottom_margin = s.left_margin = s.right_margin = Inches(1)

hdr = DOC.sections[0].header.paragraphs[0]
hdr.alignment = WD_ALIGN_PARAGRAPH.RIGHT
run = hdr.add_run()
for instr in ("begin", None, "end"):
    el = OxmlElement("w:fldChar") if instr else OxmlElement("w:instrText")
    if instr:
        el.set(qn("w:fldCharType"), instr)
    else:
        el.set(qn("xml:space"), "preserve"); el.text = " PAGE "
    run._r.append(el)
hdr.runs[0].font.name = "Times New Roman"
hdr.runs[0].font.size = Pt(12)


def p(texto="", *, negrita=False, cursiva=False, align=None, sangria=True,
      espacio=False, size=12, sencillo=False):
    par = DOC.add_paragraph()
    par.paragraph_format.line_spacing_rule = (
        WD_LINE_SPACING.SINGLE if sencillo else WD_LINE_SPACING.DOUBLE)
    if align:
        par.alignment = align
    if sangria and align is None:
        par.paragraph_format.first_line_indent = Inches(0.5)
    if espacio:
        par.paragraph_format.space_before = Pt(12)
    if texto:
        r = par.add_run(texto)
        r.bold, r.italic = negrita, cursiva
        r.font.size = Pt(size)
    return par


def h2(t):
    p(t, negrita=True, sangria=False, espacio=True)


def tabla(cabeceras, filas, titulo=None):
    if titulo:
        par = p(titulo, negrita=True, sangria=False, espacio=True, sencillo=True)
        par.paragraph_format.space_after = Pt(4)
    t = DOC.add_table(rows=1, cols=len(cabeceras))
    t.style = "Table Grid"
    for i, c in enumerate(cabeceras):
        celda = t.rows[0].cells[i]
        celda.text = ""
        r = celda.paragraphs[0].add_run(c)
        r.bold = True
        r.font.size = Pt(10)
        celda.paragraphs[0].paragraph_format.line_spacing_rule = WD_LINE_SPACING.SINGLE
    for fila in filas:
        celdas = t.add_row().cells
        for i, v in enumerate(fila):
            celdas[i].text = ""
            r = celdas[i].paragraphs[0].add_run(str(v))
            r.font.size = Pt(10)
            celdas[i].paragraphs[0].paragraph_format.line_spacing_rule = WD_LINE_SPACING.SINGLE
    p(sencillo=True).paragraph_format.space_after = Pt(6)


# ════════════════════════════ PORTADA ══════════════════════════════════════
for _ in range(4):
    p()
p("Observabilidad integral sobre Google Kubernetes Engine: malla de servicios, "
  "detección de anomalías, señales de seguridad e ingeniería del caos",
  negrita=True, align=WD_ALIGN_PARAGRAPH.CENTER)
p()
for autor in ("Fredy Orlando Pulido Quintero", "Myriam Andrea Martínez Fontecha",
              "Juan Francisco Javier Pérez Rivero", "Nicolás Felipe Torres Amaya"):
    p(autor, align=WD_ALIGN_PARAGRAPH.CENTER)
p("Maestría en Arquitectura de Software", align=WD_ALIGN_PARAGRAPH.CENTER)
p("MASS – OBAP20264: Observabilidad en Ambientes Productivos",
  align=WD_ALIGN_PARAGRAPH.CENTER)
p("Maria Fernanda Ochoa Paipilla", align=WD_ALIGN_PARAGRAPH.CENTER)
p("31 de agosto de 2026", align=WD_ALIGN_PARAGRAPH.CENTER)
DOC.add_page_break()

# ════════════════════════════ CUERPO ═══════════════════════════════════════
p("Observabilidad integral sobre Google Kubernetes Engine",
  negrita=True, align=WD_ALIGN_PARAGRAPH.CENTER)

h2("Resumen ejecutivo")
p("Se desplegó en Google Cloud un sistema de tres microservicios instrumentados "
  "con OpenTelemetry sobre Kubernetes con malla de servicios gestionada, con "
  "detección de anomalías por desviación estándar, cuatro señales de seguridad "
  "derivadas de registros de red y auditoría, y tres experimentos de ingeniería "
  "del caos. Toda la infraestructura se creó y se destruyó con Terraform.")
p("El resultado más valioso del ejercicio no fue el tiempo de detección medido, "
  "sino los dos defectos que los experimentos revelaron en la propia "
  "instrumentación de medida. Un experimento que confirma lo esperado no informa "
  "sobre dónde está roto el instrumento; los dos que fallaron sí lo hicieron.")

h2("Arquitectura")
p("La cadena de peticiones atraviesa tres procesos y una base de datos "
  "administrada: service-a recibe el checkout, llama por HTTP a service-b para "
  "reservar inventario, y este consulta a data-service, que lee el catálogo de "
  "productos en Cloud SQL. Tres saltos son el mínimo para que el trazado "
  "distribuido demuestre algo que no demostraría con dos: que el contexto se "
  "propaga más allá de un único salto entre procesos.")
p("Cada servicio corre con dos contenedores en Kubernetes: la aplicación y un "
  "sidecar Envoy inyectado por Cloud Service Mesh. El OpenTelemetry Collector es "
  "la única excepción y está excluido de la malla de forma deliberada: si Envoy "
  "interceptara su tráfico, se generarían trazas sobre el envío de trazas.")
p("La portabilidad del pipeline se sostiene en un hecho concreto y verificable: "
  "entre la configuración del Collector para el laboratorio local y la de Google "
  "Cloud solo cambian los exportadores. Receptores, procesadores y tuberías son "
  "idénticos. La independencia de proveedor no es una afirmación de diseño, es "
  "un diff.")

tabla(["Componente", "Tecnología", "Función"],
      [["service-a", "FastAPI · Python 3.12", "Checkout, expuesto por balanceador"],
       ["service-b", "FastAPI · Python 3.12", "Reserva de inventario"],
       ["data-service", "FastAPI · Python 3.12", "Catálogo, convenciones semánticas de BD"],
       ["Collector", "OTel Contrib 0.115", "Recepción OTLP y exportación"],
       ["Cloud SQL", "PostgreSQL 15, IP privada", "Inventario y catálogo"],
       ["GKE", "Estándar, 2 nodos e2-standard-2", "Cómputo"],
       ["Cloud Service Mesh", "Gestionado, asm-managed", "mTLS y telemetría de malla"]],
      "Tabla 1. Componentes desplegados")

h2("Instrumentación y los tres pilares")
p("La instrumentación combina el agente automático de OpenTelemetry con spans y "
  "métricas escritos a mano. El aporte específico de data-service son las "
  "convenciones semánticas de base de datos declaradas explícitamente, siguiendo "
  "la versión 1.28 de la especificación. No es un detalle formal: sin "
  "db.collection.name y db.operation.name todas las consultas caen en un mismo "
  "grupo y resulta imposible responder qué tabla se degradó.")
p("La consulta se registra parametrizada, con el marcador y no con el valor. Si "
  "se registrara interpolada, cada ejecución sería un texto distinto —inútil para "
  "agrupar— y además se estarían escribiendo datos de cliente en la telemetría.")
p("La correlación entre pilares quedó verificada de la forma más exigente "
  "posible: partiendo de un identificador de negocio. Se consulta Cloud Logging "
  "por el campo cart_id y el registro devuelve el identificador de traza en el "
  "campo nativo trace de la plataforma, lo que hace que la consola ofrezca un "
  "enlace directo a la traza distribuida. La correlación no es una convención "
  "propia que haya que explicar: la entiende la plataforma.")

tabla(["Caso", "Identificador de traza", "Qué demuestra"],
      [["Sana", "89b5444cb33105a0…", "Tres servicios en una traza; spans de negocio y de BD"],
       ["Lenta (800 ms)", "4c8c9f508d17faee…", "Un solo span concentra el tiempo; justifica el p99"],
       ["Fallida (502)", "94405bcd1bd2367f…", "Span en ERROR con excepción dentro del span"]],
      "Tabla 2. Trazas de evidencia capturadas")

p("El tercer caso merece una nota. La excepción se registra dentro del span y no "
  "fuera, por lo que su línea de registro lleva identificador de traza en vez de "
  "un valor nulo. Si el error se dejara escapar hasta el servidor de aplicación, "
  "el registro se emitiría ya fuera del contexto y quedaría huérfano, "
  "precisamente en el caso en que más falta hace poder correlacionarlo.")

h2("Detección de anomalías")
p("La regla de alerta no usa un umbral fijo. Compara la tasa de error contra su "
  "propia media móvil de la última hora más dos desviaciones estándar, y exige "
  "además que el percentil 99 de latencia haya superado el objetivo de servicio. "
  "Un umbral fijo falla en dos direcciones opuestas a la vez: con tráfico alto, "
  "un uno por ciento son cientos de peticiones rotas y avisa tarde; con tráfico "
  "bajo, dos peticiones fallidas de veinte ya son un diez por ciento y avisa sin "
  "que ocurra nada.")
p("La exigencia de dos señales simultáneas es lo que de verdad elimina ruido. Un "
  "rastreador pidiendo referencias inexistentes mueve la tasa de error sin que el "
  "servicio esté mal; una consulta pesada puntual mueve el percentil sin que "
  "nadie lo note. Que ambas se rompan a la vez distingue un incidente de una "
  "casualidad. La regla incorpora además una guarda de volumen mínimo, porque con "
  "muestras minúsculas cualquier valor parece anómalo: dos peticiones de madrugada "
  "con una fallida producen un cincuenta por ciento que supera cualquier sigma.")
p("La misma expresión se ejecuta en los dos entornos. Al recibirse las métricas "
  "por Managed Service for Prometheus, la política en Google Cloud usa el mismo "
  "PromQL que el Prometheus local, de modo que la equivalencia entre entornos se "
  "puede comprobar en vez de suponerse.")

h2("Señales de seguridad")
p("Los cuatro golden signals de la ingeniería de fiabilidad se trasladaron al "
  "dominio de seguridad: el tráfico son las conexiones entrantes externas, los "
  "errores son las conexiones que el cortafuegos rechaza, la saturación es el "
  "volumen de datos que sale hacia internet —la señal que delata una "
  "exfiltración— y la latencia es el tiempo hasta detectar un cambio de permisos. "
  "El valor de esta traducción es práctico: un equipo que ya lee paneles de "
  "fiabilidad puede leer este sin formación adicional, y la seguridad deja de "
  "vivir en una herramienta aparte.")
p("Security Command Center no pudo activarse. Se activa a nivel de organización y "
  "el proyecto pertenece a una cuenta personal que no forma parte de ninguna, lo "
  "que se verificó por comando y no se supuso. Las cuatro señales lo sustituyen "
  "operando sobre registros de flujo, de cortafuegos y de auditoría, que sí "
  "funcionan a nivel de proyecto. La cobertura no es equivalente: la herramienta "
  "ausente correlaciona además con inteligencia de amenazas, y eso no tiene "
  "sustituto. Queda declarado como brecha.")

h2("Ingeniería del caos y tiempo de detección")
p("Se ejecutaron tres experimentos. Los dos primeros no produjeron un tiempo de "
  "detección, cada uno por un motivo distinto, y ambos resultaron más "
  "informativos que el tercero.")

tabla(["Exp.", "Inyección", "Resultado medido", "Hallazgo"],
      [["1", "200 ms de latencia en service-b (tc netem)",
        "p99 de 247 a 4.900 ms · cero errores · sin alerta",
        "La regla es ciega ante degradación pura de latencia"],
       ["2", "10 % de errores en data-service (proxy HTTP)",
        "La herramienta reportó éxito · efecto nulo",
        "El sidecar intercepta el tráfico antes que el proxy del caos"],
       ["3", "15 % fallos y 25 % latencia (aplicación)",
        "15,1 % de error · p99 1.278 ms · alerta activada",
        "La regla detecta lo que afirma detectar"]],
      "Tabla 3. Experimentos de caos y resultados")

p("El primer experimento multiplicó la latencia por veinte sin generar un solo "
  "error, y la alerta no se activó. El comportamiento es correcto —la regla exige "
  "las dos señales— pero mide por primera vez el costo de esa decisión de diseño. "
  "Exigir dos señales reduce el ruido y, a cambio, deja sin detectar una "
  "degradación severa de latencia. El dato convierte una preferencia de diseño en "
  "una compensación cuantificada.")
p("El segundo experimento reprodujo un patrón conocido y peligroso: la "
  "herramienta de caos informó de una inyección exitosa que nunca tuvo efecto "
  "observable. Se detectó porque se buscaron los registros de degradación del "
  "servicio intermedio antes de interpretar el resultado. Si se hubiera aceptado "
  "el «cero errores» como éxito, se habría concluido que el sistema resiste "
  "cuando en realidad nada lo había puesto a prueba.")

tabla(["Métrica", "Valor medido", "Objetivo"],
      [["Tasa de error alcanzada", "15,1 %", "—"],
       ["Percentil 99 máximo", "1.278 ms", "—"],
       ["Detección de la condición", "3 s", "—"],
       ["Notificación al operador", "≈ 63 s", "< 120 s"]],
      "Tabla 4. Tiempo de detección, experimento 3")

p("El tiempo de detección se calcula sobre la serie temporal y no sobre la "
  "llegada del aviso por correo, que dependería del agrupamiento del gestor de "
  "alertas y de la latencia del proveedor, ninguno de los cuales es propiedad del "
  "sistema observado. Los tres segundos corresponden al instante en que la "
  "condición se vuelve cierta; la política exige que se mantenga sesenta segundos "
  "antes de notificar, para no alertar de picos transitorios, de modo que la "
  "cifra relevante para un operador es la segunda. Ambas son cotas inferiores.")
p("Una limitación honesta del resultado: la línea base tenía errores "
  "prácticamente nulos, por lo que el umbral de dos sigmas degeneró en «cualquier "
  "error». El mecanismo estadístico está desplegado y es correcto, pero no quedó "
  "ejercitado. Demostrarlo exigiría una línea base ruidosa que este laboratorio no "
  "tiene.")

h2("Defectos encontrados por los experimentos")
p("Dos fallos de la instrumentación de medida salieron a la luz, ambos capaces de "
  "haber invalidado las conclusiones sin dejar rastro.")
p("El primero es una consulta que devuelve vacío en lugar de cero. Cuando no ha "
  "ocurrido ningún error, el selector de la métrica no coincide con ninguna serie "
  "y la suma devuelve un vector vacío; una división vacía deja la condición sin "
  "evaluar, ni verdadera ni falsa, sino inexistente. La alerta habría permanecido "
  "muda ante cualquier incidente que empezara desde un estado limpio, que es "
  "exactamente como empiezan casi todos.")
p("El segundo es una comparación numérica errónea al leer el resultado: la "
  "condición devuelve el valor de la tasa de error y no un indicador binario, de "
  "modo que un truncamiento de decimales convertía un 0,009 verdadero en un cero "
  "falso. El tercer experimento llegó a reportarse como no detectado cuando la "
  "detección había funcionado en tres segundos.")
p("Ninguno de los dos habría aparecido si los experimentos hubiesen salido bien a "
  "la primera. Es el argumento central a favor de la ingeniería del caos: su "
  "valor no está en confirmar que el sistema resiste, sino en descubrir que el "
  "instrumento con el que se mide no funcionaba.")

h2("Madurez de observabilidad")
p("La autoevaluación sobre ocho dominios arroja una media de 3,25 sobre 5. La "
  "media importa menos que la forma del perfil: cinco de los ocho dominios están "
  "detenidos en el nivel 3 por el mismo motivo. Existen, están versionados y se "
  "reproducen, pero nadie les ha puesto un número cuyo incumplimiento obligue a "
  "actuar. El problema no es de instrumentación, que está resuelta; medir es la "
  "parte fácil y decidir qué resulta inaceptable es la difícil.")

tabla(["Dominio", "Nivel", "Qué lo frena"],
      [["Tres pilares", "4", "La correlación se navega a mano"],
       ["OpenTelemetry", "4", "Sin muestreo adaptativo"],
       ["AIOps", "3", "La reducción de ruido no se ha medido"],
       ["Observabilidad de red", "3", "Sin objetivo numérico sobre señales de red"],
       ["DataOps", "3", "Sin atribución de costo por señal"],
       ["Fiabilidad", "3", "El presupuesto de error no tiene consecuencia"],
       ["Seguridad", "2", "Umbrales sin calibrar; herramienta no disponible"],
       ["Resiliencia", "4", "Dominio más maduro: se rompió y se midió"]],
      "Tabla 5. Autoevaluación de madurez")

p("La calificación más baja es la más honesta del informe. Los umbrales de las "
  "alertas de seguridad son cifras derivadas del criterio de quien escribió la "
  "infraestructura, no de observar semanas de comportamiento normal, y una alerta "
  "sin calibrar avisará de más o de menos sin que se sepa de cuál. La detección de "
  "anomalías se mantiene en nivel 3 y no en 4 aunque funcione, porque su tasa de "
  "falsos positivos frente al umbral estático todavía no se ha medido; mientras "
  "ese número no exista, la reducción de ruido es una hipótesis.")
p("El plan a tres meses ataca primero lo que convierte hipótesis en números: "
  "medir falsos positivos durante treinta días, calibrar los umbrales de seguridad "
  "contra tráfico real e implementar el consumo del presupuesto de error con "
  "congelación de despliegues. El objetivo es una media de 4,1.")

h2("Control de costos")
p("La infraestructura se creó con veinticuatro recursos de Terraform y se destruyó "
  "con una sola operación al terminar la jornada. El desmontaje elimina el "
  "balanceador antes que el clúster y espera confirmación: en el orden inverso, la "
  "regla de reenvío queda huérfana fuera del estado de Terraform y sigue "
  "facturando sin aparecer en ningún inventario. Es la fuga de costo más común al "
  "desmontar Kubernetes administrado.")

h2("Conclusiones")
p("El sistema demuestra los tres pilares emitidos, correlacionados y navegables "
  "desde un identificador de negocio, sobre una arquitectura de tres saltos con "
  "malla de servicios y base de datos administrada. La detección correlacionada "
  "funciona y su tiempo hasta notificar, sesenta y tres segundos, cumple el "
  "objetivo con holgura.")
p("Con igual énfasis se documenta lo que no se logró: la herramienta de seguridad "
  "no pudo activarse por una restricción estructural de la cuenta, el mecanismo "
  "estadístico de la detección no quedó ejercitado por falta de una línea base "
  "ruidosa, y la regla resultó ciega ante una degradación de latencia sin errores. "
  "Los tres son resultados, no omisiones.")
p("La lección transferible es metodológica. Los experimentos que fallaron "
  "aportaron más que el que funcionó, porque revelaron defectos en el instrumento "
  "de medida que ninguna revisión de código había detectado. Un sistema "
  "observable no es el que emite telemetría, sino aquel en el que se ha "
  "comprobado que la telemetría dice la verdad cuando algo se rompe.")

DOC.add_page_break()
p("Referencias", negrita=True, align=WD_ALIGN_PARAGRAPH.CENTER)
for ref in [
    "Beyer, B., Jones, C., Petoff, J., & Murphy, N. R. (2016). Site reliability "
    "engineering: How Google runs production systems. O'Reilly Media.",
    "Google Cloud. (2026). Cloud Service Mesh documentation. "
    "https://cloud.google.com/service-mesh/docs",
    "Majors, C., Fong-Jones, L., & Miranda, G. (2022). Observability engineering: "
    "Achieving production excellence. O'Reilly Media.",
    "OpenTelemetry Authors. (2026). Semantic conventions for database client calls "
    "(v1.28). https://opentelemetry.io/docs/specs/semconv/database/",
    "Rosenthal, C., & Jones, N. (2020). Chaos engineering: System resiliency in "
    "practice. O'Reilly Media.",
]:
    par = p(ref, sangria=False)
    par.paragraph_format.first_line_indent = Inches(-0.5)
    par.paragraph_format.left_indent = Inches(0.5)

RUTA = "docs/integrador/Reporte-Proyecto-Integrador.docx"
DOC.save(RUTA)
print(f"guardado: {RUTA}")
