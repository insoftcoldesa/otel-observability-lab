# 0 · Panorama de la Fase 1

## Qué vamos a construir

Dos microservicios que se llaman entre sí y que hablan con una base de datos, y
que emiten los **tres pilares de la observabilidad** —trazas, métricas y logs—
de forma que un incidente se pueda investigar saltando entre los tres.

```
   cliente
      │  POST /checkout
      ▼
┌──────────────┐   HTTP    ┌──────────────┐   SQL   ┌────────────┐
│  service-a   │ ────────▶ │  service-b   │ ──────▶ │ PostgreSQL │
│  :8000       │           │  :8001       │         │  :5432     │
│  checkout    │           │  inventario  │         │            │
└──────┬───────┘           └──────┬───────┘         └────────────┘
       │                          │
       └──── OTLP/gRPC :4317 ─────┘
                    │
                    ▼
            OTel Collector (Fase 2)
```

Dos servicios y no uno, porque **el problema interesante de la observabilidad
distribuida es el salto entre procesos**. Con un solo servicio no se puede
demostrar propagación de contexto, que es la mitad del criterio R3.

## Las ocho tareas

| Tarea | Qué produce | Por qué la pide la rúbrica |
|---|---|---|
| T1.1 | `service-a` con `POST /checkout` | Hay que tener algo que observar |
| T1.2 | `service-b` + PostgreSQL con 10 SKUs | R1 exige acceso a base de datos instrumentado |
| T1.3 | Auto-instrumentación | R1 pide **auto** instrumentation explícitamente |
| T1.4 | 3 spans de negocio con atributos | R1 pide **custom** instrumentation explícitamente |
| T1.5 | Counter, Histogram, UpDownCounter | Pilar de métricas |
| T1.6 | Logs JSON con `trace_id` | Pilar de logs, y base de la correlación de R3 |
| T1.7 | Exportador OTLP/gRPC | Sin esto la telemetría no sale del proceso |
| T1.8 | `?fail=true` y `?delay=N` | Sin errores fabricados no hay capturas de trazas de error |

## Por qué auto **y** custom instrumentation

La rúbrica pide las dos, y no es capricho. Son complementarias:

- **La auto-instrumentación** cubre lo genérico y aburrido: cada request HTTP,
  cada consulta SQL, la propagación de contexto entre servicios. Es *gratis* en
  esfuerzo y cubre el 80 % de lo que necesitas. Su límite es que **no sabe nada
  de tu negocio**: ve un `UPDATE`, no ve "una reserva de inventario".
- **Los spans de negocio** cubren lo que solo tú sabes: qué significa validar un
  carrito, cuánto descuento se aplicó, cuánto stock quedó. Cuestan código, así
  que se ponen con criterio —tres o cuatro por servicio, no treinta.

Un laboratorio con solo auto-instrumentación se ve genérico. Uno con solo spans
manuales es trabajo desperdiciado. La combinación es el punto.

## Lo que NO es la Fase 1

- **No hay Collector todavía.** Durante la Fase 1 la telemetría sale a la
  consola. Esto es deliberado: te deja verificar la instrumentación sin depender
  de que otra pieza funcione. El Collector es la Fase 2.
- **No hay Jaeger, ni Grafana, ni dashboards.** Las capturas de evidencia
  necesitan esas herramientas y llegan después.
- **No hay nube.** Todo local.

## Cuánto toma

Unas 3–4 horas si sigues la guía sin desviarte. La página que más se atasca en
la práctica es la [6, logs correlacionados](Fase-1-06-Logs.md), porque mezcla el
sistema de logging de Python con el de uvicorn.

---

**Siguiente:** [1 · Preparar el entorno](Fase-1-01-Entorno.md)
