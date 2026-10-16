"""F08-BKP: instantánea completa de la app aislada para comparar antes/después.

  snapshot.py <carpeta>          lee <carpeta>/db/<base> y <carpeta>/invoices/*,
                                 escribe <carpeta>/dump.json (filas completas) e
                                 imprime un resumen sin valores
  snapshot.py --compare <antes> <después>
                                 compara dos instantáneas: tabla por tabla, IGUAL,
                                 TRANSFORMACIÓN ESPERADA o DIFERENTE (falla)

dump.json queda en la carpeta del ensayo (fuera de cualquier worktree) y no se
publica: contiene datos sintéticos de negocio. La base no guarda tokens ni
contraseñas (viven en el almacén cifrado del sistema). El resumen y la
comparación sólo imprimen nombres de tabla, conteos, huellas de 12 hex y
nombres de columna.

Transformaciones que exige el protocolo al restaurar en otra instalación:
  app_settings   sólo `activated_installation_ref` pasa a la instalación nueva
  sync_outbox    ACKED intacta; lo pendiente/pausado pasa a RESTORE_PAUSED
                 (cambian sólo `status` y `updated_at`)
  purchases      `invoice_image_path` apunta a la carpeta de este teléfono con el
                 mismo nombre de archivo
"""
import hashlib
import json
import pathlib
import re
import sqlite3
import sys

DB_NAME = "agroquimicos_v2.db"
SENDABLE_OR_PAUSED = {"PENDING", "SENDING", "OUTCOME_UNKNOWN", "AUTH_PAUSED", "OWNER_PAUSED", "RESTORE_PAUSED"}


def h12(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:12]


def take(folder):
    folder = pathlib.Path(folder)
    db = sqlite3.connect((folder / "db" / DB_NAME).resolve().as_uri(), uri=True)
    db.row_factory = sqlite3.Row
    tables = [r[0] for r in db.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")]
    dump = {"user_version": db.execute("PRAGMA user_version").fetchone()[0], "tables": {}, "photos": {}}
    for table in tables:
        rows = [dict(r) for r in db.execute(f'SELECT * FROM "{table}" ORDER BY rowid')]
        dump["tables"][table] = rows
    db.close()
    for photo in sorted((folder / "invoices").glob("*")):
        if photo.is_file():
            dump["photos"][photo.name] = hashlib.sha256(photo.read_bytes()).hexdigest()
    (folder / "dump.json").write_text(json.dumps(dump, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"user_version={dump['user_version']} tablas={len(tables)} fotos={len(dump['photos'])}")
    for table, rows in dump["tables"].items():
        print(f"  {table}: {len(rows)} filas huella={h12(rows)}")
    print(f"  fotos: huella={h12(dump['photos'])}")


def compare(before_dir, after_dir):
    before = json.loads((pathlib.Path(before_dir) / "dump.json").read_text(encoding="utf-8"))
    after = json.loads((pathlib.Path(after_dir) / "dump.json").read_text(encoding="utf-8"))
    failures = 0

    def report(table, verdict, detail=""):
        nonlocal failures
        if verdict == "DIFERENTE":
            failures += 1
        print(f"{verdict:24} {table}{(' — ' + detail) if detail else ''}")

    for table in sorted(set(before["tables"]) | set(after["tables"])):
        a = before["tables"].get(table)
        b = after["tables"].get(table)
        if a is None or b is None:
            report(table, "DIFERENTE", "falta en una de las dos")
            continue
        if a == b:
            report(table, "IGUAL", f"{len(a)} filas")
            continue
        if len(a) != len(b):
            report(table, "DIFERENTE", f"{len(a)} → {len(b)} filas")
            continue
        if table == "app_settings":
            ka = {r["key"]: r["value"] for r in a}
            kb = {r["key"]: r["value"] for r in b}
            changed = sorted(k for k in set(ka) | set(kb) if ka.get(k) != kb.get(k))
            ok = changed == ["activated_installation_ref"] and kb[changed[0]] is not None
            report(table, "TRANSFORMACIÓN ESPERADA" if ok else "DIFERENTE", f"claves cambiadas: {changed}")
        elif table == "sync_outbox":
            core = lambda r: {k: v for k, v in r.items() if k not in ("status", "updated_at")}
            same_core = [core(x) for x in a] == [core(y) for y in b]
            statuses_ok = all(
                (x["status"] == "ACKED" and y["status"] == "ACKED")
                or (x["status"] in SENDABLE_OR_PAUSED and y["status"] == "RESTORE_PAUSED")
                or (x["status"] == y["status"] and x["status"] not in SENDABLE_OR_PAUSED)
                for x, y in zip(a, b))
            counts = {}
            for x, y in zip(a, b):
                counts[f"{x['status']}→{y['status']}"] = counts.get(f"{x['status']}→{y['status']}", 0) + 1
            report(table, "TRANSFORMACIÓN ESPERADA" if same_core and statuses_ok else "DIFERENTE",
                   f"operación/cantidad/causalidad iguales={same_core}; estados {counts}")
        elif table == "purchases":
            strip = lambda r: {k: v for k, v in r.items() if k != "invoice_image_path"}
            # Rutas de Android (/) o de una prueba en Windows (\).
            names = lambda rows: [re.split(r"[\\/]", r["invoice_image_path"])[-1] if r["invoice_image_path"] else None for r in rows]
            ok = [strip(x) for x in a] == [strip(y) for y in b] and names(a) == names(b)
            report(table, "TRANSFORMACIÓN ESPERADA" if ok else "DIFERENTE",
                   "sólo cambia la carpeta de invoice_image_path" if ok else "difiere más que la ruta")
        else:
            columns = sorted({k for x, y in zip(a, b) for k in x if x.get(k) != y.get(k)})
            report(table, "DIFERENTE", f"columnas: {columns}")

    photos_ok = before["photos"] == after["photos"]
    report("fotos (nombre y SHA-256)", "IGUAL" if photos_ok else "DIFERENTE", f"{len(before['photos'])} → {len(after['photos'])}")
    print("Resultado:", "PASS" if failures == 0 else f"FAIL ({failures})")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    if sys.argv[1] == "--compare":
        sys.exit(compare(sys.argv[2], sys.argv[3]))
    take(sys.argv[1])
