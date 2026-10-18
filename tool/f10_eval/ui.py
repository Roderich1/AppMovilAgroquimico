"""Evaluación F10 (protocolo v1.0 §1.6-§1.7): navegación de la copia aislada por adb.

Prepara cada repetición (rellenar formularios, abrir pantallas) leyendo la jerarquía
de `uiautomator` en vez de usar coordenadas fijas: el formulario de compra se
desplaza al abrirse el teclado y una coordenada fija acaba en otro campo. La
preparación NO se mide; el tiempo sale sólo del vídeo (`frames.py`).

Sólo actúa sobre la app en primer plano del dispositivo de ANDROID_SERIAL; no
lanza ni toca otros paquetes. No escribe secretos.

    python -I -X utf8 ui.py dump
    python -I -X utf8 ui.py purchase-form <proveedor> <prod1> <cant1> <precio1> <prod2> <cant2> <precio2>
    python -I -X utf8 ui.py find <regex>
"""

import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")


def adb(*args, capture=False):
    cmd = ["adb", *args]
    if capture:
        return subprocess.run(cmd, check=True, capture_output=True).stdout
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


_SCREEN = None


def screen():
    """(ancho, alto) en píxeles de la pantalla del dispositivo (`wm size`). Las coordenadas
    de desplazamiento y los umbrales de «quedó bajo el borde» se expresan como fracción de
    la pantalla, de modo que la misma herramienta sirve para el POCO (1080×2400, serie 1) y
    para el HONOR (720×1612, serie 2) sin coordenadas fijas."""
    global _SCREEN
    if _SCREEN is None:
        out = adb("shell", "wm", "size", capture=True).decode("utf-8", "replace")
        m = re.search(r"Physical size: (\d+)x(\d+)", out)
        _SCREEN = (int(m.group(1)), int(m.group(2))) if m else (1080, 2400)
    return _SCREEN


def sx(frac):
    return int(screen()[0] * frac)


def sy(frac):
    return int(screen()[1] * frac)


def scroll_down(start=0.66, end=0.40):
    """Desplaza la pantalla hacia abajo (dedo de `start` a `end`, fracciones del alto), sin
    entrar en la franja de gestos del borde inferior. Lento (700 ms) para que no haya inercia:
    en el HONOR un gesto rápido de media pantalla manda la línea siguiente fuera por arriba."""
    adb("shell", "input", "swipe", str(sx(0.5)), str(sy(start)), str(sx(0.5)), str(sy(end)), "700")
    time.sleep(0.9)


def dump():
    for _ in range(3):
        raw = adb("exec-out", "uiautomator", "dump", "/dev/tty", capture=True)
        text = raw.decode("utf-8", "replace")
        start, end = text.find("<hierarchy"), text.rfind("</hierarchy>")
        if start != -1 and end != -1:
            root = ET.fromstring(text[start: end + len("</hierarchy>")])
            nodes = []
            for n in root.iter("node"):
                m = BOUNDS.match(n.get("bounds", ""))
                if not m:
                    continue
                x1, y1, x2, y2 = map(int, m.groups())
                nodes.append({
                    "text": n.get("text", ""), "desc": n.get("content-desc", ""),
                    "cls": n.get("class", ""), "focused": n.get("focused") == "true",
                    "x": (x1 + x2) // 2, "y": (y1 + y2) // 2, "x1": x1, "y1": y1, "x2": x2, "y2": y2,
                })
            return nodes
        time.sleep(0.5)
    raise RuntimeError("uiautomator no devolvió una jerarquía")


def label(n):
    return re.sub(r"\s+", " ", n["text"] + " " + n["desc"]).strip()


def find(nodes, pattern, nth=0):
    rx = re.compile(pattern)
    hits = [n for n in nodes if rx.search(label(n))]
    return hits[nth] if len(hits) > nth else None


def tap(x, y, wait=1.0):
    adb("shell", "input", "tap", str(x), str(y))
    time.sleep(wait)


def keyboard_shown():
    """True sólo si el teclado está realmente en pantalla. En el HONOR (Android 16)
    `mInputShown` puede seguir en true un instante después de cerrarse el teclado; un BACK
    enviado entonces cierra la pantalla, no el teclado (serie 2). Se exige además la ventana
    del IME visible."""
    out = adb("shell", "dumpsys", "input_method", capture=True).decode("utf-8", "replace")
    return "mInputShown=true" in out and "mWindowVisible=true" in out


def hide_keyboard():
    if keyboard_shown():
        adb("shell", "input", "keyevent", "KEYCODE_BACK")
        time.sleep(0.8)


def type_text(value):
    adb("shell", "input", "text", value)
    time.sleep(0.4)


def edits(nodes):
    return sorted((n for n in nodes if n["cls"] == "android.widget.EditText"), key=lambda n: (n["y"], n["x"]))


