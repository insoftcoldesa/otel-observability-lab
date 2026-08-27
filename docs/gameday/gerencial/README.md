# Informe gerencial del Game Day

Versión alterna del informe, orientada a que **cualquier equipo lo entienda sin
contexto técnico**. No sustituye al informe técnico ni al anexo: los complementa.

**Publicado en:** https://claude.ai/code/artifact/ecdb6656-e9e2-4457-8129-e49cb1485468

## Qué cambia respecto al informe técnico

| | Informe técnico | Informe gerencial |
|---|---|---|
| Audiencia | Evaluador de la asignatura | Cualquier equipo |
| Estructura | Hipótesis, diseño, resultados | Una pregunta por experimento |
| Datos | Tablas | Gráficos, con la tabla al final |
| Lenguaje | `p95`, `span`, `pool` | «latencia», «llamada entre servicios», «conexiones» |
| Notas | Metodología | Solo «cómo leer esto» |

## Decisiones de diseño

**Los titulares son preguntas, no términos.** «¿Y si la red se pone lenta?» en vez
de «Experimento 1: inyección de latencia». Quien lee entiende qué se probó antes
de ver un solo número.

**Cada gráfico responde una sola pregunta.** El de la traza —dónde se fue el
tiempo— es el más valioso: muestra de un vistazo que el retraso se concentró en
un punto y que la base de datos nunca se vio afectada.

**Analogías en lugar de jerga.** La falta de reutilización de conexiones se
explica como «colgar y volver a marcar en cada frase de una conversación».

**Nada se maquilla.** Las dos hipótesis refutadas se presentan como tales y como
el resultado valioso del ejercicio.

## Sobre el color

La paleta se validó con la herramienta del sistema de diseño, no a ojo. El primer
intento usaba **verde para "estado estable" y rojo para "fallo"**, y la validación
lo rechazó: ΔE 4,1 en deuteranopia, es decir, **indistinguibles para una persona
con daltopía rojo-verde**. Se cambió a azul y naranja, que pasan todas las
comprobaciones en modo claro y oscuro (ΔE 24,7 con daltonismo, 33,6 en visión
normal).

El verde y el rojo se reservan para los distintivos de veredicto, que llevan
**icono y texto** además del color, de modo que el color nunca carga el
significado por sí solo.

## Cómo regenerarlo

El fuente es `informe-gerencial.html`, autocontenido: sin dependencias externas,
con los gráficos en SVG en línea y adaptado a tema claro y oscuro.
