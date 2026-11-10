"""Ayudante de tool/f09_emu/f09emu.sh (F09, emulador). Sólo lectura.

  python -I -X utf8 f09emu.py ui <paquete>            < volcado-uiautomator.xml
  python -I -X utf8 f09emu.py estado <paquete>        < volcado-uiautomator.xml
  python -I -X utf8 f09emu.py find <paquete> <regex>  < volcado-uiautomator.xml
  python -I -X utf8 f09emu.py has <paquete> <regex>   < volcado-uiautomator.xml
  python -I -X utf8 f09emu.py db <copia.db>

Seguridad: los nodos con password="true" no muestran texto ni descripción, y
nunca se eligen para tocar. Sólo se consideran los nodos del paquete indicado
(o del diálogo de permisos del sistema, cuando se pide explícitamente con el
paquete «permisos»). La consulta de la base abre la COPIA en modo de sólo
lectura y no imprime transcripciones ni campos de la evidencia: sólo cuentas.

Pantallas de voz: `estado` imprime SÓLO lo que está en una lista blanca
(estado y configuración del motor, etiquetas fijas de campo, fichas de estado,
valores numéricos, elección de catálogo y botones conocidos); lo demás se
cuenta como omitido. `ui` cambia solo a `estado` si reconoce una pantalla de
voz, de modo que lo reconocido («Lo último que se oyó», «Oído: …», frases del
borrador) no sale nunca por la herramienta. Autoprueba:
`python -I -X utf8 tool/f09_emu/test_f09emu_privacidad.py`.
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
    nodes = list(_nodes(package))
    if is_voice_screen(nodes):
        print("(pantalla de voz: sólo la lista blanca)")
        estado(package, nodes)
        return
    shown = 0
    for node in nodes:
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


# --- Pantallas de voz: lista blanca -----------------------------------------
# Marcas que identifican una pantalla de dictado (compra, plan o aplicación).
VOICE_MARKERS = (
    "Hablar. Abre el micrófono",
    "Terminar. El micrófono",
    "Lo último que se oyó",
    "Reconocedor:",
    # Formulario único (F09): todo formulario con «Completar por voz», su
    # panel o un campo marcado por un dictado se lee con la lista blanca.
    "Completar por voz",
    "Ocultar el panel de voz",
    "Listo para dictar",
    "Grabando",
    "Procesando tu voz",
    "Revisa los campos marcados",
    "Deshacer último dictado",
    "Usar lo dictado",
    "Descartar lo dictado",
)
# Nunca se imprime un elemento que contenga alguna de estas marcas, aunque
# encaje en la lista blanca: son lo oído o lo transcrito.
DENY = ("«", "»", "Oído", "oído", "Lo último que se oyó", "Aplicado al borrador")
# Prefijos de líneas de estado y configuración (sin contenido dictado).
ALLOWED_PREFIXES = (
    "Estado: ",
    "Reconocedor: ",
    "Revisión de cada frase: ",
    "Idioma: ",
    "Funciona sin conexión",
    "Modo avión: ",
    "Total: ",
)
# Etiquetas fijas de la interfaz (texto exacto).
ALLOWED_EXACT = {
    "Hablar", "Terminar", "Micrófono abierto", "Borrador", "Campaña",
    "Moneda", "Proveedor", "Recibe la compra", "Total de la línea", "BOB",
    "USD", "Cancelar", "Registrar compra", "Registrar plan",
    "Registrar aplicación", "Añadir producto", "Añadir otro producto",
    "Quitar este producto", "Usar el formulario manual", "Volver",
    "Sí, pagué todo", "No, todavía no", "¿Ya pagaste al proveedor?",
    "Para registrar falta:", "Hablar. Abre el micrófono.",
    "Terminar. El micrófono está escuchando.",
    "Cancelar este turno (descarta el audio)",
    "No cambió el borrador: no se reconoció nada que completar.",
    "No hay una campaña activa.", "Falta el proveedor.",
    "Elige una opción para poder confirmar.",
    # Formulario único: panel, marcas y formularios (textos fijos).
    "Completar por voz", "Ocultar el panel de voz", "Listo para dictar",
    "Abriendo el micrófono…", "Grabando", "Procesando tu voz",
    "Revisa los campos marcados", "Cancelar dictado",
    "Deshacer último dictado", "Por voz", "Elegir", "Mantener",
    "Usar lo dictado", "Descartar lo dictado", "Abrir ajustes",
    "Dictado cancelado: el formulario no cambió.",
    "No se oyó nada que completar. El formulario no cambió.",
    "No cambió el formulario: no se reconoció nada que completar.",
    "Se deshizo el último dictado.",
    "Termine o cancele el dictado antes de continuar.",
    "Hay 1 campo dictado por revisar.",
    "Nueva compra", "Nueva aplicación", "Nueva planificación", "Continuar",
    "Atrás", "Confirmar compra", "Confirmar aplicación",
    "Guardar planificación", "Agregar producto", "Agregar al plan",
    "Fecha de la compra", "Fecha de la aplicación", "Cantidad comprada",
    "Área planificada (ha)", "Área tratada (ha)", "Dosis por hectárea",
    "Producto por elegir", "Toda para una persona", "Repartir entre varias",
    "Editar", "Quitar", "Descartar cambios", "Seguir editando",
    # Fichas de estado de un campo.
    "Dictado", "Falta", "Confirmado", "Propuesto", "Corregido a mano",
    "Ambiguo: elija", "Revisar", "Sin seleccionar",
}
ALLOWED_PATTERNS = (
    re.compile(r"^Producto \d+$"),
    re.compile(r"^Productos \(\d+\)$"),
    re.compile(r"^Paso \d de \d · [A-Za-zÁÉÍÓÚáéíóúñ ]{3,40}$"),
    re.compile(r"^Hay \d+ campos dictados por revisar\.$"),
    re.compile(r"^Dosis \((L|kg)/ha\)$"),
    re.compile(r"^Precio (BOB|USD)/(L|kg)$"),
    re.compile(r"^Falta: [a-záéíóúñ «»()]{3,40}$"),
    # Resumen de un dictado: sólo cuentas.
    re.compile(
        r"^(\d+ (campo completado|campos completados|línea añadida|"
        r"líneas añadidas|por revisar)(, )?)+\.( Revisa los campos marcados\.)?"
        r"( Se conservó lo que editó mientras se procesaba\.)?$"
    ),
    # Ficha de estado de un campo: «<campo>: <estado>», ambos de listas fijas.
    re.compile(
        r"^(Producto|Cantidad|Moneda|Proveedor|Campaña|Recibe la compra|"
        r"Tipo de cambio|Precio por [^:«»]{1,8}|Total de la línea)"
        r"( \([^:«»]{1,12}\))?: "
        r"(Dictado|Falta|Confirmado|Propuesto|Corregido a mano|Ambiguo: elija|"
        r"Revisar|Por revisar)$"
    ),
    re.compile(r"^Cantidad( \([^«»]{1,12}\))?$"),
    re.compile(r"^Precio por [^«»]{1,12}$"),
    re.compile(r"^Por [^«»]{1,12}$"),
    re.compile(r"^• [^«»]{1,80}\.$"),
    # Selector: «<elemento del catálogo>, <campo>…» (catálogo, no lo dictado).
    re.compile(
        r"^(?P<valor>[^«»\n]{1,60}), "
        r"(?P<campo>Producto|Proveedor|Recibe la compra|Chaco|Persona|"
        r"Agregar producto)\n"
    ),
)
NUMERIC = re.compile(r"^[0-9]+([.,][0-9]+)?$")


def is_voice_screen(nodes):
    return any(
        marker in (n.get("text") or "") + (n.get("content-desc") or "")
        for n in nodes
        for marker in VOICE_MARKERS
    )


def _allowed_value(value):
    """Un texto (una línea o un selector) si está en la lista blanca, o None."""
    if not value or any(d in value for d in DENY):
        return None
    if value in ALLOWED_EXACT or value.startswith(ALLOWED_PREFIXES):
        return value
    for rx in ALLOWED_PATTERNS:
        m = rx.match(value)
        if m:
            if "campo" in m.groupdict():
                return f"{m.group('campo')}: {m.group('valor')}"
            return value
    return None


def allowed_label(node):
    """Lo que se puede imprimir de un nodo de una pantalla de voz, o None.

    Un elemento de varias líneas se evalúa línea a línea: sólo salen las
    líneas permitidas (las demás, incluida cualquier línea con lo oído, no).
    """
    if node.get("password") == "true":
        return None
    for raw in (node.get("text") or "", node.get("content-desc") or ""):
        value = raw.strip()
        if not value:
            continue
        if node.get("class", "").endswith("EditText"):
            if NUMERIC.match(value) and not any(d in value for d in DENY):
                return f"[campo numérico] {value}"
            continue
        whole = _allowed_value(value)
        if whole is not None:
            return whole
        if "\n" in value:
            lines = [_allowed_value(l.strip()) for l in value.split("\n")]
            kept = [l for l in lines if l]
            if kept:
                return " / ".join(kept) + (
                    f"  [{len(lines) - len(kept)} líneas omitidas]"
                    if len(kept) < len(lines) else ""
                )
    return None


def estado(package, nodes=None):
    nodes = list(_nodes(package)) if nodes is None else nodes
    omitted = 0
    for node in nodes:
        label = allowed_label(node)
        has_content = (node.get("text") or "").strip() or (
            node.get("content-desc") or ""
        ).strip()
        if label is None:
            omitted += 1 if has_content else 0
            continue
        flags = []
        if node.get("checked") == "true" or node.get("selected") == "true":
            flags.append("marcado")
        if node.get("enabled") == "false":
            flags.append("deshabilitado")
        print(label + (f"  [{', '.join(flags)}]" if flags else ""))
    print(f"[{omitted} elementos omitidos por la lista blanca]")


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
    if mode == "estado":
        estado(argv[2])
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
