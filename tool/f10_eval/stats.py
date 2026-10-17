"""Evaluación F10 (protocolo v1.0 §0.8 y §1.8): estadísticos de una serie a partir del CSV crudo.

Mediana, p90 por rango más cercano (posición ceil(0,9·n) de la lista ordenada), máximo y
errores. Los calentamientos (calentamiento=si) se informan aparte y no entran. Una fila con
error cuenta como fallo y NO se descarta: el criterio exige 0 errores.

    python -I -X utf8 stats.py <serie.csv> <umbral_ms> [columna=duracion_ms]
"""

import csv
import math
import statistics
import sys


def main():
    path, threshold = sys.argv[1], float(sys.argv[2])
    column = sys.argv[3] if len(sys.argv) > 3 else "duracion_ms"
    with open(path, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    warm = [r for r in rows if r.get("calentamiento") == "si"]
    acc = [r for r in rows if r.get("calentamiento") != "si"]
    errors = [r for r in acc if r.get("error") or not r.get(column)]
    values = sorted(float(r[column]) for r in acc if r.get(column) and not r.get("error"))
    n = len(acc)
    print(f"serie={path.rsplit('/', 1)[-1]} n={n} calentamientos={len(warm)} errores={len(errors)}")
    if warm:
        print("calentamiento(s): " + ", ".join(r.get(column, "") for r in warm))
    print("crudos (orden de ejecución): " + ", ".join(r.get(column, "") or "ERROR" for r in acc))
    if values:
        p90 = values[math.ceil(0.9 * len(values)) - 1] if len(values) == n else None
        print(f"mediana={statistics.median(values):.1f} p90={'%.1f' % p90 if p90 is not None else 'n/d (hay errores)'} "
              f"max={values[-1]:.1f} min={values[0]:.1f} (ms)")
        ok = p90 is not None and p90 <= threshold and not errors
        print(f"criterio p90 <= {threshold:g} ms y 0 errores: {'CUMPLE' if ok else 'NO CUMPLE'}")
    for r in errors:
        print(f"error rep {r.get('rep')}: {r.get('error')}")


if __name__ == "__main__":
    main()
