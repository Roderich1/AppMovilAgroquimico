# Audio de referencia SINTÉTICO para comprobar el reconocimiento local (HOST).
#
# Procedencia: voces de síntesis de Windows (OneCore, es-ES: Helena, Laura,
# Pablo) a partir de las frases de `reference_phrases.tsv`. No es voz humana, no
# usa el micrófono del PC y no toca el corpus reservado de #12.
#
#   powershell -File tool/voice_local/synth_reference_audio.ps1 <carpeta-salida>
#
# Escribe <id>_<voz>.wav en 16 kHz, mono, 16 bits (ffmpeg en el PATH).
param([Parameter(Mandatory = $true)][string]$OutDir)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null

[void][Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType = WindowsRuntime]
[void][Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType = WindowsRuntime]
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
  $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
function Await($op, [Type]$type) {
  $task = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
  $task.Wait() | Out-Null
  $task.Result
}

$synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$voices = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object { $_.Language -like 'es-*' }
$phrases = Get-Content (Join-Path $PSScriptRoot 'reference_phrases.tsv') -Encoding UTF8 |
  Where-Object { $_ -and -not $_.StartsWith('#') }

foreach ($voice in $voices) {
  $synth.Voice = $voice
  $tag = ($voice.DisplayName -split ' ')[1].ToLower()
  foreach ($line in $phrases) {
    $id, $text = $line -split "`t", 2
    $stream = Await ($synth.SynthesizeTextToStreamAsync($text)) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
    $reader = New-Object Windows.Storage.Streams.DataReader($stream.GetInputStreamAt(0))
    $size = [uint32]$stream.Size
    [void](Await ($reader.LoadAsync($size)) ([uint32]))
    $bytes = New-Object byte[] $size
    $reader.ReadBytes($bytes)
    $raw = Join-Path $OutDir "$id`_$tag.raw.wav"
    [IO.File]::WriteAllBytes($raw, $bytes)
    & ffmpeg -loglevel error -y -i $raw -ar 16000 -ac 1 -sample_fmt s16 (Join-Path $OutDir "$id`_$tag.wav")
    Remove-Item $raw
  }
}
Write-Output "voces: $(($voices | ForEach-Object DisplayName) -join ', ')"
