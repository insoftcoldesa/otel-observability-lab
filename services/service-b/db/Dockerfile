# syntax=docker/dockerfile:1
#
# PostgreSQL con los datos semilla horneados, para correr como contenedor
# sidecar en Cloud Run.
#
# Por que un sidecar y no Cloud SQL: Cloud SQL no esta en el free tier y
# CLAUDE.md lo prohibe expresamente. Por que un sidecar y no SQLite: cambiar de
# motor obligaria a reescribir el acceso a datos de service-b y, sobre todo,
# cambiaria los spans de base de datos de psycopg2 por los de sqlite3 —
# justamente la evidencia que sostiene R1. El sidecar conserva el codigo y la
# telemetria identicos a los de local.
#
# El almacenamiento es efimero: al escalar a cero se pierde el inventario y se
# vuelve a sembrar en el siguiente arranque. Para un laboratorio es correcto, y
# ademas hace cada demostracion reproducible desde el mismo estado.
FROM postgres:16-alpine
COPY init.sql /docker-entrypoint-initdb.d/init.sql
