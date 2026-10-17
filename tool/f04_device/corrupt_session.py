"""P13: deja ilegible SÓLO el slot a de la sesión cifrada de una copia aislada.

Lee el XML de SharedPreferences por stdin y escribe en argv[1] el mismo XML
con el texto cifrado del slot a sustituido por base64 aleatorio de la misma
longitud. Nunca imprime ni guarda el valor original. Imprime sólo longitudes.
"""
import base64
import os
import re
import sys

xml = sys.stdin.read()
pattern = re.compile(r'(_session_a">)([^<]*)(<)')
matches = pattern.findall(xml)
assert len(matches) == 1, f'slots a encontrados: {len(matches)}'
old = matches[0][1]
new = base64.b64encode(os.urandom(len(old))).decode()[: len(old)]
assert new != old
out = pattern.sub(lambda m: m.group(1) + new + m.group(3), xml, count=1)
with open(sys.argv[1], 'w', encoding='utf-8', newline='') as f:
    f.write(out)
print(f'slot a sustituido: longitud {len(old)} -> {len(new)}; resto del XML sin cambios')
