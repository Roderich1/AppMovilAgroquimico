"""Evaluación F10 (protocolo v1.2, DS-B de R6): asocia fotografías sintéticas a compras de
DS-V en una COPIA de la base extraída de `.f10eval`, con la app detenida. Es parte de la
fixture, no un flujo medido.

Pone `invoice_image_path` en las primeras compras DS-V (`DSV-F-%`, por id) que aún no
tienen foto, hasta que haya exactamente <total> compras DS-V con foto. La ruta apunta a
`app_flutter/invoices/<archivo>` del paquete; el respaldo sólo usa el nombre de archivo.
Imprime cuántas filas cambió y el total resultante; nunca borra filas.

    python -I -X utf8 attach_photos.py <base.db> <total> <paquete> <fotos...>
"""

import pathlib
import sqlite3
import sys


def main():
    db_path, total, package, *photos = sys.argv[1:]
    total = int(total)
    if total > len(photos):
        sys.exit(f"faltan fotos: {total} pedidas, {len(photos)} dadas")
    db = sqlite3.connect(pathlib.Path(db_path).resolve().as_uri() + "?mode=rw", uri=True)
    base = f"/data/user/0/{package}/app_flutter/invoices/"
    with_photo = db.execute(
        "SELECT invoice_image_path FROM purchases WHERE invoice_number LIKE 'DSV-F-%' "
        "AND invoice_image_path IS NOT NULL").fetchall()
    used = {pathlib.PurePosixPath(p).name for (p,) in with_photo}
    pending = [pathlib.Path(p).name for p in photos[:total] if pathlib.Path(p).name not in used]
    need = total - len(used)
    if need < 0:
        sys.exit(f"ya hay {len(used)} compras con foto, más que {total}")
    rows = db.execute(
        "SELECT id FROM purchases WHERE invoice_number LIKE 'DSV-F-%' AND invoice_image_path IS NULL "
        "ORDER BY id LIMIT ?", (need,)).fetchall()
    for (purchase_id,), name in zip(rows, pending):
        db.execute("UPDATE purchases SET invoice_image_path = ? WHERE id = ?", (base + name, purchase_id))
    db.commit()
    now = db.execute("SELECT count(*) FROM purchases WHERE invoice_number LIKE 'DSV-F-%' "
                     "AND invoice_image_path IS NOT NULL").fetchone()[0]
    check = db.execute("PRAGMA integrity_check").fetchone()[0]
    db.close()
    print(f"asociadas ahora: {len(rows)}; compras DS-V con foto: {now}; integridad: {check}")
    if now != total or check != "ok":
        sys.exit(1)


if __name__ == "__main__":
    main()
