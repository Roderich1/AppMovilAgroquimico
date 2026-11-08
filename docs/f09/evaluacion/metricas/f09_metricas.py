"""Métricas de la evaluación de la voz (MOB #12, #167) a partir de registros por toma.

Uso (sin dependencias, sólo la biblioteca estándar):

    python -I -B f09_metricas.py REGISTRO.csv [--json SALIDA.json]

Calcula, **por teléfono y condición, sin promediar entre ellos** (D5 de
https://github.com/Roderich1/AppMovilAgroquimico/issues/12#issuecomment-6547952377):

- D1, campos correctos por tipo (producto, cantidad, unidad, parcela o persona),
  con numerador y denominador, y los campos añadidos indebidamente aparte;
- D2, transcripciones útiles, con todos los dictados con voz como denominador;
- primer parcial (p50, p95), final de la segunda pasada (p50, p95, frases de
  hasta 20 s) y factor de tiempo real p95 (frases de hasta 60 s);
- rechazo: texto aceptado en silencio o ruido sin voz (fuera de los
  denominadores de D1 y D2);
- escrituras sin confirmación;
- cantidad y unidad frente a Android, sólo con los mismos audios (D6).

Reglas que no cambia este script:

- Los umbrales son los de c-12, copiados en ``UMBRALES``. No se ajustan aquí.
- Un valor ausente es NOT_MEASURED; una condición sin tomas es NOT_RUN. Nunca
  se convierten en cero ni en CUMPLE.
- Los porcentajes se comparan con enteros (``num * 100 >= umbral * den``).
- Percentil por **rango más cercano** (sin interpolar). El método no está
  fijado en c-12: es una elección declarada, pendiente de confirmar.
- Las memorias, la estabilidad en 30 sesiones, el registro térmico y de batería
  y el modo avión desde una instalación limpia son datos de sesión, no de toma:
  este script no los calcula y los informa como fuera de su alcance.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import math
import sys
from dataclasses import dataclass, field

NOT_MEASURED = "NOT_MEASURED"
NOT_RUN = "NOT_RUN"
CUMPLE = "CUMPLE"
NO_CUMPLE = "NO CUMPLE"
NO_DEMOSTRADO = "NO DEMOSTRADO"

TIPOS_CAMPO = ("producto", "cantidad", "unidad", "parcela_o_persona")
CONDICIONES_VOZ = ("tranquilo", "ruido")
CONDICIONES_RECHAZO = ("silencio_sin_voz", "ruido_sin_voz")
CONDICION_SIN_CONFIRMACION = "sin_confirmacion"
ESCENARIOS_SIN_CONFIRMACION = (
    "cancelar",
    "no_hablar",
    "microfono_denegado",
    "resultado_tardio",
)
VALORES_CAMPO = ("correcto", "incorrecto", "falta", "no_esperado", NOT_MEASURED)

# Copia de la tabla «Umbrales fijados antes de medir» de c-12 (2026-10-31).
UMBRALES = {
    "campos_correctos_pct": {"tranquilo": 90, "ruido": 80},
    "transcripciones_utiles_pct": {"tranquilo": 80, "ruido": 70},
    "primer_parcial_ms": {"p50": 800, "p95": 1500},
    "final_segunda_pasada_ms": {"p50": 2500, "p95": 5000, "frase_max_ms": 20000},
    "rtf_segunda_pasada": {"p95": 0.50, "frase_max_ms": 60000},
    "rechazo_textos_aceptados": 0,
    "escrituras_sin_confirmacion": 0,
}

COLUMNAS_OBLIGATORIAS = (
    "toma_id",
    "telefono",
    "condicion",
    "motor",
    "ficha_id",
    "estado_motor",
)


class RegistroInvalido(ValueError):
    pass


def leer_registro(texto: str) -> list[dict[str, str]]:
    """Lee el CSV. Las líneas que empiezan por ``#`` son comentarios."""
    lineas = [l for l in texto.splitlines() if not l.lstrip().startswith("#")]
    filas = list(csv.DictReader(io.StringIO("\n".join(lineas))))
    if not filas:
        return []
    faltan = [c for c in COLUMNAS_OBLIGATORIAS if c not in filas[0]]
    if faltan:
        raise RegistroInvalido(f"faltan columnas: {', '.join(faltan)}")
    for fila in filas:
        for tipo in TIPOS_CAMPO:
            valor = (fila.get(f"campo_{tipo}") or "").strip()
            if valor and valor not in VALORES_CAMPO:
                raise RegistroInvalido(
                    f"toma {fila['toma_id']}: campo_{tipo}={valor!r} no es uno de {VALORES_CAMPO}"
                )
    return filas


