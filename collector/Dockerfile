# syntax=docker/dockerfile:1
#
# Imagen del Collector para el stack LOCAL, unicamente.
#
# La imagen oficial es distroless: dentro solo hay /otelcol-contrib, los
# certificados y una config por defecto. Ni shell, ni wget, ni curl. Eso esta
# bien por seguridad, pero deja al contenedor sin nada con que responder a un
# healthcheck de Docker Compose, y la Fase 2 exige los 8 contenedores healthy.
#
# Se le agrega el busybox estatico (~1,5 MB) SOLO para el healthcheck. En la
# nube (Fases 5 y 6) se usa la imagen oficial sin modificar: alli el estado de
# salud lo comprueba la plataforma (Cloud Run, ECS), no Docker Compose.
ARG OTELCOL_VERSION=0.115.1

FROM busybox:1.37.0-uclibc AS tools

FROM otel/opentelemetry-collector-contrib:${OTELCOL_VERSION}
COPY --from=tools /bin/busybox /bin/busybox
