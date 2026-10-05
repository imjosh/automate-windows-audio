<#
.SYNOPSIS
  Mute, set volume, speak, beep, and play sounds on the default Windows playback device.

.DESCRIPTION
  Defines the AutoAudio type for the current PowerShell session. Load this file once
  per window, and again only when ("AutoAudio" -as [type]) is empty.

  Mute(bool) mutes or unmutes.
  SetVolume(float) unmutes, then sets the master volume from 0.0 to 1.0.
  Speak(string) prefers "Microsoft Mark" and otherwise uses the first installed voice.
  Speak(string, string) uses the voice you name and throws if it is not installed.
  Voice names are the Windows display names, such as "Microsoft Mark". A trailing " Desktop"
  still selects that voice, so "Microsoft Zira Desktop" selects "Microsoft Zira".
  Beep() plays the console beep. Beep(int, int) plays a tone: pitch in Hz, then length in milliseconds.
  PlaySound(string) plays a System.Media.SystemSounds name (Asterisk, Beep, Exclamation, Hand, Question)
  or a Windows sound-scheme label such as "Desktop Mail Notification".
  PlaySoundFile(string) plays a .wav or .mp3 path and waits until it finishes. A missing file throws.

.EXAMPLE
  . .\Automate-Windows-Audio.ps1
  [AutoAudio]::SetVolume(0.4)
  [AutoAudio]::Speak("Hello World!")

.NOTES
  Requires Windows. Speech uses the Windows Runtime voices, including OneCore voices such as Microsoft Mark.
#>

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