def _entero(valor: str | None) -> int | None:
    valor = (valor or "").strip()
    if not valor or valor.upper() in (NOT_MEASURED, NOT_RUN):
        return None
    return int(valor)


def percentil(valores: list[int | float], p: int) -> int | float | None:
    """Percentil por rango más cercano; ``None`` si no hay valores."""
    if not valores:
        return None
    ordenados = sorted(valores)
    rango = max(1, math.ceil(p / 100 * len(ordenados)))
    return ordenados[rango - 1]


def _pct(num: int, den: int) -> str:
    return NOT_MEASURED if den == 0 else f"{num * 100 / den:.1f}"


def _veredicto_pct(num: int, den: int, umbral: int) -> str:
    if den == 0:
        return NOT_MEASURED
    return CUMPLE if num * 100 >= umbral * den else NO_CUMPLE


def _veredicto_max(valor, maximo) -> str:
    if valor is None:
        return NOT_MEASURED
    return CUMPLE if valor <= maximo else NO_CUMPLE


@dataclass
class Grupo:
    telefono: str
    condicion: str
    motor: str
    filas: list[dict[str, str]] = field(default_factory=list)


def _agrupar(filas):
    grupos: dict[tuple[str, str, str], Grupo] = {}
    for fila in filas:
        clave = (fila["telefono"].strip(), fila["condicion"].strip(), fila["motor"].strip())
        grupos.setdefault(clave, Grupo(*clave)).filas.append(fila)
    return grupos


def _es_util(fila) -> bool:
    """D2: borrador utilizable sin corregir los campos esenciales.

    Interpretación declarada: el motor terminó bien y todos los campos
    esenciales que la ficha espera (producto, cantidad, unidad y, si los
    exige, parcela o persona) están correctos frente a la ficha.
    """
    if fila["estado_motor"].strip() != "ok":
        return False
    for tipo in TIPOS_CAMPO:
        valor = (fila.get(f"campo_{tipo}") or "").strip()
        if valor in ("", "no_esperado"):
            continue
        if valor != "correcto":
            return False
    return True


def metricas_voz(grupo: Grupo) -> dict:
    filas = grupo.filas
    fichas = {f["ficha_id"].strip() for f in filas}
    out: dict = {
        "telefono": grupo.telefono,
        "condicion": grupo.condicion,
        "motor": grupo.motor,
        "fichas": len(fichas),
        "dictados": len(filas),
    }

    # D1
    campos = {}
    for tipo in TIPOS_CAMPO:
        num = den = sin_medir = 0
        errores = {"transcripcion": 0, "interpretacion": 0, "ambos": 0, "sin_causa": 0}
        for fila in filas:
            valor = (fila.get(f"campo_{tipo}") or "").strip()
            if valor in ("", "no_esperado"):
                continue
            if valor == NOT_MEASURED:
                sin_medir += 1
                continue
            den += 1
            if valor == "correcto":
                num += 1
            else:
                causa = _causas(fila).get(tipo, "sin_causa")
                errores[causa if causa in errores else "sin_causa"] += 1
        umbral = UMBRALES["campos_correctos_pct"].get(grupo.condicion)
        campos[tipo] = {
            "numerador": num,
            "denominador": den,
            "porcentaje": _pct(num, den),
            "umbral_pct": umbral,
            "veredicto": _veredicto_pct(num, den, umbral) if umbral is not None else NOT_MEASURED,
            "sin_medir": sin_medir,
            "errores_por_causa": errores,
        }
    indebidos = [_entero(f.get("campos_indebidos")) or 0 for f in filas]
    out["d1_campos_correctos"] = campos
    out["d1_campos_indebidos"] = {
        "conteo": sum(indebidos),
        "dictados_afectados": sum(1 for n in indebidos if n > 0),
    }

    # D2
    utiles = sum(1 for f in filas if _es_util(f))
    umbral = UMBRALES["transcripciones_utiles_pct"].get(grupo.condicion)
    out["d2_transcripciones_utiles"] = {
        "numerador": utiles,
        "denominador": len(filas),
        "porcentaje": _pct(utiles, len(filas)),
        "umbral_pct": umbral,
        "veredicto": _veredicto_pct(utiles, len(filas), umbral),
    }

    # Tiempos
    parciales = [v for v in (_entero(f.get("primer_parcial_ms")) for f in filas) if v is not None]
    p50, p95 = percentil(parciales, 50), percentil(parciales, 95)
    u = UMBRALES["primer_parcial_ms"]
    out["primer_parcial_ms"] = {
        "n": len(parciales),
        "p50": p50 if p50 is not None else NOT_MEASURED,
        "p95": p95 if p95 is not None else NOT_MEASURED,
        "veredicto": _ambos(_veredicto_max(p50, u["p50"]), _veredicto_max(p95, u["p95"])),
    }

    u = UMBRALES["final_segunda_pasada_ms"]
    finales = []
    for f in filas:
        dur, fin = _entero(f.get("duracion_audio_ms")), _entero(f.get("segunda_pasada_ms"))
        if dur is not None and fin is not None and dur <= u["frase_max_ms"]:
            finales.append(fin)
    p50, p95 = percentil(finales, 50), percentil(finales, 95)
    out["final_segunda_pasada_ms"] = {
        "n": len(finales),
        "p50": p50 if p50 is not None else NOT_MEASURED,
        "p95": p95 if p95 is not None else NOT_MEASURED,
        "veredicto": _ambos(_veredicto_max(p50, u["p50"]), _veredicto_max(p95, u["p95"])),
    }

    u = UMBRALES["rtf_segunda_pasada"]
    rtfs = []
    for f in filas:
        dur, fin = _entero(f.get("duracion_audio_ms")), _entero(f.get("segunda_pasada_ms"))
        if dur and fin is not None and dur <= u["frase_max_ms"]:
            rtfs.append(fin / dur)
    p95 = percentil(rtfs, 95)
    out["rtf_segunda_pasada"] = {
        "n": len(rtfs),
        "p95": round(p95, 3) if p95 is not None else NOT_MEASURED,
        "veredicto": _veredicto_max(p95, u["p95"]),
    }
    return out


