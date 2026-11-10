"""Autoprueba de privacidad de f09emu.py con un volcado SINTÉTICO.

    python -I -X utf8 tool/f09_emu/test_f09emu_privacidad.py

Comprueba que, en una pantalla de voz, ni `estado` ni `ui` imprimen lo oído o
lo transcrito (aunque no vaya entre comillas) y que sí imprimen los campos y
métricas de la lista blanca. Las frases son de guion; no hay audio.
"""

import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
PKG = "com.comunidad.agro.agroquimicos.f09c"

# Contenido que NUNCA debe salir (sintético, pero con la forma de lo real).
SECRETOS = [
    "Lo último que se oyó",
    "compre dos litros de erbisida demo a cincuenta",  # transcripción sin comillas
    "frase sintetica entre comillas",
    "erbisida demo",  # lo oído (distinto del catálogo) en «Oído: …»
    "Aplicado al borrador",
    "texto libre escrito",  # campo de texto no numérico
    "clave-sintetica",  # campo de contraseña
    "cincuenta bolivianos",
    "sin comillas",
]
# Lo que SÍ debe salir.
ESPERADO = [
    "Estado: Texto listo para revisar",
    "Reconocedor: modelo de voz de la aplicación (whisper-small-q5_1)",
    "Producto: Herbicida DEMO",
    "Producto 1",
    "Cantidad (L)",
    "[campo numérico] 2",
    "Precio por L",
    "Confirmado",
    "BOB  [marcado]",
    "• Falta el proveedor.",
    "Cancelar este turno (descarta el audio)",
    "Precio por L / Ambiguo: elija  [2 líneas omitidas]",
    "Cantidad (L): Dictado",
]


def node(text="", desc="", cls="android.view.View", **extra):
    attrs = {
        "text": text,
        "content-desc": desc,
        "class": cls,
        "package": PKG,
        "bounds": "[0,0][100,100]",
        "checked": "false",
        "selected": "false",
        "enabled": "true",
        "password": "false",
    }
    attrs.update(extra)
    esc = lambda v: (v.replace("&", "&amp;").replace('"', "&quot;")
                     .replace("<", "&lt;").replace("\n", "&#10;"))
    return "<node " + " ".join(f'{k}="{esc(v)}"' for k, v in attrs.items()) + " />"


NODES = [
    node(desc="Hablar. Abre el micrófono."),
    node(desc="Estado: Texto listo para revisar"),
    node(desc="Reconocedor: modelo de voz de la aplicación (whisper-small-q5_1)"),
    node(desc="Lo último que se oyó"),
    node(desc="«Compré dos litros de frase sintetica entre comillas.»"),
    node(desc="compre dos litros de erbisida demo a cincuenta"),
    node(desc="Aplicado al borrador:"),
    node(desc="Producto 1"),
    node(desc="Oído: «erbisida demo»"),
    node(desc="Herbicida DEMO, Producto\nProducto\nHerbicida DEMO"),
    node(desc="Cantidad (L)"),
    node(desc="Cantidad (L): Dictado"),
    node(desc="Producto: erbisida demo"),
    node(text="2", cls="android.widget.EditText"),
    node(desc="Precio por L"),
    node(desc="Confirmado"),
    node(text="texto libre escrito", cls="android.widget.EditText"),
    node(text="clave-sintetica", cls="android.widget.EditText", password="true"),
    node(desc="BOB", checked="true"),
    node(desc="• Falta el proveedor."),
    node(desc="• Línea 1: precio ambiguo («cincuenta bolivianos»), elija una opción."),
    node(desc="Cancelar este turno (descarta el audio)"),
    # Elemento de varias líneas (teléfono en vertical): etiqueta, lo oído sin
    # comillas, lo oído con comillas y la ficha de estado.
    node(desc="Precio por L\ncincuenta bolivianos el litro sin comillas\nOído: «erbisida demo»\nAmbiguo: elija"),
]
XML = "<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation=\"0\">" + "".join(NODES) + "</hierarchy>"


def run(mode):
    out = subprocess.run(
        [sys.executable, "-I", "-X", "utf8", str(HERE / "f09emu.py"), mode, PKG],
        input=XML, capture_output=True, text=True, encoding="utf-8", check=True,
    ).stdout
    return out


def main():
    fallos = 0
    for mode in ("estado", "ui"):
        out = run(mode)
        for s in SECRETOS:
            if s.lower() in out.lower():
                print(f"FALLO [{mode}]: salió «{s}»")
                fallos += 1
        for e in ESPERADO:
            if e not in out:
                print(f"FALLO [{mode}]: no salió «{e}»")
                fallos += 1
        if "elementos omitidos por la lista blanca" not in out:
            print(f"FALLO [{mode}]: falta el recuento de omitidos")
            fallos += 1
    print("autoprueba de privacidad:", "correcta" if fallos == 0 else f"{fallos} fallos")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
