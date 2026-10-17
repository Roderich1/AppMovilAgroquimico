"""Lectura de la base SQLite de una copia AISLADA por run-as (sólo lectura).

    python -I -X utf8 devdb.py <paquete> settings|dump|sql "<SELECT ...>"

`dump` imprime el SHA-256 de un volcado completo de cada tabla (filas enteras,
ordenadas por rowid) y uno global, sin valores. Copia base, -wal y -shm a una
carpeta temporal, abre la copia y la borra al terminar.
"""
import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile

DB = 'agroquimicos_v2.db'


def pull(package, folder):
    for suffix in ('', '-wal', '-shm'):
        out = subprocess.run(
            ['adb', 'exec-out', 'run-as', package, 'cat', f'databases/{DB}{suffix}'],
            capture_output=True,
        )
        if out.returncode == 0 and out.stdout and b'No such file' not in out.stdout[:200]:
            with open(os.path.join(folder, DB + suffix), 'wb') as f:
                f.write(out.stdout)
    return os.path.join(folder, DB)


def main():
    package, cmd = sys.argv[1], sys.argv[2]
    folder = tempfile.mkdtemp(prefix='agro_devdb_')
    try:
        path = pull(package, folder)
        con = sqlite3.connect(path)
        if cmd == 'settings':
            for k, v in con.execute('SELECT key, value FROM app_settings ORDER BY key'):
                print(f'{k}={v}')
            print('user_version=' + str(con.execute('PRAGMA user_version').fetchone()[0]))
        elif cmd == 'dump':
            total = hashlib.sha256()
            tables = [r[0] for r in con.execute(
                "SELECT name FROM sqlite_master WHERE type='table' "
                "AND name NOT LIKE 'sqlite_%' ORDER BY name")]
            for t in tables:
                rows = con.execute(f'SELECT * FROM "{t}" ORDER BY rowid').fetchall()
                h = hashlib.sha256(json.dumps(rows, default=str).encode()).hexdigest()
                total.update(f'{t}:{h}'.encode())
                print(f'{t}\t{len(rows)}\t{h[:12]}')
            print('TOTAL\t' + total.hexdigest())
        elif cmd == 'sql':
            for row in con.execute(sys.argv[3]):
                print(row)
        con.close()
    finally:
        shutil.rmtree(folder, ignore_errors=True)


main()
