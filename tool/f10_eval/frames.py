"""Evaluación F10 (protocolo v1.0 §1.6): tiempos de una repetición a partir del vídeo.

Lee un vídeo de `adb shell screenrecord` con los tiempos de presentación reales de
cada cuadro (sin duplicar ni descartar cuadros) y calcula:

- INICIO, según --start:
  - `touch`: primer cuadro en que la región alrededor del toque (--tap X,Y en
    píxeles de la pantalla) cambia respecto del primer cuadro del vídeo: aparece
    el indicador de `show_touches`.
  - `launch`: primer cuadro en que la pantalla completa cambia respecto del primer
    cuadro (comienzo de la animación de apertura tras `am start`).
- FIN: primer cuadro a partir del cual la región --end-roi X,Y,W,H coincide de
  forma estable con su estado final (el último cuadro del vídeo), dentro de
  --tolerance.

Escribe una línea JSON con los tiempos y los cuadros, y exporta en --frames-dir
los cuadros de inicio y de fin (y el anterior a cada uno) para comprobarlos a la
vista. No modifica el vídeo.

    python -I frames.py video.mp4 --start touch --tap 540,2200 \
        --end-roi 0,300,1080,1500 --frames-dir out/ [--scale 4]
"""

import argparse
import json
import pathlib
import subprocess
import sys


def probe(video):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "json", video],
        check=True, capture_output=True, text=True).stdout
    stream = json.loads(out)["streams"][0]
    times = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "frame=best_effort_timestamp_time", "-of", "csv=p=0",
         video],
        check=True, capture_output=True, text=True).stdout.split()
    return stream["width"], stream["height"], [float(t) for t in times if t not in ("", "N/A")]


def frames(video, crop, scale):
    """Cuadros en gris de la región `crop` (x, y, w, h), reducidos `scale` veces."""
    x, y, w, h = crop
    ow, oh = max(1, w // scale), max(1, h // scale)
    proc = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", video, "-fps_mode", "passthrough",
         "-vf", f"crop={w}:{h}:{x}:{y},scale={ow}:{oh}:flags=area,format=gray",
         "-f", "rawvideo", "-"],
        check=True, capture_output=True).stdout
    size = ow * oh
    return [proc[i:i + size] for i in range(0, len(proc), size)]


def diff(a, b):
    return sum(abs(p - q) for p, q in zip(a, b)) / len(a)


def export(video, index, path):
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", video, "-fps_mode", "passthrough",
         "-vf", f"select=eq(n\\,{index})", "-frames:v", "1", str(path)],
        check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--start", choices=["touch", "launch"], required=True)
    ap.add_argument("--tap", help="X,Y del toque en píxeles de pantalla")
    ap.add_argument("--tap-box", type=int, default=72, help="lado de la región del toque")
    ap.add_argument("--start-roi", help="X,Y,W,H donde se detecta el contacto (p. ej., la barra de "
                    "pointer_location); sustituye a la región alrededor de --tap")
    ap.add_argument("--end-roi", required=True, help="X,Y,W,H de la región del estado final")
    ap.add_argument("--scale", type=int, default=4)
    ap.add_argument("--start-threshold", type=float, default=6.0)
    ap.add_argument("--tolerance", type=float, default=1.5)
    ap.add_argument("--frames-dir")
    ap.add_argument("--screen-width", type=int, default=1080,
                    help="ancho de la pantalla en píxeles; --tap y --end-roi se dan en píxeles de pantalla")
    args = ap.parse_args()

    width, height, pts = probe(args.video)
    k = width / args.screen_width  # 720/1080: el vídeo se graba reducido
    if args.start == "touch":
        if not args.tap:
            sys.exit("--tap es obligatorio con --start touch")
        if args.start_roi:
            rx, ry, rw, rh = (round(int(v) * k) for v in args.start_roi.split(","))
            start_crop = (rx, ry, min(rw, width - rx), min(rh, height - ry))
        else:
            tx, ty = (round(int(v) * k) for v in args.tap.split(","))
            half = round(args.tap_box * k) // 2
            sx, sy = max(0, tx - half), max(0, ty - half)
            start_crop = (sx, sy, min(2 * half, width - sx), min(2 * half, height - sy))
        start_frames = frames(args.video, start_crop, 1)
    else:
        start_crop = (0, 0, width, height)
        start_frames = frames(args.video, start_crop, args.scale * 2)
    ex, ey, ew, eh = (round(int(v) * k) for v in args.end_roi.split(","))
    ew, eh = min(ew, width - ex), min(eh, height - ey)
    end_frames = frames(args.video, (ex, ey, ew, eh), args.scale)

    n = min(len(pts), len(start_frames), len(end_frames))
    if n < 3:
        sys.exit(f"vídeo demasiado corto: {n} cuadros")
    start = next((i for i in range(1, n)
                  if diff(start_frames[i], start_frames[0]) > args.start_threshold), None)
    if start is None:
        print(json.dumps({"video": args.video, "error": "sin inicio detectable", "frames": n}))
        return 2
    final = end_frames[n - 1]
    end = n - 1
    for i in range(n - 1, start - 1, -1):
        if diff(end_frames[i], final) > args.tolerance:
            break
        end = i
    result = {
        "video": pathlib.Path(args.video).name,
        "frames": n,
        "start_mode": args.start,
        "start_frame": start,
        "start_s": round(pts[start], 6),
        "end_frame": end,
        "end_s": round(pts[end], 6),
        "duration_ms": round((pts[end] - pts[start]) * 1000, 1),
        "end_settled_on_last_frame": end == n - 1,
        "video_last_s": round(pts[n - 1], 6),
        "params": {"tap": args.tap, "tap_box": args.tap_box, "start_roi": args.start_roi, "end_roi": args.end_roi,
                   "scale": args.scale, "video_px_per_screen_px": round(k, 4), "start_threshold": args.start_threshold,
                   "tolerance": args.tolerance},
    }
    if args.frames_dir:
        out = pathlib.Path(args.frames_dir)
        out.mkdir(parents=True, exist_ok=True)
        stem = pathlib.Path(args.video).stem
        for label, index in (("inicio", start), ("antes_inicio", start - 1),
                             ("fin", end), ("antes_fin", max(start, end - 1))):
            export(args.video, index, out / f"{stem}_{label}_{index}.png")
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