def _ambos(a: str, b: str) -> str:
    if NO_CUMPLE in (a, b):
        return NO_CUMPLE
    if NOT_MEASURED in (a, b):
        return NOT_MEASURED
    return CUMPLE


def _causas(fila) -> dict[str, str]:
    """``causa_errores`` = ``cantidad:interpretacion;producto:transcripcion``."""
    out = {}
    for parte in (fila.get("causa_errores") or "").split(";"):
        if ":" in parte:
            tipo, causa = parte.split(":", 1)
            out[tipo.strip()] = causa.strip()
    return out


def rechazo(filas) -> dict:
    por_tel: dict[str, dict] = {}
    for f in filas:
        tel = f["telefono"].strip()
        r = por_tel.setdefault(tel, {"muestras": 0, "texto_aceptado": 0, "sin_medir": 0})
        r["muestras"] += 1
        valor = (f.get("texto_aceptado") or "").strip().lower()
        if valor == "si":
            r["texto_aceptado"] += 1
        elif valor != "no":
            r["sin_medir"] += 1
    for r in por_tel.values():
        if r["texto_aceptado"] > UMBRALES["rechazo_textos_aceptados"]:
            r["veredicto"] = NO_CUMPLE
        elif r["sin_medir"]:
            r["veredicto"] = NOT_MEASURED
        else:
            r["veredicto"] = CUMPLE
    return por_tel


def escrituras(filas) -> dict:
    """Escrituras y sobrescrituras sin confirmación, por teléfono (o HOST)."""
    por_tel: dict[str, dict] = {}
    for f in filas:
        escenario = (f.get("escenario") or "").strip()
        if escenario not in ESCENARIOS_SIN_CONFIRMACION:
            raise RegistroInvalido(
                f"toma {f['toma_id']}: escenario {escenario!r} no es uno de {ESCENARIOS_SIN_CONFIRMACION}"
            )
        tel = f["telefono"].strip()
        r = por_tel.setdefault(
            tel, {"tomas": 0, "escrituras": 0, "sin_medir": 0, "escenarios": []}
        )
        r["tomas"] += 1
        if escenario not in r["escenarios"]:
            r["escenarios"].append(escenario)
        valores = [
            _entero(f.get("escrituras_sin_confirmacion")),
            _entero(f.get("sobrescrituras")),
        ]
        if None in valores:
            r["sin_medir"] += 1
        r["escrituras"] += sum(v for v in valores if v is not None)
    for r in por_tel.values():
        if r["escrituras"] > UMBRALES["escrituras_sin_confirmacion"]:
            r["veredicto"] = NO_CUMPLE
        elif r["sin_medir"]:
            r["veredicto"] = NOT_MEASURED
        else:
            r["veredicto"] = CUMPLE
    return por_tel


