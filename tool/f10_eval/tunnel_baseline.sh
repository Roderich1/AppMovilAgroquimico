#!/usr/bin/env bash
# Evaluación F10 (protocolo v1.0 §1.6): línea base del túnel desde el PC. 10 peticiones
# al endpoint de salud por el origen HTTPS y 10 directas a la API local, espaciadas 4 s
# (respeta el límite de 20/min). Imprime los tiempos totales en ms; el origen no se imprime.
#   tunnel_baseline.sh <etiqueta>   (requiere el entorno cargado)
set -euo pipefail
: "${F03_RUN_DIR:?cargue el entorno}"
label="${1:?etiqueta}"
origin="$(cat "$F03_RUN_DIR/origin")"
csv="$F03_RUN_DIR/series/tunel.csv"
mkdir -p "$(dirname "$csv")"
[ -f "$csv" ] || echo "etiqueta,via,rep,hora_utc,http,total_ms" > "$csv"
for i in $(seq 1 10); do
  for via in tunel local; do
    url=$([ "$via" = tunel ] && echo "$origin/api/v1/health" || echo "http://127.0.0.1:$F03_API_PORT/api/v1/health")
    r=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time 20 "$url" || echo "000 20")
    ms=$(python -I -c "print(round(float('${r#* }')*1000,1))")
    echo "$label,$via,$i,$(date -u +%FT%T.%3NZ),${r% *},$ms" >> "$csv"
  done
  sleep 4
done
grep "^$label," "$csv" | python -I -X utf8 -c '
import sys, math
rows = [l.strip().split(",") for l in sys.stdin]
for via in ("tunel", "local"):
    v = sorted(float(r[5]) for r in rows if r[1] == via)
    p90 = v[math.ceil(0.9 * len(v)) - 1]
    bad = sum(1 for r in rows if r[1] == via and r[4] != "200")
    print(f"{via}: n={len(v)} mediana={(v[4]+v[5])/2:.1f} ms p90={p90:.1f} ms max={v[-1]:.1f} ms errores={bad}")'