def wait_for(pattern, timeout=8.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        nodes = dump()
        hit = find(nodes, pattern)
        if hit:
            return hit, nodes
        time.sleep(0.4)
    raise RuntimeError(f"no apareció: {pattern}")


def choose(field_pattern, option_pattern):
    field, _ = wait_for(field_pattern)
    tap(field["x"], field["y"], 1.2)
    option, _ = wait_for(option_pattern)
    tap(option["x"], option["y"], 1.2)


def fill_line(line_no, product, qty, price):
    """Rellena la línea `line_no` (1, 2…) ya agregada: producto, cantidad, precio y asignación."""
    hide_keyboard()
    header = None
    for _ in range(3):  # la línea puede quedar bajo el borde (pantallas cortas): se desplaza
        try:
            header, nodes = wait_for(rf"^{line_no} (Seleccione producto|DSV-)", 3)
        except RuntimeError:
            header = None
        if header is not None and header["y"] <= sy(0.79):
            break
        scroll_down()
    if header is None:
        raise RuntimeError(f"no se ve la línea {line_no}")
    selector = next(n for n in nodes if n["y"] > header["y"] and "Producto Producto" in label(n))
    tap(selector["x"], selector["y"], 1.2)
    option, _ = wait_for(rf"^{re.escape(product)} Producto sintético")
    tap(option["x"], option["y"], 1.2)
    def line_edits():
        """Campos de la línea: los EditText bajo su cabecera y antes de la siguiente línea."""
        nodes = dump()
        header = find(nodes, rf"^{line_no} DSV-")
        if header is None or header["y"] > sy(0.79):
            scroll_down()
            nodes = dump()
            header = find(nodes, rf"^{line_no} DSV-")
        if header is None:
            raise RuntimeError(f"no se ve la cabecera de la línea {line_no}")
        nxt = find(nodes, rf"^{line_no + 1} (Seleccione producto|DSV-)")
        top, bottom = header["y"], (nxt["y"] if nxt else 10 ** 6)
        fields = [n for n in edits(nodes) if top < n["y"] < bottom]
        own = find(nodes, r"^Para el titular") is not None
        return header, fields, own

    # Dos disposiciones: lado a lado (serie 1, POCO: cantidad y precio a la izquierda,
    # asignación a la derecha) o apilada (serie 2, HONOR 720 px: cantidad, moneda, precio;
    # en modalidad propia no hay campo de asignación: «Para el titular»).
    header, fields, own = line_edits()
    stacked = fields and all(n["x1"] < sx(0.3) for n in fields)
    plan = [(qty, 0), (price, 1)]
    if not own and (not stacked or len(fields) >= 3):
        plan.append((qty, 2))
    for value, idx in plan:
        hide_keyboard()
        header, fields, own = line_edits()
        if stacked:
            fields = sorted(fields, key=lambda n: n["y"])
        else:
            left = sorted((n for n in fields if n["x1"] < sx(0.19)), key=lambda n: n["y"])
            right = sorted((n for n in fields if n["x1"] > sx(0.55)), key=lambda n: n["y"])
            fields = left[0:2] + right[0:1]
        if len(fields) <= idx or fields[idx]["y"] > sy(0.875):
            scroll_down()
            header, fields, own = line_edits()
            if stacked:
                fields = sorted(fields, key=lambda n: n["y"])
            else:
                left = sorted((n for n in fields if n["x1"] < sx(0.19)), key=lambda n: n["y"])
                right = sorted((n for n in fields if n["x1"] > sx(0.55)), key=lambda n: n["y"])
                fields = left[0:2] + right[0:1]
        target = fields[idx]
        tap(target["x"], target["y"], 0.8)
        type_text(value)
    hide_keyboard()
    header, fields, own = line_edits()
    if "Pendiente" in label(header) or (not own and "Asignado" not in label(header)):
        raise RuntimeError(f"línea {line_no} incompleta: {label(header)}")


def purchase_form(supplier, p1, q1, c1, p2, q2, c2):
    """Desde la lista de Compras: abre «Nueva compra» y deja la compra de 2 líneas lista,
    sin confirmar y con el teclado cerrado."""
    button, _ = wait_for(r"^Nueva compra$")
    tap(button["x"], button["y"], 2.0)
    choose(r"Proveedor Proveedor", rf"^{re.escape(supplier)}$")
    fill_line(1, p1, q1, c1)
    add, _ = wait_for(r"^Agregar producto$")
    tap(add["x"], add["y"], 1.2)
    fill_line(2, p2, q2, c2)
    hide_keyboard()
    nodes = dump()
    total = find(nodes, r"TOTAL COMPRA 2 productos")
    confirm = find(nodes, r"^Confirmar( compra)?$")  # «Confirmar compra» desde MOB #103 (barra inferior)
    if not confirm:
        raise RuntimeError("no se ve «Confirmar»")
    print(f"listo: {label(total) if total else 'total no visible'}; confirmar en {confirm['x']},{confirm['y']}")


def open_sync():
    """Desde Inicio (o cualquier pantalla con el acceso), abre Sincronización."""
    hit, _ = wait_for(r"^Sincronización con el sindicato$|^Sincronizar ahora$", 10)
    if "Sincronizar ahora" not in label(hit):
        tap(hit["x"], hit["y"], 2.5)
        wait_for(r"^Sincronizar ahora$", 8)
    print("sincronización abierta")


def need(quantity):
    """Declara (o cambia) la necesidad de DSV-001 en la campaña DSV con `quantity` L.
    Parte de Sincronización o de Necesidades; deja la lista de Necesidades a la vista."""
    hit, _ = wait_for(r"^Necesidades declaradas$|^Necesidad declarada$", 8)
    if label(hit) == "Necesidades declaradas":
        tap(hit["x"], hit["y"], 2.5)
        wait_for(r"^Necesidad declarada$", 8)
    nodes = dump()
    options = find(nodes, r"^Opciones de la necesidad$")
    if options:
        tap(options["x"], options["y"], 1.2)
        item, _ = wait_for(r"^(Cambiar cantidad…|Declarar de nuevo…)$")
        tap(item["x"], item["y"], 1.5)
        wait_for(r"^Nueva cantidad total$")
        field = edits(dump())[0]
        tap(field["x"], field["y"], 0.6)
        adb("shell", "input", "keyevent", "KEYCODE_MOVE_END")
        for _ in range(12):
            adb("shell", "input", "keyevent", "KEYCODE_DEL")
    else:
        button = find(nodes, r"^Declarar$")
        tap(button["x"], button["y"], 2.0)
        product, _ = wait_for(r"^Producto")
        tap(product["x"], product["y"], 1.5)
        option, _ = wait_for(r"^DSV-001 Producto sintético$")
        tap(option["x"], option["y"], 1.2)
        field = edits(dump())[0]
        tap(field["x"], field["y"], 0.6)
    type_text(str(quantity))
    hide_keyboard()
    go, _ = wait_for(r"^Continuar$")
    tap(go["x"], go["y"], 1.5)
    confirm, _ = wait_for(r"^Declarar$")
    tap(confirm["x"], confirm["y"], 2.5)
    # La necesidad va a la campaña que contiene hoy (serie 2: «Campaña DSV S2»); se acepta cualquier nombre.
    row, _ = wait_for(rf"DSV-001 Producto sintético · Campaña [^·]* {quantity} L", 8)
    print("necesidad: " + label(row))


def application(lines):
    """Desde la lista de Aplicaciones: «Registrar», agrega los productos [(código, cantidad)…]
    y toca «Confirmar aplicación». Devuelve el texto visible justo después (p. ej. el aviso
    de rechazo), sin esperar a que desaparezca."""
    button, _ = wait_for(r"^Registrar$")
    tap(button["x"], button["y"], 2.5)
    wait_for(r"^Nueva aplicación$")
    for code, qty in lines:
        hide_keyboard()
        selector, _ = wait_for(r"Elegir producto Elegir producto")
        tap(selector["x"], selector["y"], 1.5)
        option, _ = wait_for(rf"^{re.escape(code)} Producto sintético .*FIFO")
        tap(option["x"], option["y"], 1.5)
        hide_keyboard()
        nodes = dump()
        header = find(nodes, rf"^{re.escape(code)} Producto sintético [0-9.,]+ (L|kg) real")
        fields = [n for n in edits(nodes) if header and n["y"] > header["y"]]
        if len(fields) < 2 or fields[1]["y"] > sy(0.875):
            scroll_down()
            nodes = dump()
            header = find(nodes, rf"^{re.escape(code)} Producto sintético [0-9.,]+ (L|kg) real")
            fields = [n for n in edits(nodes) if n["y"] > header["y"]]
        target = fields[1]  # [Dosis, Cantidad real, …]
        tap(target["x"], target["y"], 0.8)
        type_text(str(qty))
    hide_keyboard()
    confirm, _ = wait_for(r"^Confirmar aplicación$")
    adb("shell", "input", "tap", str(confirm["x"]), str(confirm["y"]))
    time.sleep(0.6)
    seen = [label(n) for n in dump() if label(n)]
    print(" | ".join(t for t in seen if re.search(r"Revise|stock|guardad|registrad|confirmad", t, re.I)) or "(sin aviso visible)")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "dump"
    if cmd == "dump":
        for n in dump():
            if label(n) or n["cls"] == "android.widget.EditText":
                f = "F" if n["focused"] else " "
                print(f"[{n['x']},{n['y']}] {f} {n['cls'].split('.')[-1]:10s} {label(n)[:110]}")
    elif cmd == "find":
        n = find(dump(), sys.argv[2])
        print(f"{n['x']} {n['y']}" if n else "")
    elif cmd == "open-sync":
        open_sync()
    elif cmd == "need":
        need(int(sys.argv[2]))
    elif cmd == "application":
        args = sys.argv[2:]
        application([(args[i], args[i + 1]) for i in range(0, len(args), 2)])
    elif cmd == "purchase-form":
        purchase_form(*sys.argv[2:9])
    elif cmd == "tab":
        # Toca una pestaña inferior por su nombre («Inventario», «Inicio»…), sin coordenadas fijas.
        n, _ = wait_for(rf"^{sys.argv[2]} Tab \d of \d$")
        tap(n["x"], n["y"], 2.0)
    elif cmd == "screen":
        print("%d %d" % screen())
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
