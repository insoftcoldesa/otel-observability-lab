# ADR-002 · Reducir el alcance a una sola nube, y que sea GCP

- **Fecha:** 22 de agosto de 2026
- **Estado:** Aceptada
- **Decide:** Fredy Pulido (coordinación), con el equipo
- **Afecta a:** criterios R2 y R5

## Contexto

La rúbrica pide el OTel Collector desplegado en **dos** nubes. A tres días de la
entrega, ninguna de las dos cuentas estaba creada ni verificada, y la
verificación de facturación puede tardar horas o un día completo en cuentas
nuevas. Era el riesgo número uno del cronograma desde el primer día y no se
destrabó.

Desplegar en dos nubes con las cuentas sin crear implicaba dos rutas de
infraestructura distintas —Terraform, redes, registros de imágenes, permisos— y
la probabilidad de terminar con **ninguna** completa era alta.

## Decisión

**Desplegar en una sola nube, y que sea Google Cloud Platform.**

## Justificación económica

El free tier de las dos plataformas no es comparable, y la diferencia no es de
grado sino de naturaleza.

| Dimensión | GCP | AWS |
|---|---|---|
| Modelo | **Always Free**, permanente | **Créditos** ($100 + $100) que caducan a los 6 meses |
| Cómputo | Cloud Run: 2 M solicitudes, 360 000 GB-s y 180 000 vCPU-s al mes, gratis siempre | ECS Fargate **no tiene nivel gratuito**: consume crédito por segundo de ejecución |
| Inactividad | **Escala a cero: cuesta 0** | La tarea factura mientras exista, se use o no |
| Registro de imágenes | Artifact Registry: 0,5 GB always free | ECR: 500 MB/mes solo durante 12 meses |
| Trazas gestionadas | Cloud Trace, cuota mensual gratuita permanente | X-Ray: 100 000 trazas/mes solo el primer año |
| Logs | Cloud Logging, 50 GiB/mes | CloudWatch: 5 GB/mes |
| Red | No requiere NAT ni balanceador | Sin NAT Gateway obliga a subredes públicas con IP asignada |

**El factor decisivo es la escala a cero.** En Cloud Run se despliega, se captura
la evidencia y se puede dejar el servicio publicado sin costo mientras no reciba
tráfico. En Fargate, olvidar el `terraform destroy` una noche consume crédito
hasta que alguien lo advierta. `CLAUDE.md` recoge esa preocupación en la regla
"nunca dejar nada corriendo de noche"; con Cloud Run la regla deja de ser
necesaria, y eliminar una clase entera de error humano vale más que cualquier
ahorro marginal.

Un factor secundario: las imágenes ya están construidas para `linux/amd64` y
pesan 174 MB y 182 MB. Las dos caben en el medio giga gratuito de Artifact
Registry, sin necesidad de purgar versiones.

## Consecuencias

**Lo que se gana.** Una ruta de infraestructura en lugar de dos, con
probabilidad realista de completarse. Riesgo de costo prácticamente nulo. Menos
superficie que revisar en la revisión cruzada del último día.

**Lo que se pierde, y hay que decirlo.** R2 pide dos nubes y se entrega una:
**el criterio queda parcialmente cubierto**. No se demuestra que la misma
configuración del Collector sirva en dos proveedores distintos, que es
precisamente el argumento de portabilidad de OpenTelemetry.

**Cómo se mitiga.** El argumento de portabilidad sí se sostiene por diseño,
aunque no se demuestre desplegado: la aplicación exporta a una única dirección
OTLP y **no conoce el destino**. Cambiar de nube es cambiar los `exporters` del
Collector, no el código. El repositorio conserva `collector/otel-collector-local.yaml`
y `collector/otel-collector-gcp.yaml`, cuya única diferencia son los exporters,
lo que evidencia el punto sin necesidad de una segunda cuenta.

**Queda anotado como trabajo futuro**, no como olvido: `iac/aws/` mantiene su
lugar en la estructura del repositorio.

## Alternativas descartadas

**Desplegar en las dos de todos modos.** Rechazada por tiempo: con las cuentas
sin verificar, el resultado más probable era dejar las dos a medias.

**Elegir AWS en vez de GCP.** Rechazada por la tabla anterior. Además el equipo
ya tenía decidido Cloud Run frente a GKE (ADR-001), de modo que el camino de GCP
estaba más avanzado en diseño.

**No desplegar en ninguna y declararlo fuera de alcance.** Rechazada: R2 es el
criterio con más peso de infraestructura y entregarlo vacío costaría más que
entregarlo a medias con la limitación documentada.
