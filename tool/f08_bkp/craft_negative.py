"""F10: contenedores negativos para el turno del POCO a partir de una copia legítima.

Uso (con Python 3 del sistema, sin dependencias):
    python -I -X utf8 craft_negative.py <origen.agrobackup> <carpeta_salida>

Lee una copia `.agrobackup` exportada por la propia app (datos sintéticos) y
escribe en <carpeta_salida>, con el prefijo que la app lista:

- `agroquimicos_backup_F10-alterada.agrobackup`: un byte de `database.db`
  cambiado y el manifiesto intacto. Esperado: rechazo por SHA-256 **antes** de
  confirmar.
- `agroquimicos_backup_F10-ajena.agrobackup`: el vínculo activo apunta a otro
  Member y el manifiesto se recalcula (una copia ajena coherente). Esperado:
  rechazo por titular antes de sustituir.
- `agroquimicos_backup_F10-fallo_tras_sustituir.agrobackup`: base sin la
  tabla `sync_outbox` y manifiesto recalculado. Pasa la validación y el titular,
  y falla al pausar la outbox **con la base y las fotos ya sustituidas**.
  Esperado: error y rollback completo, con la transacción reciente.
- `agroquimicos_backup_F10-bomba.agrobackup`: unos 300 KB que se expanden a
  300 MiB y declaran 1000 bytes. Esperado: rechazo por límites al validar.

No imprime contenido de la base. Los archivos generados contienen los datos
sintéticos de la copia de origen: se borran al terminar el turno.
"""
import hashlib
import json
import os
import shutil
import sqlite3
import struct
import sys
import tempfile
import zipfile
import zlib

PREFIX = "agroquimicos_backup_F10-"
OTHER_MEMBER = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"


def read_container(path):
    with zipfile.ZipFile(path) as z:
        return {name: z.read(name) for name in z.namelist() if not name.endswith("/")}


def write_container(path, entries):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in entries.items():
            z.writestr(name, data)


def with_database(entries, database):
    manifest = json.loads(entries["manifest.json"].decode("utf-8"))
    manifest["database"] = {
        "name": "database.db",
        "bytes": len(database),
        "sha256": hashlib.sha256(database).hexdigest(),
    }
    out = dict(entries)
    out["database.db"] = database
    out["manifest.json"] = json.dumps(manifest, indent=2).encode("utf-8")
    return out


def modified_database(database, statements):
    workdir = tempfile.mkdtemp(prefix="agro_f10_craft_")
    try:
        path = os.path.join(workdir, "database.db")
        with open(path, "wb") as f:
            f.write(database)
        con = sqlite3.connect(path)
        try:
            con.execute("PRAGMA foreign_keys = OFF")
            # Los disparadores protegen el historial del titular; se retiran
            # sólo durante el cambio y se vuelven a crear tal cual.
            triggers = con.execute(
                "SELECT name, sql FROM sqlite_master WHERE type='trigger' AND tbl_name='owner_bindings'"
            ).fetchall()
            for name, _ in triggers:
                con.execute(f'DROP TRIGGER "{name}"')
            for sql in statements:
                con.execute(sql)
            for _, sql in triggers:
                con.execute(sql)
            con.commit()
            assert con.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        finally:
            con.close()
        with open(path, "rb") as f:
            return f.read()
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def write_bomb(path, manifest):
    """ZIP escrito a mano: la cabecera declara 1000 bytes y se expande a 300 MiB."""
    comp = zlib.compressobj(9, zlib.DEFLATED, -15)
    chunk = bytes(1024 * 1024)
    bomb = b"".join(comp.compress(chunk) for _ in range(300)) + comp.flush()
    entries = [
        ("manifest.json", zlib.compress(manifest, 9)[2:-4], zlib.crc32(manifest), len(manifest)),
        ("database.db", bomb, 0, 1000),
    ]
    out, central = bytearray(), bytearray()
    for name, data, crc, size in entries:
        raw = name.encode("utf-8")
        offset = len(out)
        out += struct.pack("<IHHHHHIIIHH", 0x04034B50, 20, 0x0800, 8, 0, 0x5821, crc, len(data), size, len(raw), 0)
        out += raw + data
        central += struct.pack("<IHHHHHHIIIHHHHHII", 0x02014B50, 20, 20, 0x0800, 8, 0, 0x5821,
                               crc, len(data), size, len(raw), 0, 0, 0, 0, 0, offset)
        central += raw
    start = len(out)
    out += central
    out += struct.pack("<IHHHHIIH", 0x06054B50, 0, 0, len(entries), len(entries), len(central), start, 0)
    with open(path, "wb") as f:
        f.write(out)


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    source, target = sys.argv[1], sys.argv[2]
    os.makedirs(target, exist_ok=True)
    entries = read_container(source)
    database = entries["database.db"]

    altered = bytearray(database)
    altered[len(altered) // 2] ^= 0xFF
    variants = {
        "alterada": dict(entries, **{"database.db": bytes(altered)}),
        "ajena": with_database(entries, modified_database(database, [
            f"UPDATE owner_bindings SET member_id = '{OTHER_MEMBER}' WHERE ended_at IS NULL",
        ])),
        "fallo_tras_sustituir": with_database(entries, modified_database(database, [
            "DROP TABLE sync_outbox",
        ])),
    }
    for name, content in variants.items():
        path = os.path.join(target, f"{PREFIX}{name}.agrobackup")
        write_container(path, content)
        print(f"{os.path.basename(path)}  {os.path.getsize(path)} bytes")
    bomb = os.path.join(target, f"{PREFIX}bomba.agrobackup")
    write_bomb(bomb, entries["manifest.json"])
    print(f"{os.path.basename(bomb)}  {os.path.getsize(bomb)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
