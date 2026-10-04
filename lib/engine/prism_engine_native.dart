/// The engine on platforms with `dart:ffi` — iPad, Android, Windows, macOS.
///
/// Wraps `prism_core_bindings` and adds the two things a Flutter app needs that
/// the bindings deliberately do not provide:
///
/// 1. **Assets become files.** The C ABI takes a filesystem PATH to a scene
///    manifest and resolves stems relative to it. Flutter assets are not files
///    on device — they live inside the app bundle — so they are copied once
///    into the app-support directory and the engine is pointed there.
///
/// 2. **Mood means scene.** Each of the six moods has its own manifest with its
///    own stems, so switching mood means loading a different scene.
///
/// ## How a mood change reaches the speakers
///
/// A scene is bound to a handle for that handle's whole life: `prism_load_scene`
/// is rejected once a scene is loaded — not merely after `prism_start`, and
/// `prism_stop` does not clear it. So there is no reload-in-place, and for a
/// while the only way to reach another scene was to dispose the handle and build
/// a new one. That is where the audible gap came from: the room went silent
/// while the new stems decoded.
///
/// `prism_crossfade_scene` (ABI 0.3) is the door that fixes it. The engine holds
/// BOTH scenes and equal-power fades between them at a loop boundary, so the
/// room never drops out. Only the first mood of a session builds a handle; every
/// one after it crossfades in place.
///
/// The overlap length is the venue's Seamless / Gentle / Lively setting, passed
/// down as [setMood]'s `transition`. Lively also turns off bar alignment: with
/// 16-second loops the wait for a boundary can exceed the fade itself, which
/// reads as the app ignoring the tap.
///
/// The alternative once considered — one shared scene for all six moods,
/// switched purely by pinning the PSV — would also have been seamless, but much
/// less distinct: measured on a single scene the loudest and quietest moods land
/// within ~2.6 dB, because most of what separates the six is their different
/// stem sets. Holding two scenes keeps both properties.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:prism_core_bindings/prism_core_bindings.dart';

import '../theme/moods.dart';
import 'prism_engine.dart';
import 'weather_influence.dart';

/// Where the bundled scenes live in the asset tree.
const _assetDir = 'assets/audio';

class PlatformPrismEngine implements PrismEngine {
  PrismCore? _core;
  Directory? _sceneDir;

  /// What the engine is actually playing.
  String? _currentMood;

  /// What the app most recently asked for. Differs from [_currentMood] only while a
  /// change is queued or waiting out a transition; a queued request that no longer
  /// matches this has been superseded and is dropped.
  String? _desiredMood;

  bool _silenced = false;

  /// The room is meant to be on a mood this device cannot play, and is silent
  /// because of it. Cleared by the next mood that does load. While set, the
  /// device stays stopped whatever [resume] is told — see [_failClosed].
  String? _unavailableReason;

  /// The environmental adjustment folded into every pin. Neutral until the host
  /// has a weather reading, and neutral again the moment it loses one — so a
  /// dropped network returns the room to the plain preset rather than freezing
  /// it on the last sky it saw.
  PsvNudge _nudge = PsvNudge.none;

  /// The preset for [_currentMood], kept so an influence change can re-pin
  /// without re-deriving it or touching the scene.
  VenueMood? _currentPreset;

  /// Mirrors the core's device state. `prism_device_start` returns
  /// INVALID_STATE when the device is already running, and the controller
  /// legitimately reaches resume() straight after setMood() has already
  /// started it — so the app tracks this rather than letting a benign
  /// double-start mark the whole engine failed.
  bool _deviceRunning = false;

  EngineStatus _status = EngineStatus.idle;
  String? _lastError;
  final _statusController = StreamController<EngineStatus>.broadcast();

  /// Serialises engine work. Mood taps can arrive faster than a scene loads,
  /// and overlapping stop/load/start sequences would corrupt the lifecycle.
  Future<void> _queue = Future.value();

  @override
  EngineStatus get status => _status;

  @override
  String? get lastError => _lastError;

  @override
  Stream<EngineStatus> get statusChanges => _statusController.stream;

