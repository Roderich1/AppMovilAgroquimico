"""¿Está cada palabra en el vocabulario de un modelo Vosk de grafo lookahead?

    python -I tool/voice_local/vosk_vocab_check.py <ruta/graph/Gr.fst> palabra...

Los modelos «small» de Vosk (`HCLr.fst` + `Gr.fst`) guardan la tabla de
símbolos de palabras dentro de `Gr.fst` (formato OpenFst: cada símbolo es un
entero de 32 bits con la longitud en bytes, el texto en UTF-8 y un entero de
64 bits con su número). Se busca la secuencia exacta «longitud + texto»: así
«herbicida» no coincide dentro de «herbicidas».

Una palabra **ausente** no la puede escribir Vosk nunca: entrega otra parecida
que sí conoce. Una palabra **presente** y mal escrita en una transcripción es
un error de reconocimiento, no de vocabulario.

Sólo lee el archivo; no escribe nada. Diagnóstico F09 (2026-11-09).
"""
import hashlib
import struct
import sys


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    path, words = sys.argv[1], sys.argv[2:]
    data = open(path, 'rb').read()
    print(f'Gr.fst sha256={hashlib.sha256(data).hexdigest()} bytes={len(data)}')
    for word in words:
        raw = word.lower().encode('utf-8')
        present = (struct.pack('<i', len(raw)) + raw) in data
        print(f'{word}\t{"presente" if present else "AUSENTE"}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
