# Game Day — plan de experimentos de caos

**Entrega: miércoles 26 de agosto de 2026, 23:59.**

| Entregable | Estado |
|---|---|
| `Plan-Game-Day-MASS-OBAP20264.docx` | ✅ **5 páginas** · diseño, ejecución y reflexión |
| `Anexo-Evidencias-Game-Day.docx` | ✅ **4 páginas** · salidas literales de consola |
| Instrumental (`chaos/`) | ✅ los 3 experimentos ejecutados |

## Resultados

| Hipótesis | Veredicto | Dato |
|---|---|---|
| 1 · Latencia | Parcialmente refutada | p95 de 23,9 a **487,5 ms**, más del doble de lo inyectado |
| 2 · Recursos | Parcialmente refutada | 736 excepciones, disponibilidad 1,00 → **0,57**; pero los logs **no** atribuyen la causa |
| 3 · Partición | Confirmada | **152 checkouts correctos** sin Collector |

**Dos debilidades sistémicas encontradas:**

1. **Sin reutilización de conexiones HTTP.** `requests.post()` abre una conexión
   nueva por llamada, así que bajo latencia el handshake paga el retardo dos
   veces más: impacto ×2,5. Remediación: `requests.Session` con pooling.
2. **Las excepciones no controladas pierden trazabilidad.** Las 736 excepciones
   nunca llegaron a Loki — solo el mensaje genérico, sin `trace_id` ni traceback.
   El sistema correlaciona los errores que sabe manejar y pierde los inesperados,
   que son los que más falta hace investigar.

## Para ejecutar el miércoles

```bash
make local-down && make local-up     # estado estable limpio, inventario sembrado
bash chaos/preflight-gameday.sh      # NO ejecuta experimentos; verifica que todo esté listo

bash chaos/exp1-latencia-red.sh      # el que exige la rúbrica (tc netem)
bash chaos/exp2-agotamiento-pool.sh  # opcional
bash chaos/exp3-particion-red.sh     # opcional
```

Cada guion imprime los SLIs antes y durante el fallo, y **revierte solo**.

## Decisiones de diseño que conviene recordar

**El caos no modifica las imágenes del laboratorio.** Se inyecta desde un
contenedor efímero que comparte la pila de red del objetivo. Dos razones: las
imágenes son evidencia del laboratorio de OTel —su tamaño está reportado— y, más
importante, el sistema bajo experimento debe ser **el mismo** que corre
normalmente. Si hay que modificarlo para poder atacarlo, ya no se está probando
el sistema real.

**La reversión se arma antes de inyectar.** El `trap` se instala antes de la
primera regla, no después. Si se armara después y el guion fallara en medio, la
degradación quedaría puesta indefinidamente.

**La reversión se verifica, no se supone.** Después de retirar la regla se
consulta `tc qdisc show` y se comprueba que no queda nada. El preflight prueba
ese mecanismo completo —aplica una regla inocua de 1 ms y confirma que
desaparece— antes de permitir que se ejecute nada.

**El experimento 2 valida una remediación, no descubre un fallo.** El
agotamiento del pool ocurrió de verdad en el benchmark de la actividad anterior
(11 236 excepciones, medición invalidada). Ya está corregido. Reproducirlo ahora
sirve para comprobar que la corrección aguanta, y así se declara en el documento:
formular una hipótesis fingiendo desconocer el resultado sería deshonesto.

## Sobre la extensión

El plan quedó en **5 páginas**, dentro del 4–5 que pide la rúbrica, sin recortar
ningún criterio puntuable. La clave fue revisar una suposición propia: el
enunciado **no pide formato APA**, solo 4–5 páginas y redacción técnica. Con
doble espacio los 20 criterios no caben sin mutilarlos; con interlineado 1,5 sí.
