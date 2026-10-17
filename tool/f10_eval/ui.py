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
    out = adb("shell", "dumpsys", "input_method", capture=True).decode("utf-8", "replace")
    return "mInputShown=true" in out


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
    header, nodes = wait_for(rf"^{line_no} (Seleccione producto|DSV-)")
    if header["y"] > 1900:  # la línea quedó bajo el borde: se desplaza
        adb("shell", "input", "swipe", "540", "1900", "540", "700", "350")
        time.sleep(0.8)
        header, nodes = wait_for(rf"^{line_no} (Seleccione producto|DSV-)")
    selector = next(n for n in nodes if n["y"] > header["y"] and "Producto Producto" in label(n))
    tap(selector["x"], selector["y"], 1.2)
    option, _ = wait_for(rf"^{re.escape(product)} Producto sintético")
    tap(option["x"], option["y"], 1.2)
    for value, which in ((qty, "cantidad"), (price, "precio"), (qty, "asignación")):
        hide_keyboard()
        nodes = dump()
        header = find(nodes, rf"^{line_no} DSV-")
        fields = [n for n in edits(nodes) if n["y"] > header["y"]]
        if which == "asignación":
            fields = [n for n in fields if n["x1"] > 600]
        else:
            fields = [n for n in fields if n["x1"] < 200]
            fields = fields[0:1] if which == "cantidad" else fields[1:2]
        if not fields or fields[0]["y"] > 2150:
            adb("shell", "input", "swipe", "540", "1800", "540", "1000", "350")
            time.sleep(0.8)
            nodes = dump()
            header = find(nodes, rf"^{line_no} DSV-")
            fields = [n for n in edits(nodes) if n["y"] > header["y"]]
            fields = [n for n in fields if (n["x1"] > 600) == (which == "asignación")]
            if which != "asignación":
                fields = fields[0:1] if which == "cantidad" else fields[1:2]
        target = fields[0]
        tap(target["x"], target["y"], 0.8)
        type_text(value)
    hide_keyboard()
    nodes = dump()
    header = find(nodes, rf"^{line_no} DSV-")
    if "Asignado" not in label(header):
        raise RuntimeError(f"línea {line_no} sin asignar: {label(header)}")


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
    confirm = find(nodes, r"^Confirmar$")
    if not confirm:
        raise RuntimeError("no se ve «Confirmar»")
    print(f"listo: {label(total) if total else 'total no visible'}; confirmar en {confirm['x']},{confirm['y']}")


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
    elif cmd == "purchase-form":
        purchase_form(*sys.argv[2:9])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