def frente_a_android(filas) -> list[dict]:
    """Cantidad y unidad, motor local frente a Android, sólo con los mismos audios.

    Si alguna toma local de un teléfono y condición no tiene su par Android
    con el mismo ``audio_id``, la comparación queda NO DEMOSTRADO (D6). No hay
    margen ni prueba estadística fijados: la comparación es descriptiva.
    """
    out = []
    claves = {(f["telefono"].strip(), f["condicion"].strip()) for f in filas}
    for tel, cond in sorted(claves):
        locales = [f for f in filas if (f["telefono"].strip(), f["condicion"].strip()) == (tel, cond) and f["motor"].strip() == "local"]
        android = {
            f["audio_id"].strip(): f
            for f in filas
            if (f["telefono"].strip(), f["condicion"].strip()) == (tel, cond)
            and f["motor"].strip() == "android"
            and (f.get("audio_id") or "").strip()
        }
        if not locales:
            continue
        pares = [(l, android.get((l.get("audio_id") or "").strip())) for l in locales]
        if any(not (l.get("audio_id") or "").strip() or a is None for l, a in pares):
            out.append({
                "telefono": tel,
                "condicion": cond,
                "veredicto": NO_DEMOSTRADO,
                "motivo": "sin los mismos audios para todas las tomas (D6): se registra la limitación",
            })
            continue

        def correctas(fila):
            return sum(1 for t in ("cantidad", "unidad") if (fila.get(f"campo_{t}") or "").strip() == "correcto")

        def esperadas(fila):
            return sum(1 for t in ("cantidad", "unidad") if (fila.get(f"campo_{t}") or "").strip() not in ("", "no_esperado", NOT_MEASURED))

        num_l = sum(correctas(l) for l, _ in pares)
        num_a = sum(correctas(a) for _, a in pares)
        den = sum(esperadas(l) for l, _ in pares)
        out.append({
            "telefono": tel,
            "condicion": cond,
            "pares": len(pares),
            "local": {"numerador": num_l, "denominador": den},
            "android": {"numerador": num_a, "denominador": den},
            "veredicto": NOT_MEASURED if den == 0 else (CUMPLE if num_l >= num_a else NO_CUMPLE),
            "nota": "descriptivo: c-12 no fija margen ni prueba estadística",
        })
    return out


def calcular(filas: list[dict[str, str]]) -> dict:
    voz = [f for f in filas if f["condicion"].strip() in CONDICIONES_VOZ]
    rech = [f for f in filas if f["condicion"].strip() in CONDICIONES_RECHAZO]
    sin_conf = [f for f in filas if f["condicion"].strip() == CONDICION_SIN_CONFIRMACION]
    otras = sorted(
        {f["condicion"].strip() for f in filas}
        - set(CONDICIONES_VOZ)
        - set(CONDICIONES_RECHAZO)
        - {CONDICION_SIN_CONFIRMACION}
    )
    if otras:
        raise RegistroInvalido(f"condiciones desconocidas: {', '.join(otras)}")
    grupos = _agrupar(voz)
    telefonos = sorted({f["telefono"].strip() for f in voz})
    resultado = {
        "metodo_percentil": "rango más cercano, sin interpolar (pendiente de confirmar)",
        "grupos": [metricas_voz(g) for _, g in sorted(grupos.items())],
        "no_ejecutado": [
            {"telefono": t, "condicion": c, "motor": m, "estado": NOT_RUN}
            for t in telefonos
            for m in sorted({f["motor"].strip() for f in voz} or {"local"})
            for c in CONDICIONES_VOZ
            if (t, c, m) not in grupos
        ],
        "rechazo": rechazo(rech) if rech else NOT_RUN,
        "escrituras_sin_confirmacion": escrituras(sin_conf) if sin_conf else NOT_RUN,
        "frente_a_android": frente_a_android(voz),
        "fuera_del_alcance_de_este_script": [
            "memoria pico total (<= 1,2 GB)",
            "estabilidad: 0 caídas, ANR u OOM en 30 sesiones consecutivas",
            "registro térmico y de batería en 10 min",
            "modo avión desde una instalación limpia",
        ],
    }
    return resultado


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("registro")
    parser.add_argument("--json", dest="salida")
    args = parser.parse_args(argv)
    with open(args.registro, encoding="utf-8") as fh:
        resultado = calcular(leer_registro(fh.read()))
    texto = json.dumps(resultado, ensure_ascii=False, indent=2)
    if args.salida:
        with open(args.salida, "w", encoding="utf-8") as fh:
            fh.write(texto + "\n")
    else:
        sys.stdout.write(texto + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
