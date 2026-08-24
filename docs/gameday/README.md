# Game Day — plan de experimentos de caos

**Entrega: miércoles 26 de agosto de 2026, 23:59.**

| Entregable | Estado |
|---|---|
| `Plan-Game-Day-MASS-OBAP20264.docx` | 🟨 Diseño completo · ejecución y reflexión PENDIENTES |
| Anexo de evidencias (documento aparte) | ⬜ se produce el miércoles |
| Instrumental de ejecución (`chaos/`) | ✅ construido y verificado |

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

## Pendiente de decidir antes del miércoles

El documento está en **6 páginas** y la rúbrica pide **4–5**. Los resultados de
la ejecución añadirán alrededor de una página más. Habrá que recortar: las
opciones son comprimir el apartado de arquitectura, fundir dos tablas o reducir
las referencias.
