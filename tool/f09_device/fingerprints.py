"""Huellas que el ensayo físico de F09 fija ANTES de la primera toma.

    python -I -X utf8 fingerprints.py <worktree-mobile> <apk> <conjunto> [salida.json]

Imprime y guarda (JSON):
- `mobile_sha`: HEAD completo del worktree, que tiene que estar limpio;
- `interpreter_tree`: árbol git de `lib/voice_draft` en ese HEAD (el intérprete);
- `protocol_sha256`: SHA-256 del protocolo `F09_VOZ_ENSAYO_FISICO_PLAN.md` en ese HEAD;
- `apk_sha256`: SHA-256 del APK;
- `set_sha256`: SHA-256 de los bytes del conjunto nuevo y sus expectativas, un archivo
  FUERA del repositorio. Se calcula sin abrirlo ni mostrarlo.

No lee ni imprime el contenido del conjunto. Una huella fijada no se recalcula después
de ver un resultado: si el archivo cambia, es otro conjunto y se declara.
"""
import datetime
import hashlib
import json
import subprocess
import sys

PROTOCOL = 'docs/evolution/features/F09_VOZ_ENSAYO_FISICO_PLAN.md'


def git(worktree, *args):
    return subprocess.run(['git', '-C', worktree, *args], capture_output=True,
                          check=True).stdout


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    worktree, apk, corpus = sys.argv[1:4]
    if git(worktree, 'status', '--porcelain').strip():
        sys.exit('El worktree Mobile no está limpio')
    head = git(worktree, 'rev-parse', 'HEAD').decode().strip()
    result = {
        'fixed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
        'mobile_sha': head,
        'interpreter_tree': git(worktree, 'rev-parse', f'{head}:lib/voice_draft').decode().strip(),
        'protocol_sha256': hashlib.sha256(git(worktree, 'show', f'{head}:{PROTOCOL}')).hexdigest(),
        'apk_sha256': sha256_file(apk),
        'set_sha256': sha256_file(corpus),
    }
    text = json.dumps(result, indent=2)
    print(text)
    if len(sys.argv) > 4:
        with open(sys.argv[4], 'w', encoding='utf-8') as f:
            f.write(text + '\n')


if __name__ == '__main__':
    main()