  void _setStatus(EngineStatus s, [String? error]) {
    _lastError = error;
    if (_status == s) return;
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  /// Runs [action] after everything already queued, swallowing failures into
  /// [status]. The dashboard must keep working when audio does not.
  Future<void> _serialise(String what, Future<void> Function() action) {
    final next = _queue.then((_) async {
      try {
        await action();
      } catch (e) {
        _setStatus(EngineStatus.failed, '$what failed: $e');
        debugPrint('prism engine: $what failed: $e');
      }
    });
    // Keep the chain alive even if a link failed, or every later call hangs.
    _queue = next.catchError((_) {});
    return next;
  }

  @override
  Future<void> start() => _serialise('start', () async {
        if (_sceneDir != null) return;
        _setStatus(EngineStatus.starting);
        _sceneDir = await _extractScenes();
        // No core yet: the first setMood builds one around its scene. Creating
        // one here would only have to be torn down again — see setMood.
      });

  @override
  Future<void> setMood(Mood mood, {Duration? transition, bool? alignToBar}) {
    final moodId = mood.id;
    // Recorded OUTSIDE the queue, so it is already true when a later tap is queued
    // behind an earlier one. Everything below treats it as the single answer to
    // "what should the room be playing?".
    _desiredMood = moodId;
    return _serialise('setMood($moodId)', () async {
        // Superseded while queued — a manager tapped twice and only the last one
        // is still wanted. Applying this would put the room on a mood the
        // dashboard has already moved past.
        if (_desiredMood != moodId) return;

        // No catalogue has this mood. It used to be ignored, which left the
        // room on whatever it was playing before — the wrong thing, quietly.
        if (!mood.known) {
          _failClosed('This room is set to a mood ("$moodId") this device '
              'does not have. Nothing is playing.');
          return;
        }
        if (moodId == _currentMood && _core != null) return;

        final sceneDir = _sceneDir;
        if (sceneDir == null) return; // start() not called, or it failed

        final scenePath = scenePathFor(sceneDir.path, mood.sceneManifest);
        if (scenePath == null || !File(scenePath).existsSync()) {
          _failClosed('The audio for ${mood.name} is not installed on this '
              'device. Nothing is playing.');
          return;
        }

        final preset = presetFor(mood);

        // Anything that goes wrong loading this mood's audio — a stem the
        // manifest names and the device does not have, a file that will not
        // decode — ends the same way as a missing manifest: silence, and a
        // reason. Without this the failure surfaced as a status while the
        // PREVIOUS mood went on playing, which is a substitution in all but
        // name.
        try {
          await _switchTo(_core, scenePath, preset, moodId,
              transition: transition, alignToBar: alignToBar);
        } catch (e) {
          debugPrint('prism engine: setMood($moodId) failed: $e');
          _failClosed('The audio for ${mood.name} could not be loaded on this '
              'device. Nothing is playing.');
        }
      });
  }

  /// Puts the room on [scenePath] pinned to [mood]: builds the first handle of
  /// a session, or crossfades from the scene already playing.
  Future<void> _switchTo(
    PrismCore? core,
    String scenePath,
    VenueMood mood,
    String moodId, {
    Duration? transition,
    bool? alignToBar,
  }) async {
        // The first mood of a session has nothing to fade from, so it builds the
        // handle. Every mood after it crossfades in place.
        if (core == null) {
          _buildCore(scenePath, mood, moodId);
          _unavailableReason = null;
          return;
        }

        // Only one crossfade can run at a time, and a transition is long — up to
        // 60 s on Seamless — so taps routinely arrive mid-fade. Wait for the one in
        // flight rather than dropping this one: the engine refuses a second
        // crossfade with BUSY, and simply logging that left the room on the old
        // mood while the dashboard showed the new one. That disagreement between
        // the speakers and the screen is the exact thing this seam exists to
        // prevent, so it is worth the wait.
        //
        // Re-checking supersession each time keeps it latest-wins: three quick taps
        // cost one transition to the last mood, not three in series.
        while (core.crossfadeActive) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (_desiredMood != moodId) return;
        }

        // Hold both scenes and ease between them. The room never drops out, which
        // is the whole difference from what this used to do: a scene is bound to
        // its handle for life, so the only other way to reach a new one is to
        // dispose the handle and rebuild — and that costs a silence while the new
        // stems decode.
        core.crossfadeScene(
          scenePath,
          crossfade: transition ?? const Duration(seconds: 35),
          alignToBar: alignToBar ?? true,
        );
        _pin(core, mood);
        _currentMood = moodId;
        _unavailableReason = null;
        if (_silenced) {
          // Coming back from [EngineStatus.unavailable] while paused or taken
          // over: the room is silent for the ordinary reason again.
          _setStatus(EngineStatus.silenced);
        } else {
          _deviceStart(core);
          _setStatus(EngineStatus.playing);
        }
  }

