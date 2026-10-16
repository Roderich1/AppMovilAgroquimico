"""F06 (D4): contraste independiente del oráculo escrito a mano.

Recalcula, sólo con la biblioteca estándar y sin el código bajo prueba (Dart o
TypeScript), las aportaciones y las celdas esperadas a partir de
docs/evidence/F06_DATASET.csv, y las compara con las tablas escritas a mano
F06_EXPECTED_CONTRIBUTIONS.csv y F06_EXPECTED_CELLS.csv.

Reglas aplicadas (F06 §3 y §5, política provisional F07-POL-01 con k=3):
- Consumo: aplicaciones del TITULAR no revertidas; la reversión es de la
  aplicación entera. Lo del FAMILIAR no se proyecta. «Adherente casero» no está
  vinculado y no llega a Central.
- Necesidad: el último valor declarado; una cancelación posterior deja la
  aportación CANCELLED, que no cuenta.
- Celda: proyección × producto (canónico en la etapa CANONICAL) × unidad base.
  Se divulga con al menos 3 Members distintos; un cero explícito cuenta.

Uso: python -I tool/f06_d4/oracle_check.py docs/evidence [--central volcado.csv [--only F1]]
"""
import csv
import pathlib
import sys

UNBOUND = {"Adherente casero"}
ALIASES = {"Bellator": "Belator"}  # asociación confirmada en la etapa CANONICAL
THRESHOLD = 3
BASE = {"L": "ML", "KG": "G"}


def read(path):
    with open(path, newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def contributions(events):
    reversed_groups = {(e["farmer"], e["group"]) for e in events if e["event"] == "REVERSAL"}
    consumption = {}
    for e in events:
        if e["event"] != "APPLICATION" or e["person"] != "TITULAR" or e["product"] in UNBOUND:
            continue
        if (e["farmer"], e["group"]) in reversed_groups:
            consumption.setdefault((e["farmer"], e["campaign"], e["product"], BASE[e["unit"]]), None)
            continue
        key = (e["farmer"], e["campaign"], e["product"], BASE[e["unit"]])
        consumption[key] = (consumption.get(key) or 0) + int(e["quantity_base"])
    needs = {}
    for e in events:
        key = (e["farmer"], e["campaign"], e["product"], BASE.get(e["unit"], ""))
        if e["event"] == "NEED":
            needs[key] = ("ACTIVE", int(e["quantity_base"]))
        elif e["event"] == "NEED_CANCEL":
            needs[key] = ("CANCELLED", None)
    rows = []
    for (farmer, campaign, product, unit), total in consumption.items():
        # Una celda propia sin ninguna aplicación vigente nunca se publicó.
        if total is not None:
            rows.append((farmer, campaign, "CONSUMPTION_TOTAL", product, unit, "ACTIVE", str(total)))
    for (farmer, campaign, product, unit), (status, total) in needs.items():
        rows.append((farmer, campaign, "DECLARED_NEED", product, unit, status, "" if total is None else str(total)))
    return sorted(rows), consumption, needs


def cells(rows, consumption, needs, stage):
    canonical = (lambda p: ALIASES.get(p, p)) if stage == "CANONICAL" else (lambda p: p)
    groups = {}
    for farmer, campaign, kind, product, unit, status, total in rows:
        key = (campaign, kind, canonical(product), unit)
        members, amount = groups.setdefault(key, (set(), 0))
        if status == "ACTIVE":
            members.add(farmer)
            groups[key] = (members, amount + int(total))
    # Claves vistas en el dataset sin ninguna aportación vigente: ausencia.
    seen = {(c, "CONSUMPTION_TOTAL", canonical(p), u) for (_, c, p, u) in consumption}
    seen |= {(c, "DECLARED_NEED", canonical(p), u) for (_, c, p, u) in needs}
    out = []
    for key in sorted(seen):
        members, amount = groups.get(key, (set(), 0))
        if not members:
            out.append((stage, *key, "0", "", "ABSENT", "", ""))
        elif len(members) >= THRESHOLD:
            out.append((stage, *key, str(len(members)), str(amount), "DISCLOSED", str(amount), str(len(members))))
        else:
            out.append((stage, *key, str(len(members)), str(amount), "SUPPRESSED_UNDER_THRESHOLD", "", ""))
    return out


def main(folder):
    folder = pathlib.Path(folder)
    events = read(folder / "F06_DATASET.csv")
    rows, consumption, needs = contributions(events)
    expected_rows = sorted(tuple(r.values()) for r in read(folder / "F06_EXPECTED_CONTRIBUTIONS.csv"))
    computed_cells = cells(rows, consumption, needs, "RAW") + cells(rows, consumption, needs, "CANONICAL")
    expected_cells = [tuple(r.values()) for r in read(folder / "F06_EXPECTED_CELLS.csv")]
    ok = True
    for name, computed, expected in [
        ("aportaciones", rows, expected_rows),
        ("celdas", sorted(computed_cells), sorted(expected_cells)),
    ]:
        missing = sorted(set(expected) - set(computed))
        extra = sorted(set(computed) - set(expected))
        print(f"{name}: calculadas={len(computed)} a mano={len(expected)} faltan={len(missing)} sobran={len(extra)}")
        for row in missing:
            print("  sólo a mano: " + ",".join(row))
        for row in extra:
            print("  sólo calculada: " + ",".join(row))
        ok = ok and not missing and not extra and len(computed) == len(expected)
    print("ORÁCULO COINCIDE" if ok else "ORÁCULO NO COINCIDE")
    return 0 if ok else 1


def central(folder, dump, only=None):
    """Compara un volcado de Central (central_dump.sh) con el oráculo a mano;
    con [only], sólo las filas de ese agricultor (ruta física)."""
    expected = sorted(
        tuple(r.values())
        for r in read(pathlib.Path(folder) / "F06_EXPECTED_CONTRIBUTIONS.csv")
        if only is None or r["farmer"] == only
    )
    obtained = sorted(tuple(r.values()) for r in read(dump))
    missing = sorted(set(expected) - set(obtained))
    extra = sorted(set(obtained) - set(expected))
    print(f"Central: obtenidas={len(obtained)} esperadas={len(expected)} faltan={len(missing)} sobran={len(extra)}")
    for row in missing:
        print("  falta en Central: " + ",".join(row))
    for row in extra:
        print("  sobra en Central: " + ",".join(row))
    ok = not missing and not extra and len(obtained) == len(expected)
    print("CENTRAL COINCIDE CON EL ORÁCULO" if ok else "CENTRAL NO COINCIDE")
    return 0 if ok else 1


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--central" in args:
        index = args.index("--central")
        only = args[args.index("--only") + 1] if "--only" in args else None
        sys.exit(main(args[0]) or central(args[0], args[index + 1], only))
    sys.exit(main(args[0] if args else "docs/evidence"))