public class AutoAudio {
  [ComImport]
  [Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
  class MMDeviceEnumerator {}

  enum EDataFlow { eRender, eCapture, eAll }
  enum ERole { eConsole, eMultimedia, eCommunications }

  [ComImport]
  [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
  [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceEnumerator {
    int NotImpl1();
    [PreserveSig]
    int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice device);
  }

  [ComImport]
  [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
  [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDevice {
    [PreserveSig]
    int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, out IAudioEndpointVolume endpointVolume);
  }

  [ComImport]
  [Guid("5CDF2C82-841E-4546-9722-0CF74078229A")]
  [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioEndpointVolume {
    int RegisterControlChangeNotify(IntPtr pNotify);
    int UnregisterControlChangeNotify(IntPtr pNotify);
    int GetChannelCount(out uint channelCount);
    int SetMasterVolumeLevel(float levelDB, ref Guid eventContext);
    int SetMasterVolumeLevelScalar(float level, ref Guid eventContext);
    int GetMasterVolumeLevel(out float levelDB);
    int GetMasterVolumeLevelScalar(out float level);
    int SetChannelVolumeLevel(uint channelNumber, float levelDB, ref Guid eventContext);
    int SetChannelVolumeLevelScalar(uint channelNumber, float level, ref Guid eventContext);
    int GetChannelVolumeLevel(uint channelNumber, out float levelDB);
    int GetChannelVolumeLevelScalar(uint channelNumber, out float level);
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool isMuted, ref Guid eventContext);
  }

  public static void SetVolume(float volume) {
    var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
    IMMDevice device;
    enumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eMultimedia, out device);

    Guid iid = typeof(IAudioEndpointVolume).GUID;
    IAudioEndpointVolume endpoint;
    device.Activate(ref iid, 23, IntPtr.Zero, out endpoint);

    Guid ctx = Guid.Empty;
    endpoint.SetMute(false, ref ctx);
    endpoint.SetMasterVolumeLevelScalar(volume, ref ctx);
  }

  public static void Mute(bool isMuted) {
    var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
    IMMDevice device;
    enumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eMultimedia, out device);

    Guid iid = typeof(IAudioEndpointVolume).GUID;
    IAudioEndpointVolume endpoint;
    device.Activate(ref iid, 23, IntPtr.Zero, out endpoint);

    Guid ctx = Guid.Empty;
    endpoint.SetMute(isMuted, ref ctx);
  }

  const string PreferredVoiceName = "Microsoft Mark";
  const string WinRtMedia = "Windows.Media, Version=255.255.255.255, Culture=neutral, PublicKeyToken=null, ContentType=WindowsRuntime";

  static Type speechSynthesizerType;
  static Type speechStreamType;
  static MethodInfo asTaskMethod;
  static MethodInfo asStreamForReadMethod;

  static Type SpeechSynthesizerType {
    get {
      EnsureSpeech();
      return speechSynthesizerType;
    }
  }

  public static string GetDefaultVoice() {
    object preferred = FindVoice(PreferredVoiceName);
    if (preferred != null) return VoiceDisplayName(preferred);
    foreach (object voice in InstalledVoices()) {
      return VoiceDisplayName(voice);
    }
    throw new Exception("No installed voices found");
  }

  public static void Speak(string text) {
    Speak(text, GetDefaultVoice());
  }

  public static void Speak(string text, string voiceName) {
    object voice = FindVoice(voiceName);
    if (voice == null) {
      throw new ArgumentException("Voice is not installed: " + voiceName);
    }
    object synth = Activator.CreateInstance(SpeechSynthesizerType);
    try {
      SpeechSynthesizerType.GetProperty("Voice").SetValue(synth, voice, null);
      byte[] wav = SynthesizeWav(synth, text);
      using (var mem = new MemoryStream(wav))
      using (var player = new System.Media.SoundPlayer(mem)) {
        player.PlaySync();
      }
    } finally {
      Close(synth);
    }
  }

  static void EnsureSpeech() {
    if (speechSynthesizerType != null) return;
    Type synthesizer = RequireWinRt("Windows.Media.SpeechSynthesis.SpeechSynthesizer");
    Type stream = RequireWinRt("Windows.Media.SpeechSynthesis.SpeechSynthesisStream");
    MethodInfo asTask = FindMethod(typeof(System.WindowsRuntimeSystemExtensions), "AsTask", "IAsyncOperation``1");
    MethodInfo asStream = FindMethod(typeof(System.IO.WindowsRuntimeStreamExtensions), "AsStreamForRead", null);
    speechStreamType = stream;
    asTaskMethod = asTask;
    asStreamForReadMethod = asStream;
    speechSynthesizerType = synthesizer;
  }

  static Type RequireWinRt(string name) {
    Type type = Type.GetType(name + ", " + WinRtMedia);
    if (type == null) throw new InvalidOperationException("Windows speech is not available: " + name);
    return type;
  }

  static MethodInfo FindMethod(Type type, string name, string firstParameterName) {
    foreach (MethodInfo method in type.GetMethods()) {
      if (method.Name != name) continue;
      ParameterInfo[] parameters = method.GetParameters();
      if (parameters.Length != 1) continue;
      if (name == "AsTask" && !method.IsGenericMethodDefinition) continue;
      if (firstParameterName != null && parameters[0].ParameterType.Name != firstParameterName) continue;
      return method;
    }
    throw new InvalidOperationException("Could not find " + type.Name + "." + name);
  }

  static System.Collections.IEnumerable InstalledVoices() {
    return (System.Collections.IEnumerable)SpeechSynthesizerType.GetProperty("AllVoices").GetValue(null, null);
  }

  static string VoiceDisplayName(object voice) {
    return (string)voice.GetType().GetProperty("DisplayName").GetValue(voice, null);
  }

  static object FindVoice(string voiceName) {
    if (string.IsNullOrEmpty(voiceName)) return null;
    string withoutDesktop = voiceName;
    const string desktopSuffix = " Desktop";
    if (voiceName.EndsWith(desktopSuffix, StringComparison.OrdinalIgnoreCase)) {
      withoutDesktop = voiceName.Substring(0, voiceName.Length - desktopSuffix.Length);
    }
    object suffixMatch = null;
    foreach (object voice in InstalledVoices()) {
      string displayName = VoiceDisplayName(voice);
      if (string.Equals(displayName, voiceName, StringComparison.OrdinalIgnoreCase)) return voice;
      if (suffixMatch == null && string.Equals(displayName, withoutDesktop, StringComparison.OrdinalIgnoreCase)) {
        suffixMatch = voice;
      }
    }
    return suffixMatch;
  }

  static byte[] SynthesizeWav(object synth, string text) {
    object operation = SpeechSynthesizerType.GetMethod("SynthesizeTextToStreamAsync").Invoke(synth, new object[] { text });
    Task task = (Task)asTaskMethod.MakeGenericMethod(speechStreamType).Invoke(null, new object[] { operation });
    task.GetAwaiter().GetResult();
    object stream = task.GetType().GetProperty("Result").GetValue(task, null);
    try {
      object input = stream.GetType().GetMethod("GetInputStreamAt").Invoke(stream, new object[] { 0UL });
      using (Stream net = (Stream)asStreamForReadMethod.Invoke(null, new object[] { input }))
      using (var mem = new MemoryStream()) {
        net.CopyTo(mem);
        return mem.ToArray();
      }
    } finally {
      Close(stream);
    }
  }

  static void Close(object instance) {
    IDisposable disposable = instance as IDisposable;
    if (disposable != null) disposable.Dispose();
  }

  public static void Beep() {
    Console.Beep();
  }

  public static void Beep(int frequency, int duration) {
    Console.Beep(frequency, duration);
  }

  public static void PlaySound(string soundName) {
    var property = typeof(System.Media.SystemSounds).GetProperty(
      soundName,
      System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.IgnoreCase);
    if (property != null) {
      var sound = (System.Media.SystemSound)property.GetValue(null, null);
      sound.Play();
      return;
    }

    string path = FindSchemeSound(soundName);
    if (path == null) {
      throw new ArgumentException("Unknown system sound: " + soundName);
    }
    if (path.Length == 0 || !System.IO.File.Exists(path)) {
      throw new ArgumentException("No sound file is assigned to: " + soundName);
    }
    PlaySoundFile(path);
  }

  [DllImport("winmm.dll", CharSet = CharSet.Auto)]
  static extern int mciSendString(string command, StringBuilder buffer, int bufferSize, IntPtr hwndCallback);

  public static void PlaySoundFile(string filePath) {
    if (string.IsNullOrEmpty(filePath) || !System.IO.File.Exists(filePath)) {
      throw new ArgumentException("Sound file not found: " + filePath);
    }
    if (string.Equals(System.IO.Path.GetExtension(filePath), ".mp3", StringComparison.OrdinalIgnoreCase)) {
      PlayMp3(filePath);
      return;
    }
    using (var player = new System.Media.SoundPlayer(filePath)) {
      player.PlaySync();
    }
  }

  static void PlayMp3(string filePath) {
    var buffer = new StringBuilder(512);
    string alias = "mp3clip";
    int openCode = mciSendString("open \"" + filePath + "\" type mpegvideo alias " + alias, buffer, buffer.Capacity, IntPtr.Zero);
    if (openCode != 0) {
      throw new InvalidOperationException("Could not open mp3 (" + openCode + "): " + filePath);
    }
    try {
      buffer.Length = 0;
      int playCode = mciSendString("play " + alias + " wait", buffer, buffer.Capacity, IntPtr.Zero);
      if (playCode != 0) {
        throw new InvalidOperationException("Could not play mp3 (" + playCode + "): " + filePath);
      }
    } finally {
      buffer.Length = 0;
      mciSendString("close " + alias, buffer, buffer.Capacity, IntPtr.Zero);
    }
  }

  static string FindSchemeSound(string soundName) {
    string eventName = null;
    using (var labels = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"AppEvents\EventLabels")) {
      if (labels == null) return null;
      foreach (string name in labels.GetSubKeyNames()) {
        using (var labelKey = labels.OpenSubKey(name)) {
          string display = labelKey.GetValue("") as string;
          if (string.Equals(display, soundName, StringComparison.OrdinalIgnoreCase)) {
            eventName = name;
            break;
          }
        }
      }
    }
    if (eventName == null) return null;

    using (var apps = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"AppEvents\Schemes\Apps")) {
      if (apps == null) return "";
      string preferred = ReadEventSound(apps, ".Default", eventName);
      if (!string.IsNullOrEmpty(preferred)) return preferred;
      foreach (string appName in apps.GetSubKeyNames()) {
        string path = ReadEventSound(apps, appName, eventName);
        if (!string.IsNullOrEmpty(path)) return path;
      }
    }
    return "";
  }

  static string ReadEventSound(Microsoft.Win32.RegistryKey apps, string appName, string eventName) {
    using (var current = apps.OpenSubKey(appName + "\\" + eventName + "\\.Current")) {
      if (current == null) return null;
      return current.GetValue("") as string;
    }
  }
}
"@ -ReferencedAssemblies System.Runtime.WindowsRuntime