  /// Silences the room because what it should be playing cannot be played
  /// here, and says why.
  ///
  /// The device stops and stays stopped. [_currentMood] is cleared, so
  /// [resume] has nothing to resume and a later request for the same mood is
  /// tried again from scratch rather than skipped as "already playing".
  void _failClosed(String reason) {
    _unavailableReason = reason;
    _currentMood = null;
    _currentPreset = null;
    final core = _core;
    if (core != null) _deviceStop(core);
    _setStatus(EngineStatus.unavailable, reason);
    debugPrint('prism engine: silent on purpose — $reason');
  }

  /// Builds the first handle of a session around [scenePath]. Only reached when
  /// there is no engine yet — after that, moods crossfade.
  void _buildCore(String scenePath, VenueMood mood, String moodId) {
    final next = PrismCore.create(vertical: PrismVertical.venues);
    try {
      next.loadScene(scenePath);
      next.start();
      // Before the device opens, so a venue with a 10% band never hears one
      // moment of full-volume audio while the first scene loads.
      next.outputGain = _gainFor(_volumeMaxPct);
      _pin(next, mood);
    } catch (_) {
      next.dispose(); // never leak a half-built handle
      rethrow;
    }
    _core = next;
    _currentMood = moodId;

    if (_silenced) {
      _setStatus(EngineStatus.silenced);
    } else {
      _deviceStart(next);
      _setStatus(EngineStatus.playing);
    }
  }

  /// Publishes the PSV for [mood], with the current environmental adjustment
  /// folded in.
  ///
  /// The single place the vector is pinned, which is the point: weather has to
  /// reach the first mood of a session and every mood after it, and two call
  /// sites that each remembered to apply it would eventually become one that
  /// did and one that did not.
  ///
  /// The mood's `id` and `mode_hint` are untouched by [VenueMood.adjusted] —
  /// this is still Peak, just Peak on a wet night.
  void _pin(PrismCore core, VenueMood mood) {
    _currentPreset = mood;
    // setMoodOverride also hands the engine the mood's low-pass floor (ABI
    // 0.6), which is null for all six Default moods — see [moodToPin].
    core.setMoodOverride(moodToPin(mood, _nudge));
  }

  /// Prism's own output level, or null when nothing is being rendered.
  ///
  /// Deliberately null rather than 0 while silenced or stopped: the engine's
  /// meter is driven BY the render path, so with the device stopped it holds
  /// whatever it last read. Reporting that as a live level would be the same
  /// class of lie as the old hardcoded 62% noise value.
  ///
  /// Failures return null rather than throwing. A meter is decoration; it must
  /// not be able to take the dashboard down, and an older `prism_core.dll`
  /// without this symbol would otherwise throw on every poll.
  @override
  double? get outputLevel {
    final core = _core;
    if (core == null || _silenced || !_deviceRunning) return null;
    try {
      return core.outputLevel;
    } catch (_) {
      return null;
    }
  }

  /// The venue's volume ceiling, as an amplitude the engine can apply.
  ///
  /// Remembered even with no core yet, and re-applied by [_buildCore], so a
  /// venue whose band is 10% never gets one moment of full-volume audio while
  /// the first scene loads.
  int _volumeMaxPct = 100;

  @override
  Future<void> setVolumePolicy(int maxPct) =>
      _serialise('setVolumePolicy($maxPct)', () async {
        final clamped = maxPct.clamp(0, 100);
        if (clamped == _volumeMaxPct) return;
        _volumeMaxPct = clamped;
        _core?.outputGain = _gainFor(clamped);
      });

  /// Percentage → amplitude, on the same curve the engine uses for stems.
  ///
  /// `pgae`'s own `gain_to_amp` is `0.4 · x^1.5`, so the 1.5 exponent is this
  /// codebase's existing answer to "what does a loudness number mean". Reusing
  /// it keeps the band and the mix on one curve rather than inventing a second.
  /// Linear would make 50% sound far louder than half.
  static double _gainFor(int pct) => math.pow(pct / 100.0, 1.5).toDouble();

  @override
  Future<void> applyInfluence(PsvNudge nudge) =>
      _serialise('applyInfluence', () async {
        if (nudge.arousal == _nudge.arousal &&
            nudge.cognitiveLoad == _nudge.cognitiveLoad &&
            nudge.readiness == _nudge.readiness) {
          return;
        }
        _nudge = nudge;

        // Nothing playing yet: remembered above, applied by the next pin. This
        // is the common case at launch, where the weather fetch usually beats
        // the first now-playing frame.
        final core = _core;
        final preset = _currentPreset;
        if (core == null || preset == null) return;

        // Re-publish only. No scene work, no crossfade, no device restart —
        // the mood has not changed, only how it is rendered. The engine ramps
        // into the new vector (cutoff over 0.6 s, levels over 0.25 s), so a
        // sky that clouds over is heard as a slow settling rather than a step.
        _pin(core, preset);
      });

