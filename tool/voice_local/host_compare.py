"""Comparación HOST de la transcripción local sobre audio de referencia.

Inferencia real, sin resultados prefabricados:
  * Vosk (paquete `vosk` de Python, mismo modelo `vosk-model-small-es-0.42`
    que lleva la app), alimentado en trozos de 100 ms como el micrófono;
  * whisper.cpp (`whisper-cli` compilado del commit fijado) sobre cada
    segmento que cerró Vosk, con y sin pista de vocabulario.

Es una comprobación de desarrollo en el PC, no una medición del teléfono:
los tiempos que imprime describen este PC y no se trasladan a Android.

  python -I host_compare.py <carpeta-audio> <frases.tsv> <modelo-vosk> \
      <whisper-cli> <ggml-base> <ggml-small> <salida.json>
"""

import json
import re
import subprocess
import sys
import tempfile
import time
import unicodedata
import wave
from pathlib import Path

from vosk import KaldiRecognizer, Model, SetLogLevel

AUDIO, PHRASES, VOSK_MODEL, WHISPER_CLI, GGML_BASE, GGML_SMALL, OUT = sys.argv[1:8]

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


def read_pcm(path):
    with wave.open(str(path), "rb") as w:
        assert w.getframerate() == 16000 and w.getnchannels() == 1
        return w.readframes(w.getnframes())


def vosk_run(model, pcm):
    """Como el motor de la app: trozos de 100 ms, parciales y segmentos."""
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


def whisper(model, wav, prompt):
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp) / "out"
        cmd = [WHISPER_CLI, "-m", model, "-f", str(wav), "-l", "es", "-t", "8",
               "-nt", "-np", "-sns", "-otxt", "-of", str(base)]
        if prompt:
            cmd += ["--prompt", prompt]
        start = time.perf_counter()
        subprocess.run(cmd, check=True, capture_output=True)
        took = time.perf_counter() - start
        return base.with_suffix(".txt").read_text(encoding="utf-8").strip(), took


def slice_wav(pcm, seg, tmpdir, idx):
    """El audio del segmento con 300 ms de margen, como lo guardaría la app."""
    start = max(0, seg["result"][0]["start"] - 0.3)
    end = seg["result"][-1]["end"] + 0.3
    a, b = int(start * 16000) * 2, int(end * 16000) * 2
    path = Path(tmpdir) / f"seg{idx}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
        w.writeframes(pcm[a:b])
    return path


def main():
    SetLogLevel(-1)
    refs = {}
    for line in Path(PHRASES).read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#"):
            k, v = line.split("\t", 1)
            refs[k] = v
    refs["p01"] = refs["f01"] + " " + refs["f03"]
    model = Model(VOSK_MODEL)
    rows = []
    for wav in sorted(Path(AUDIO).glob("*.wav")):
        pid = wav.stem.split("_")[0]
        ref = refs.get(pid, "")
        pcm = read_pcm(wav)
        segs, partials, first = vosk_run(model, pcm)
        vosk_text = " ".join(s["text"] for s in segs)
        row = {"file": wav.name, "ref": ref, "vosk": vosk_text,
               "vosk_segments": len(segs), "vosk_partials": partials,
               "vosk_first_partial_audio_ms": first}
        with tempfile.TemporaryDirectory() as tmp:
            slices = [slice_wav(pcm, s, tmp, i) for i, s in enumerate(segs)]
            for name, ggml, prompt in (("base", GGML_BASE, None),
                                       ("base_hint", GGML_BASE, HINT),
                                       ("small_hint", GGML_SMALL, HINT)):
                texts, took = [], 0.0
                for sl in slices:
                    text, t = whisper(ggml, sl, prompt)
                    texts.append(text); took += t
                row[name] = " ".join(texts)
                row[name + "_host_s"] = round(took, 2)
            # Sobre el archivo entero, aunque Vosk no haya oído nada: es la
            # prueba de alucinación que justifica no llamar a Whisper sin habla.
            if not segs:
                row["base_whole_file"] = whisper(GGML_BASE, wav, None)[0]
                row["small_whole_file"] = whisper(GGML_SMALL, wav, HINT)[0]
        rows.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)

    summary = {}
    scored = [r for r in rows if r["ref"]]
    for eng in ("vosk", "base", "base_hint", "small_hint"):
        prod_total = prod_ok = num_ok = false_prod = 0
        for r in scored:
            want = product_of(r["ref"])
            got = product_of(r[eng])
            prod_total += len(want)
            prod_ok += len([p for p in want if p in got])
            false_prod += len([p for p in got if p not in want])
            num_ok += numbers(r["ref"]) == numbers(r[eng])
        summary[eng] = {
            "wer_mean": round(sum(wer(r["ref"], r[eng]) for r in scored) / len(scored), 3),
            "exact_after_normalization": sum(tokens(r["ref"]) == tokens(r[eng]) for r in scored),
            "products_ok": f"{prod_ok}/{prod_total}",
            "products_not_said": false_prod,
            "numbers_ok": f"{num_ok}/{len(scored)}",
        }
    out = {"rows": rows, "summary": summary, "phrases": len(scored),
           "hint": HINT}
    Path(OUT).write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=1))


main()
