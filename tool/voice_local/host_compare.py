"""Comparación HOST de la transcripción local sobre audio de referencia.

Inferencia real, sin resultados prefabricados:
  * Vosk (paquete `vosk` de Python, mismo modelo `vosk-model-small-es-0.42`
    que lleva la app), alimentado en trozos de 100 ms como el micrófono;
  * whisper.cpp (`whisper-cli` compilado del commit fijado) sobre cada
    segmento que cerró Vosk, con y sin pista de vocabulario.

Es una comprobación de desarrollo en el PC, no una medición del teléfono:
los tiempos y la memoria que imprime describen este PC y no se trasladan a
Android.

  python -I host_compare.py <carpeta-audio> <frases.tsv> <modelo-vosk> \
      <whisper-cli> <ggml-base> <ggml-small> <salida.json>

Opcional, por variables de entorno (se registran en la salida):
  HOST_COMPARE_THREADS   hilos de whisper-cli (por defecto 8, como el
                         2026-11-05; la app usa min(4, núcleos)).
  HOST_COMPARE_DECODING  `cli` (por defecto: lo que trae whisper-cli, haz de
                         5 y reintentos de temperatura, como el 2026-11-05) o
                         `app` (voraz y sin reintentos, como `whisper_jni.c`).

Por cada segmento y configuración registra el tiempo de pared del proceso,
la carga del modelo y la inferencia según `whisper_print_timings`, el
factor de tiempo real (inferencia / duración del segmento) y la memoria pico
del proceso (`PeakWorkingSetSize` y `PeakPagefileUsage` en Windows;
`ru_maxrss` de los hijos en POSIX, que es un máximo acumulado).

Puntuar lo que la app habría entregado con su regla de selección:

  python -I host_compare.py --score-selection <salida.json> <seleccion.json>

donde <seleccion.json> lo escribe `selection_on_results_test.dart` en modo
HOST (`AGRO_HOST_COMPARE`).
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import time
import unicodedata
import wave
from pathlib import Path

# Lo que la app pasaría como pista: nombres del catálogo y personas de la DEMO.
HINT = ("Glifosato, Bellator, Atrazina, Paraquat, Mancozeb, Cipermetrina, "
        "Tebuconazole, Herbicida, Fungicida, Insecticida, Ana Quispe, "
        "Beto Mamani, litros, mililitros, kilos, gramos, bolivianos.")
PRODUCTS = ["glifosato", "bellator", "atrazina", "paraquat", "mancozeb",
            "cipermetrina", "tebuconazole", "herbicida", "fungicida",
            "insecticida", "glicerina"]

UNITS = {"cero": 0, "un": 1, "uno": 1, "una": 1, "dos": 2, "tres": 3,
         "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8,
         "nueve": 9, "diez": 10, "once": 11, "doce": 12, "trece": 13,
         "catorce": 14, "quince": 15, "dieciseis": 16, "diecisiete": 17,
         "dieciocho": 18, "diecinueve": 19, "veinte": 20, "veintiuno": 21,
         "veintidos": 22, "veintitres": 23, "veinticuatro": 24,
         "veinticinco": 25, "treinta": 30, "cuarenta": 40, "cincuenta": 50,
         "sesenta": 60, "setenta": 70, "ochenta": 80, "noventa": 90,
         "cien": 100, "ciento": 100, "doscientos": 200, "trescientos": 300,
         "cuatrocientos": 400, "quinientos": 500, "seiscientos": 600,
         "setecientos": 700, "ochocientos": 800, "novecientos": 900}

THREADS = int(os.environ.get("HOST_COMPARE_THREADS", "8"))
DECODING = os.environ.get("HOST_COMPARE_DECODING", "cli")
if DECODING not in ("cli", "app"):
    sys.exit("HOST_COMPARE_DECODING: cli o app")


def fold(text):
    text = unicodedata.normalize("NFD", text.lower())
    return "".join(c for c in text if unicodedata.category(c) != "Mn")


def tokens(text):
    """Minúsculas, sin tildes ni puntuación, números como cifras.

    Sólo para medir: la app tiene su propio normalizador y no usa éste.
    """
    text = fold(text)
    text = re.sub(r"(\d)\.(\d{3})\b", r"\1\2", text)          # 1.200 -> 1200
    text = re.sub(r"(\d),(\d)", r"\1 coma \2", text)           # 2,5 -> 2 coma 5
    text = re.sub(r"(\d)\.(\d)", r"\1 coma \2", text)
    words = re.findall(r"[a-z0-9]+", text)
    out, value, active = [], 0, False
    for i, w in enumerate(words):
        if w.isdigit():
            if active:
                out.append(str(value)); value, active = 0, False
            out.append(str(int(w)))
            continue
        if w in UNITS or w == "mil":
            if w == "mil":
                value = (value or 1) * 1000
            else:
                value += UNITS[w]
            active = True
            continue
        if w == "y" and active and i + 1 < len(words) and words[i + 1] in UNITS \
                and UNITS[words[i + 1]] < 10:
            continue
        if active:
            out.append(str(value)); value, active = 0, False
        out.append(w)
    if active:
        out.append(str(value))
    return out


def wer(ref, hyp):
    r, h = tokens(ref), tokens(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = d[j]
            d[j] = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev = cur
    return d[len(h)] / max(1, len(r))


def numbers(text):
    return [t for t in tokens(text) if t.isdigit() or t == "coma"]


def product_of(text):
    t = tokens(text)
    return [p for p in PRODUCTS if p in t]


def percentile(values, q):
    """Rango más cercano, sin interpolar (como `f09_metricas.py`)."""
    if not values:
        return None
    ordered = sorted(values)
    rank = max(1, -(-len(ordered) * q // 100))
    return ordered[int(rank) - 1]


def read_refs(path):
    refs = {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#"):
            k, v = line.split("\t", 1)
            refs[k] = v
    refs["p01"] = refs["f01"] + " " + refs["f03"]
    return refs


def accuracy(rows, get):
    """Exactitud de una configuración sobre las filas con frase de referencia."""
    scored = [r for r in rows if r["ref"]]
    prod_total = prod_ok = num_ok = false_prod = 0
    for r in scored:
        want = product_of(r["ref"])
        got = product_of(get(r))
        prod_total += len(want)
        prod_ok += len([p for p in want if p in got])
        false_prod += len([p for p in got if p not in want])
        num_ok += numbers(r["ref"]) == numbers(get(r))
    return {
        "wer_mean": round(sum(wer(r["ref"], get(r)) for r in scored) / len(scored), 3),
        "exact_after_normalization": sum(tokens(r["ref"]) == tokens(get(r)) for r in scored),
        "products_ok": f"{prod_ok}/{prod_total}",
        "products_not_said": false_prod,
        "numbers_ok": f"{num_ok}/{len(scored)}",
    }


# ------------------------------------------------------------------ medición

def read_pcm(path):
    with wave.open(str(path), "rb") as w:
        assert w.getframerate() == 16000 and w.getnchannels() == 1
        return w.readframes(w.getnframes())


def vosk_run(model, pcm):
    """Como el motor de la app: trozos de 100 ms, parciales y segmentos."""
    from vosk import KaldiRecognizer
    rec = KaldiRecognizer(model, 16000)
    rec.SetWords(True)
    chunk = 3200
    segments, partials, first_partial_ms = [], 0, None
    last_partial = ""
    for off in range(0, len(pcm), chunk):
        if rec.AcceptWaveform(pcm[off:off + chunk]):
            res = json.loads(rec.Result())
            if res.get("text"):
                segments.append(res)
            last_partial = ""
        else:
            p = json.loads(rec.PartialResult()).get("partial", "")
            if p and p != last_partial:
                partials += 1
                last_partial = p
                if first_partial_ms is None:
                    first_partial_ms = (off + chunk) * 1000 // 32000
    res = json.loads(rec.FinalResult())
    if res.get("text"):
        segments.append(res)
    return segments, partials, first_partial_ms


def peak_memory(proc):
    """(pico de memoria residente, pico de memoria privada) en bytes, o None."""
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes

        class Counters(ctypes.Structure):
            _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                        ("PeakWorkingSetSize", ctypes.c_size_t),
                        ("WorkingSetSize", ctypes.c_size_t),
                        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                        ("QuotaPagedPoolUsage", ctypes.c_size_t),
                        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                        ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                        ("PagefileUsage", ctypes.c_size_t),
                        ("PeakPagefileUsage", ctypes.c_size_t)]

        counters = Counters()
        counters.cb = ctypes.sizeof(counters)
        psapi = ctypes.WinDLL("psapi")
        psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters),
                                               wintypes.DWORD]
        ok = psapi.GetProcessMemoryInfo(wintypes.HANDLE(int(proc._handle)),
                                        ctypes.byref(counters), counters.cb)
        return (counters.PeakWorkingSetSize, counters.PeakPagefileUsage) if ok else (None, None)
    import resource
    return resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss * 1024, None


def timing(stderr, name):
    m = re.search(rf"{name} time =\s*([\d.]+) ms", stderr)
    return float(m.group(1)) if m else None


def whisper(model, wav, prompt):
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp) / "out"
        cmd = [WHISPER_CLI, "-m", model, "-f", str(wav), "-l", "es", "-t", str(THREADS),
               "-nt", "-sns", "-otxt", "-of", str(base)]
        if DECODING == "app":
            cmd += ["-bs", "1", "-bo", "1", "-nf"]
        if prompt:
            cmd += ["--prompt", prompt]
        start = time.perf_counter()
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        _, err = proc.communicate()
        took = time.perf_counter() - start
        rss, private = peak_memory(proc)
        if proc.returncode:
            raise subprocess.CalledProcessError(proc.returncode, cmd)
        err = err.decode("utf-8", "replace")
        load, total = timing(err, "load"), timing(err, "total")
        return base.with_suffix(".txt").read_text(encoding="utf-8").strip(), {
            "wall_ms": round(took * 1000, 1),
            "load_ms": load,
            "encode_ms": timing(err, "encode"),
            "infer_ms": round(total - load, 1) if load is not None and total is not None else None,
            "peak_rss_mb": round(rss / 2**20, 1) if rss else None,
            "peak_private_mb": round(private / 2**20, 1) if private else None,
        }


def slice_wav(pcm, seg, tmpdir, idx):
    """El audio del segmento con 300 ms de margen, como lo guardaría la app."""
    start = max(0, seg["result"][0]["start"] - 0.3)
    end = seg["result"][-1]["end"] + 0.3
    a, b = int(start * 16000) * 2, int(end * 16000) * 2
    path = Path(tmpdir) / f"seg{idx}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
        w.writeframes(pcm[a:b])
    return path, (b - a) / 32000


CONFIGS = ("base", "base_hint", "small_hint")


def main():
    from vosk import Model, SetLogLevel
    SetLogLevel(-1)
    refs = read_refs(PHRASES)
    model = Model(VOSK_MODEL)
    rows = []
    for wav in sorted(Path(AUDIO).glob("*.wav")):
        pid = wav.stem.split("_")[0]
        ref = refs.get(pid, "")
        pcm = read_pcm(wav)
        segs, partials, first = vosk_run(model, pcm)
        vosk_text = " ".join(s["text"] for s in segs)
        row = {"file": wav.name, "ref": ref, "vosk": vosk_text,
               "vosk_segs": [s["text"] for s in segs],
               "vosk_segments": len(segs), "vosk_partials": partials,
               "vosk_first_partial_audio_ms": first}
        with tempfile.TemporaryDirectory() as tmp:
            slices = [slice_wav(pcm, s, tmp, i) for i, s in enumerate(segs)]
            for name, ggml, prompt in (("base", GGML_BASE, None),
                                       ("base_hint", GGML_BASE, HINT),
                                       ("small_hint", GGML_SMALL, HINT)):
                texts, took, measures = [], 0.0, []
                for path, seconds in slices:
                    text, m = whisper(ggml, path, prompt)
                    m["audio_s"] = round(seconds, 2)
                    m["rtf"] = round(m["infer_ms"] / 1000 / seconds, 3) \
                        if m["infer_ms"] is not None and seconds else None
                    texts.append(text); took += m["wall_ms"] / 1000
                    measures.append(m)
                row[name] = " ".join(texts)
                row[name + "_segs"] = texts
                row[name + "_host_s"] = round(took, 2)
                row[name + "_measures"] = measures
            # Sobre el archivo entero, aunque Vosk no haya oído nada: es la
            # prueba de alucinación que justifica no llamar a Whisper sin habla.
            if not segs:
                row["base_whole_file"] = whisper(GGML_BASE, wav, None)[0]
                row["small_whole_file"] = whisper(GGML_SMALL, wav, HINT)[0]
        rows.append(row)
        print(json.dumps({k: v for k, v in row.items() if not k.endswith("_measures")},
                         ensure_ascii=False), flush=True)

    summary = {"vosk": accuracy(rows, lambda r: r["vosk"])}
    cost = {}
    for name in CONFIGS:
        summary[name] = accuracy(rows, lambda r, n=name: r[n])
        ms = [m for r in rows for m in r[name + "_measures"]]

        def pick(key, ms=ms):
            return [m[key] for m in ms if m[key] is not None]

        infer, wall, rtf = pick("infer_ms"), pick("wall_ms"), pick("rtf")
        cost[name] = {
            "segments": len(ms),
            "audio_s_max": max(pick("audio_s"), default=None),
            "infer_ms_p50": percentile(infer, 50), "infer_ms_p95": percentile(infer, 95),
            "infer_ms_max": max(infer, default=None),
            "wall_ms_p50": percentile(wall, 50), "wall_ms_p95": percentile(wall, 95),
            "load_ms_p50": percentile(pick("load_ms"), 50),
            "rtf_p50": percentile(rtf, 50), "rtf_p95": percentile(rtf, 95),
            "peak_rss_mb_max": max(pick("peak_rss_mb"), default=None),
            "peak_private_mb_max": max(pick("peak_private_mb"), default=None),
        }
    out = {"rows": rows, "summary": summary, "cost": cost, "phrases": len([r for r in rows if r["ref"]]),
           "hint": HINT, "threads": THREADS, "decoding": DECODING,
           "percentile": "rango más cercano, sin interpolar"}
    Path(OUT).write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps({"summary": summary, "cost": cost, "threads": THREADS,
                      "decoding": DECODING}, ensure_ascii=False, indent=1))


def score_selection(host_json, selection_json):
    """Exactitud de lo que la app entregaría tras su regla de selección."""
    host = json.loads(Path(host_json).read_text(encoding="utf-8"))
    selection = json.loads(Path(selection_json).read_text(encoding="utf-8"))
    rows = {r["file"]: r for r in host["rows"]}
    out = {}
    for name, picks in selection.items():
        scored = [dict(rows[f], picked=v["text"]) for f, v in picks.items()]
        verdicts = {}
        for v in picks.values():
            for verdict in v["verdicts"]:
                verdicts[verdict] = verdicts.get(verdict, 0) + 1
        out[name] = {"accuracy": accuracy(scored, lambda r: r["picked"]), "verdicts": verdicts}
    print(json.dumps(out, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    if sys.argv[1:2] == ["--score-selection"]:
        score_selection(*sys.argv[2:4])
    else:
        AUDIO, PHRASES, VOSK_MODEL, WHISPER_CLI, GGML_BASE, GGML_SMALL, OUT = sys.argv[1:8]
        main()
