# Automate Windows Audio

Defines `[AutoAudio]` for the default Windows playback device.

## Methods

| Method | Behavior |
| --- | --- |
| `Mute(bool)` | Mutes or unmutes. |
| `SetVolume(float)` | Unmutes, then sets the master volume from `0.0` to `1.0`. |
| `Speak(string)` | Uses `GetDefaultVoice()`, which prefers **Microsoft Mark** and otherwise uses the first installed voice. |
| `Speak(string, string)` | Uses the voice you name, such as `Microsoft Mark` or `Microsoft David`. Throws if that voice is not installed. A trailing ` Desktop`, as in `Microsoft Zira Desktop`, still selects that voice. |
| `Beep()` | Plays the console beep. |
| `Beep(int, int)` | Plays a tone: pitch in Hz, then length in milliseconds. |
| `PlaySound(string)` | Plays a `System.Media.SystemSounds` name (`Asterisk`, `Beep`, `Exclamation`, `Hand`, `Question`) or a Windows sound-scheme label such as `Desktop Mail Notification`. |
| `PlaySoundFile(string)` | Plays a `.wav` or `.mp3` path and waits until it finishes. A missing file throws. |

`[AutoAudio]` can be defined once per PowerShell window. Load this file again only when `("AutoAudio" -as [type])` is empty.

## Load

Dot-source it in the current session:

```powershell
. ".\Automate-Windows-Audio.ps1"
```

Or source it in another script:

```powershell
if (-not ("AutoAudio" -as [type])) {
  & (Join-Path $PSScriptRoot "Automate-Windows-Audio.ps1")
}
```

## Examples

```powershell
[AutoAudio]::Mute(0) # 0 = unmuted, 1 = muted

[AutoAudio]::SetVolume(0.4) # 0.0 to 1.0 (0–100%)

[AutoAudio]::Speak("Hello World!") # default voice: Microsoft Mark
[AutoAudio]::Speak("Hello World!", "Microsoft David")

[AutoAudio]::Beep()          # [console]::Beep()
[AutoAudio]::Beep(1000, 500) # pitch in Hz, then length in ms

[AutoAudio]::PlaySound("Desktop Mail Notification")
[AutoAudio]::PlaySoundFile("C:\windows\media\Windows Notify.wav") # .wav or .mp3
```
