"""¿Una pausa parte el dictado en dos frases, y se pierde algo? (POCO, §2.2)

Imita el bucle `decode` de `LocalVoiceEngine`: trozos de 100 ms;
`AcceptWaveform` cierra una frase (un segmento, si trae texto) y al final
`FinalResult`. Inserta silencios de distinta duración entre dos tramos y
compara las frases con las del audio sin pausa.

Audio SINTÉTICO (`synth_pause_parts.ps1`, voces de Windows), no voz humana.
Es una comprobación de desarrollo en el PC, no una medición del teléfono.

  powershell -File tool/voice_local/synth_pause_parts.ps1 <carpeta-wav>
  python -I tool/voice_local/pause_split_check.py <carpeta-wav> <modelo> <salida.json>
"""
import json
import sys
import wave
from pathlib import Path

from vosk import KaldiRecognizer, Model, SetLogLevel

AUDIO, MODEL, OUT = sys.argv[1:4]
SetLogLevel(-1)
model = Model(MODEL)
RATE = 16000
CHUNK = RATE // 10  # 100 ms, como CHUNK_SAMPLES


def pcm(path):
    with wave.open(str(path), "rb") as w:
        assert w.getframerate() == RATE and w.getnchannels() == 1
        return w.readframes(w.getnframes())


def silence(seconds):
    return b"\x00\x00" * int(RATE * seconds)


def run(audio):
    rec = KaldiRecognizer(model, RATE)
    segments = []
    step = CHUNK * 2
    for i in range(0, len(audio), step):
        chunk = audio[i:i + step]
        if rec.AcceptWaveform(chunk):
            text = json.loads(rec.Result()).get("text", "").strip()
            if text:
                segments.append(text)
    text = json.loads(rec.FinalResult()).get("text", "").strip()
    if text:
        segments.append(text)
    return segments


results = []
for first, second in (("a", "b"), ("c", "d")):
    for voice in ("helena", "laura", "pablo"):
        p1 = pcm(Path(AUDIO) / f"{first}_{voice}.wav")
        p2 = pcm(Path(AUDIO) / f"{second}_{voice}.wav")
        for pause in (0.0, 0.3, 0.5, 0.8, 1.2, 2.0, 4.0):
            audio = silence(0.3) + p1 + silence(pause) + p2 + silence(1.0)
            segs = run(audio)
            results.append({
                "par": first + second, "voz": voice, "pausa_s": pause,
                "segmentos": len(segs), "textos": segs,
            })
            print(f"{first}{second} {voice:7s} pausa={pause:>4}s -> "
                  f"{len(segs)} segmento(s): {' | '.join(segs)}")

Path(OUT).write_text(json.dumps(results, ensure_ascii=False, indent=1),
                     encoding="utf-8")
