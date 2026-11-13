"""Renderiza cada página de los PDF de una carpeta a PNG con PyMuPDF.

    python -I tool/rediseno/render_pdf_rdm2_c.py <carpeta> [dpi]

Escribe <nombre>_p<n>.png junto a cada PDF e imprime, por archivo, el número
de páginas, el tamaño de la hoja y cuántos «…» aparecen en el texto extraído.
Que la librería lea el PDF no demuestra que se vea bien: hay que mirar los PNG.
"""
import pathlib
import sys

import pymupdf


def main() -> None:
    folder = pathlib.Path(sys.argv[1])
    dpi = int(sys.argv[2]) if len(sys.argv) > 2 else 110
    for pdf in sorted(folder.glob("*.pdf")):
        doc = pymupdf.open(pdf)
        ellipses = 0
        for index, page in enumerate(doc, start=1):
            ellipses += page.get_text().count("…")
            page.get_pixmap(dpi=dpi).save(folder / f"{pdf.stem}_p{index}.png")
        first = doc[0].rect
        print(
            f"{pdf.name}: {doc.page_count} páginas, "
            f"{first.width:.0f}x{first.height:.0f} pt, '…' en el texto: {ellipses}"
        )


if __name__ == "__main__":
    main()