  /// Stops and destroys the current handle, if any, leaving the engine with no
  /// core. Safe to call repeatedly.
  void _teardownCore() {
    final core = _core;
    if (core == null) return;
    _core = null;
    _currentMood = null;
    _currentPreset = null;
    _deviceStop(core);
    core.stop();
    core.dispose();
  }

  void _deviceStart(PrismCore core) {
    if (_deviceRunning) return;
    core.deviceStart();
    _deviceRunning = true;
  }

  void _deviceStop(PrismCore core) {
    if (!_deviceRunning) return;
    core.deviceStop();
    _deviceRunning = false;
  }

  @override
  Future<void> silence() => _serialise('silence', () async {
        _silenced = true;
        final core = _core;
        if (core != null) _deviceStop(core);
        _setStatus(EngineStatus.silenced);
      });

  @override
  Future<void> resume() => _serialise('resume', () async {
        _silenced = false;
        // Still nothing playable. Pausing and resuming must not turn "this
        // room has no audio for its mood" into an ordinary-looking silence.
        final reason = _unavailableReason;
        if (reason != null) {
          _setStatus(EngineStatus.unavailable, reason);
          return;
        }
        final core = _core;
        if (core == null || _currentMood == null) return;
        _deviceStart(core);
        _setStatus(EngineStatus.playing);
      });

  @override
  Future<void> dispose() => _serialise('dispose', () async {
        _teardownCore();
        await _statusController.close();
      });

  /// Copies the bundled manifests and stems into a real directory once.
  ///
  /// Keyed by a manifest of what was written: if the app ships new stems, the
  /// marker no longer matches and everything is re-extracted. Without that, an
  /// update would silently keep playing the old audio.
  Future<Directory> _extractScenes() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/prism_scenes');

    final index = await rootBundle.loadString('$_assetDir/index.txt');
    final files = index
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();

    final marker = File('${dir.path}/.extracted');
    if (await marker.exists() && await marker.readAsString() == index) {
      return dir;
    }

    await dir.create(recursive: true);
    for (final rel in files) {
      final data = await rootBundle.load('$_assetDir/$rel');
      final out = File('${dir.path}/$rel');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    await marker.writeAsString(index, flush: true);
    return dir;
  }
}

/// Where [manifest] lives under [sceneDir], or null if it is not a plain
/// relative file name.
///
/// The name comes from the server. It may name a file inside the extracted
/// audio directory and nothing else: not an absolute path, not a drive, not a
/// way out through `..`. Refused names are treated exactly like a missing
/// file — the room fails closed.
@visibleForTesting
String? scenePathFor(String sceneDir, String manifest) {
  if (manifest.isEmpty ||
      manifest.contains('..') ||
      manifest.startsWith('/') ||
      manifest.contains(r'\') ||
      manifest.contains(':')) {
    return null;
  }
  return '$sceneDir/$manifest';
}

/// The engine preset for [mood]: its PSV, its mode hint and its low-pass floor.
///
/// Built from the row, not looked up by id — the bindings' own table knows
/// only the six built-in moods. For those six this produces exactly the values
/// `VenueMood.byId` holds (`test/built_in_moods_test.dart`), which is what
/// keeps every existing venue sounding as it did: same vector in, same samples
/// out. A null floor stays null.
@visibleForTesting
VenueMood presetFor(Mood mood) => VenueMood.fromData(
      id: mood.id,
      modeHint: mood.modeHint,
      arousal: mood.arousal,
      valence: mood.valence,
      cognitiveLoad: mood.cognitiveLoad,
      readiness: mood.readiness,
      lowpassFloorHz: mood.lowpassFloorHz,
    );

/// The vector the engine is actually handed for [mood] under [nudge].
///
/// A top-level function rather than a private method so it can be tested
/// without a native library: this is the last Dart value before the FFI boundary, and two
/// things about it are promises rather than details.
///
///   * A neutral nudge returns [mood] itself, not a copy — pinning a preset
///     plus [PsvNudge.none] is bit-identical to pinning the preset alone.
///   * The mood's `lowpassFloorHz` is never invented or dropped here. It is
///     null for every Default mood, and the engine's guarantee that those
///     moods sound exactly as before rests on that null reaching it.
@visibleForTesting
VenueMood moodToPin(VenueMood mood, PsvNudge nudge) => nudge.isNeutral
    ? mood
    : mood.adjusted(
        arousal: nudge.arousal,
        cognitiveLoad: nudge.cognitiveLoad,
        readiness: nudge.readiness,
      );
