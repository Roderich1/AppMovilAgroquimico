"""F03-RES-01 (#71) y E2E de D3: lectura de la copia temporal de SQLite y de la UI.

  device_db.py <base> <consulta>   consulta de sólo lectura (ver QUERIES)
  device_db.py --ui                textos y botones de un volcado de uiautomator (stdin)
  device_db.py --find <regex>      centro "x y" del primer elemento que coincide (stdin)

Las operaciones se muestran por sus 8 primeros hex; los identificadores remotos del
titular, por una huella de 12 hex. Nunca se imprimen credenciales.
"""
import hashlib
import pathlib
import re
import sqlite3
import sys
import xml.etree.ElementTree as ET


def sha12(value):
    return "-" if value is None else hashlib.sha256(str(value).encode()).hexdigest()[:12]


def op(value):
    return "-" if value is None else str(value)[:8]


QUERIES = {
    "counts": """SELECT 'filas: personas=' || (SELECT count(*) FROM persons) ||
        ' campañas=' || (SELECT count(*) FROM campaigns) || ' productos=' || (SELECT count(*) FROM products) ||
        ' necesidades=' || (SELECT count(*) FROM declared_needs) ||
        ' versiones=' || (SELECT count(*) FROM declared_need_versions) ||
        ' outbox=' || (SELECT count(*) FROM sync_outbox) || ' user_version=' || (SELECT * FROM pragma_user_version)""",
    "marker": "SELECT 'marcador: ' || name || ' activo=' || active FROM persons WHERE name LIKE 'MARCADOR-%' ORDER BY id",
    "owner": """SELECT o.id, p.name, o.member_id, o.tenant_id, o.owner_role, o.ended_at
        FROM owner_bindings o JOIN persons p ON p.id = o.person_id ORDER BY o.id""",
    "bindings": """SELECT 'campaña', c.name, b.central_name, b.status, b.invalid_reason, b.campaign_ref, NULL
          FROM campaign_bindings b JOIN campaigns c ON c.id = b.campaign_id
        UNION ALL
        SELECT 'producto', p.name, b.central_name, b.status, b.invalid_reason, b.product_ref,
               b.central_unit || '→' || b.base_unit
          FROM product_bindings b JOIN products p ON p.id = b.product_id""",
    "outbox": """SELECT id, operation_id, projection_type, action, predecessor_operation_id, predecessor_kind,
          quantity_base, base_unit, status, attempts, last_code, server_accepted_at,
          ack_reconciliation_reference, resolution_head_operation_id
        FROM sync_outbox ORDER BY id""",
    "needs": """SELECT n.id, c.name, p.name, n.status, n.quantity_base, n.reference_date, n.current_version
        FROM declared_needs n JOIN campaigns c ON c.id = n.campaign_id JOIN products p ON p.id = n.product_id
        ORDER BY n.id""",
    "versions": """SELECT declared_need_id, version, status, quantity_base, reference_date, operation_id
        FROM declared_need_versions ORDER BY declared_need_id, version""",
}


def run_query(path, name):
    # Es una copia temporal: abrirla sin mode=ro deja que SQLite resuelva un journal
    # pendiente. Sólo se ejecutan SELECT.
    db = sqlite3.connect(pathlib.Path(path).resolve().as_uri(), uri=True)
    rows = db.execute(QUERIES[name]).fetchall()
    for row in rows:
        if name == "owner":
            id_, person, member, tenant, role, ended = row
            print(f"titular {id_}: {person} member={sha12(member)} tenant={sha12(tenant)} rol={role} cerrado={ended or '-'}")
        elif name == "bindings":
            kind, local, central, status, reason, ref, unit = row
            extra = f" unidad={unit}" if unit else ""
            print(f"vínculo {kind}: {local} → {central} {status} {reason or ''} ref={op(ref)}{extra}".replace("  ", " "))
        elif name == "outbox":
            (id_, op_id, ptype, action, pred, pkind, qty, unit, status, attempts, code, accepted, ack_ref, head) = row
            print(f"outbox {id_}: op={op(op_id)} {ptype} {action} pred={op(pred)}/{pkind or '-'} cantidad={qty or '-'} {unit}"
                  f" {status} intentos={attempts} código={code or '-'} aceptada={accepted or '-'}"
                  f" disputa={op(ack_ref)} head_resolución={op(head)}")
        elif name == "needs":
            id_, campaign, product, status, qty, date, version = row
            print(f"necesidad {id_}: {campaign} / {product} {status} cantidad={qty if qty is not None else '-'}"
                  f" fecha={date} versión={version}")
        elif name == "versions":
            need, version, status, qty, date, op_id = row
            print(f"versión {need}.{version}: {status} cantidad={qty if qty is not None else '-'} fecha={date} op={op(op_id)}")
        else:
            print(" ".join("-" if v is None else str(v) for v in row))
    if not rows:
        print(f"{name}: sin filas")


def nodes():
    root = ET.fromstring(sys.stdin.read())
    for node in root.iter("node"):
        label = (node.get("text") or "").strip() or (node.get("content-desc") or "").strip()
        if node.get("class") == "android.widget.EditText":
            # Un campo de contraseña nunca muestra su contenido.
            label = "<campo contraseña>" if node.get("password") == "true" else f"<campo> {label}"
        bounds = re.findall(r"\d+", node.get("bounds") or "")
        if not label or len(bounds) != 4:
            continue
        x1, y1, x2, y2 = map(int, bounds)
        yield label, (x1 + x2) // 2, (y1 + y2) // 2, node


def main():
    if sys.argv[1] == "--ui":
        for label, x, y, node in nodes():
            flags = "".join(f for f, attr in (("B", "clickable"), ("F", "focused"), ("C", "checked")) if node.get(attr) == "true")
            print(f"[{x},{y}] {flags:3} {' '.join(label.split())[:110]}")
    elif sys.argv[1] == "--find":
        pattern = re.compile(sys.argv[2])
        for label, x, y, _ in nodes():
            if pattern.search(label):
                print(x, y)
                return
    else:
        run_query(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    main()
