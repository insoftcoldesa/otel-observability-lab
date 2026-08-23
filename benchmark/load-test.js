/**
 * benchmark/load-test.js — carga para medir el overhead de OpenTelemetry (R4).
 *
 * No se corre a mano: lo invoca benchmark/run-benchmark.sh, que se encarga de
 * resetear el stock, reiniciar los servicios y muestrear docker stats.
 *
 * Perfil: rampa 0->50 VU en 60 s · meseta 50 VU durante 300 s · bajada 60 s.
 * Mezcla: 90 % checkouts exitosos, 10 % con ?fail=true.
 */
import http from "k6/http";
import { check } from "k6";
import { Trend, Rate, Counter } from "k6/metrics";

const BASE = __ENV.BASE_URL || "http://localhost:8000";
// El perfil de la rubrica son los valores por defecto. Se pueden acortar para
// validar el tooling sin gastar 7 minutos, pero esos numeros no van al reporte.
const VUS = Number(__ENV.VUS || 50);
const DUR_RAMPA = __ENV.DUR_RAMPA || "60s";
const DUR_MESETA = __ENV.DUR_MESETA || "300s";
const DUR_BAJADA = __ENV.DUR_BAJADA || "60s";
const ESCENARIO = __ENV.ESCENARIO || "desconocido";
const CORRIDA = __ENV.CORRIDA || "0";

// Latencia de los checkouts que DEBEN salir bien. Es la cifra que se compara
// entre escenarios: mezclar aqui los fallos inyectados ensuciaria los
// percentiles con una ruta de codigo distinta (rollback en vez de commit).
const checkoutOk = new Trend("checkout_ok_ms", true);
const checkoutFail = new Trend("checkout_fail_ms", true);
const erroresInesperados = new Counter("errores_inesperados");
const tasaExito = new Rate("tasa_exito");

const SKUS = ["SKU-001", "SKU-002", "SKU-003", "SKU-004", "SKU-005",
              "SKU-006", "SKU-007", "SKU-008", "SKU-009", "SKU-010"];
const CODIGOS = ["OBAP10", "MASS20", "UNIMINUTO5", ""];

export const options = {
  scenarios: {
    carga: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: DUR_RAMPA, target: VUS },   // rampa
        { duration: DUR_MESETA, target: VUS },  // meseta: de aqui salen los numeros
        { duration: DUR_BAJADA, target: 0 },    // bajada
      ],
      gracefulRampDown: "15s",
    },
  },
  thresholds: {
    // Sobre los checkouts que deben salir bien. Si esto se dispara, la maquina
    // esta saturada y la corrida no sirve para comparar.
    "checkout_ok_ms": ["p(95)<1000", "p(99)<2000"],
    // Los 502 inyectados son esperados y van etiquetados aparte; lo que no
    // puede pasar es que fallen los que deberian funcionar.
    "http_req_failed{esperado:no}": ["rate<0.01"],
    "tasa_exito": ["rate>0.98"],
  },
  summaryTrendStats: ["avg", "min", "med", "p(50)", "p(90)", "p(95)", "p(99)", "max", "count"],
  discardResponseBodies: true,   // menos ruido de memoria en el generador
};

function carrito(id) {
  const sku = SKUS[Math.floor(Math.random() * SKUS.length)];
  const code = CODIGOS[Math.floor(Math.random() * CODIGOS.length)];
  return JSON.stringify({
    cart_id: `bench-${ESCENARIO}-${CORRIDA}-${id}`,
    items: [{ sku: sku, qty: 1, unit_price: Math.floor(Math.random() * 90) + 10 }],
    discount_code: code,
  });
}

export function setup() {
  const h = http.get(`${BASE}/health`);
  if (h.status !== 200) throw new Error(`service-a no responde: ${h.status}`);
  return { inicio: Date.now() };
}

export default function () {
  const inyectarFallo = Math.random() < 0.10;
  const url = inyectarFallo ? `${BASE}/checkout?fail=true` : `${BASE}/checkout`;

  const params = {
    headers: { "Content-Type": "application/json" },
    tags: { esperado: inyectarFallo ? "si" : "no", escenario: ESCENARIO },
    timeout: "30s",
  };

  const t0 = Date.now();
  const r = http.post(url, carrito(__VU * 100000 + __ITER), params);
  const ms = Date.now() - t0;

  if (inyectarFallo) {
    checkoutFail.add(ms);
    const bien = check(r, { "fallo inyectado devuelve 502": (x) => x.status === 502 });
    tasaExito.add(bien);
    if (!bien) erroresInesperados.add(1);
  } else {
    checkoutOk.add(ms);
    // 409 sin stock NO es aceptable aqui: significa que el reset de stock que
    // hace run-benchmark.sh no funciono, y los numeros no serian comparables.
    const bien = check(r, { "checkout devuelve 200": (x) => x.status === 200 });
    tasaExito.add(bien);
    if (!bien) erroresInesperados.add(1);
  }
}

export function handleSummary(data) {
  const m = data.metrics;
  const v = (nombre, stat) => (m[nombre] && m[nombre].values[stat]) ?? null;

  const salida = {
    escenario: ESCENARIO,
    corrida: Number(CORRIDA),
    timestamp: new Date().toISOString(),
    duracion_s: data.state.testRunDurationMs / 1000,
    perfil: { vus: VUS, rampa: DUR_RAMPA, meseta: DUR_MESETA, bajada: DUR_BAJADA },
    checkout_ok: {
      count: v("checkout_ok_ms", "count"),
      avg_ms: v("checkout_ok_ms", "avg"),
      p50_ms: v("checkout_ok_ms", "p(50)"),
      p90_ms: v("checkout_ok_ms", "p(90)"),
      p95_ms: v("checkout_ok_ms", "p(95)"),
      p99_ms: v("checkout_ok_ms", "p(99)"),
      max_ms: v("checkout_ok_ms", "max"),
    },
    checkout_fail: {
      count: v("checkout_fail_ms", "count"),
      p95_ms: v("checkout_fail_ms", "p(95)"),
    },
    http: {
      reqs: v("http_reqs", "count"),
      rps: v("http_reqs", "rate"),
      failed_rate: v("http_req_failed", "rate"),
      duration_p95_ms: v("http_req_duration", "p(95)"),
    },
    tasa_exito: v("tasa_exito", "rate"),
    errores_inesperados: v("errores_inesperados", "count") || 0,
    thresholds_ok: Object.values(data.metrics)
      .every((x) => !x.thresholds || Object.values(x.thresholds).every((t) => !t.fails)),
  };

  const destino = __ENV.OUT_JSON || `benchmark/results/raw/${ESCENARIO}-run${CORRIDA}.json`;
  const linea = (k, val, u) =>
    `  ${k.padEnd(22)} ${val === null ? "n/d" : Number(val).toFixed(2).padStart(9)} ${u}`;

  console.log(`
=====================================================
  ${ESCENARIO}  ·  corrida ${CORRIDA}
=====================================================
${linea("checkout ok p50", salida.checkout_ok.p50_ms, "ms")}
${linea("checkout ok p95", salida.checkout_ok.p95_ms, "ms")}
${linea("checkout ok p99", salida.checkout_ok.p99_ms, "ms")}
${linea("throughput", salida.http.rps, "req/s")}
${linea("peticiones ok", salida.checkout_ok.count, "")}
${linea("errores inesperados", salida.errores_inesperados, "")}
`);

  return { [destino]: JSON.stringify(salida, null, 2), stdout: "" };
}
