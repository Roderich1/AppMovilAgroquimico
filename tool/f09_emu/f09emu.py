"""Ayudante de tool/f09_emu/f09emu.sh (F09, emulador). Sólo lectura.

  python -I -X utf8 f09emu.py ui <paquete>            < volcado-uiautomator.xml
  python -I -X utf8 f09emu.py find <paquete> <regex>  < volcado-uiautomator.xml
  python -I -X utf8 f09emu.py has <paquete> <regex>   < volcado-uiautomator.xml
  python -I -X utf8 f09emu.py db <copia.db>

Seguridad: los nodos con password="true" no muestran texto ni descripción, y
nunca se eligen para tocar. Sólo se consideran los nodos del paquete indicado
(o del diálogo de permisos del sistema, cuando se pide explícitamente con el
paquete «permisos»). La consulta de la base abre la COPIA en modo de sólo
lectura y no imprime transcripciones ni campos de la evidencia: sólo cuentas.
"""

import re
import sqlite3
import sys
import xml.etree.ElementTree as ET

PERMISSION_PACKAGES = {
    "com.google.android.permissioncontroller",
    "com.android.permissioncontroller",
}


def _nodes(package):
    root = ET.fromstring(sys.stdin.read())
    allowed = PERMISSION_PACKAGES if package == "permisos" else {package}
    for node in root.iter("node"):
        if node.get("package") not in allowed:
            continue
        yield node


def _center(node):
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
    if not m:
        return None
    x1, y1, x2, y2 = map(int, m.groups())
    if x2 <= x1 or y2 <= y1:
        return None
    return (x1 + x2) // 2, (y1 + y2) // 2


def _label(node):
    if node.get("password") == "true":
        return "[campo de contraseña: contenido omitido]"
    text = (node.get("text") or "").strip()
    desc = (node.get("content-desc") or "").strip()
    hint = (node.get("hint") or "").strip()
    parts = [p for p in (text, desc) if p]
    if hint:
        parts.append(f"(campo «{hint}»)")
    return " | ".join(dict.fromkeys(parts)).replace("\n", " / ")


def ui(package):
    shown = 0
    for node in _nodes(package):
        label = _label(node)
        center = _center(node)
        if not label or center is None:
            continue
        flags = []
        if node.get("class", "").endswith("EditText"):
            flags.append("campo")
        if node.get("focused") == "true":
            flags.append("enfocado")
        if node.get("clickable") == "true":
            flags.append("tocable")
        print(f"{center[0]:>4},{center[1]:<5} {label}" + (f"  [{', '.join(flags)}]" if flags else ""))
        shown += 1
    if shown == 0:
        print(f"(sin elementos visibles de {package})")


def find(package, pattern, tap=True):
    rx = re.compile(pattern, re.IGNORECASE)
    for node in _nodes(package):
        if node.get("password") == "true":
            continue
        label = _label(node)
        center = _center(node)
        if label and center and rx.search(label):
            if tap:
                print(f"{center[0]} {center[1]}")
            return 0
    return 1


def db(path):
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}

    def count(table, where=""):
        if table not in tables:
            return "sin tabla"
        return con.execute(f"SELECT COUNT(*) FROM {table} {where}").fetchone()[0]

    print(f"esquema (user_version)={con.execute('PRAGMA user_version').fetchone()[0]}")
    for table in (
        "persons", "owner_bindings", "campaigns", "farms", "products", "suppliers",
        "purchases", "purchase_items", "applications", "application_items",
        "application_plans", "application_plan_items", "sync_outbox",
        "voice_evidence_consent", "voice_evidence",
    ):
        print(f"{table}={count(table)}")
    if "owner_bindings" in tables:
        print(f"owner_bindings activos={count('owner_bindings', 'WHERE ended_at IS NULL')}")
    if "voice_evidence" in tables:
        rows = con.execute(
            "SELECT kind, outcome, COUNT(*) FROM voice_evidence GROUP BY kind, outcome ORDER BY kind, outcome"
        ).fetchall()
        for kind, outcome, n in rows:
            print(f"voice_evidence[{kind},{outcome}]={n}")
        commits = con.execute("SELECT DISTINCT app_commit FROM voice_evidence").fetchall()
        if commits:
            print("voice_evidence app_commit=" + ",".join(str(c[0]) for c in commits))
    print(f"integridad={con.execute('PRAGMA quick_check').fetchone()[0]}")
    con.close()


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    mode = argv[1]
    if mode == "ui":
        ui(argv[2])
        return 0
    if mode == "find":
        return find(argv[2], argv[3])
    if mode == "has":
        return find(argv[2], argv[3], tap=False)
    if mode == "db":
        db(argv[2])
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
