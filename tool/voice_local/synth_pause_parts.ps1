# Audio SINTÉTICO en dos tramos para `pause_split_check.py` (POCO, §2.2).
#
# Voces de síntesis de Windows (OneCore, es-*). No es voz humana, no usa el
# micrófono del PC y no toca el corpus reservado de #12. Escribe
# <tramo>_<voz>.wav en 16 kHz, mono, 16 bits (ffmpeg en el PATH).
#
#   powershell -File tool/voice_local/synth_pause_parts.ps1 <carpeta-salida>
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
$parts = @(
  @('a', 'Apliqué doscientos cincuenta mililitros'),
  @('b', 'de Mancozeb'),
  @('c', 'Compré dos litros'),
  @('d', 'de Glifosato por cien bolivianos')
)
foreach ($voice in $voices) {
  $synth.Voice = $voice
  $tag = ($voice.DisplayName -split ' ')[1].ToLower()
  foreach ($p in $parts) {
    $stream = Await ($synth.SynthesizeTextToStreamAsync($p[1])) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
    $reader = New-Object Windows.Storage.Streams.DataReader($stream.GetInputStreamAt(0))
    $size = [uint32]$stream.Size
    [void](Await ($reader.LoadAsync($size)) ([uint32]))
    $bytes = New-Object byte[] $size
    $reader.ReadBytes($bytes)
    $raw = Join-Path $OutDir "$($p[0])_$tag.raw.wav"
    [IO.File]::WriteAllBytes($raw, $bytes)
    & ffmpeg -loglevel error -y -i $raw -ar 16000 -ac 1 -sample_fmt s16 (Join-Path $OutDir "$($p[0])_$tag.wav")
    Remove-Item $raw
  }
}
Write-Output "voces: $(($voices | ForEach-Object DisplayName) -join ', ')"
