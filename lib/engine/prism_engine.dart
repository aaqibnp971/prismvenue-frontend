/// The app's view of the Prism sound engine.
///
/// Deliberately narrow: the app should not know about PSV dimensions, scenes,
/// stems or FFI. It knows four things — start, play this mood, go silent, come
/// back — and everything else is the engine's business.
///
/// ## Why this is an interface with two implementations
///
/// The engine is a native C++ library reached through `dart:ffi`, and **web has
/// no `dart:ffi`**. Importing the bindings unconditionally would break the web
/// build at compile time, not runtime — so the real implementation is pulled in
/// through a conditional import and web gets a silent no-op instead.
///
/// That is not a workaround, it is the honest shape of the problem: the app is
/// developed and demoed in Chrome, where native audio cannot exist, and ships to
/// an iPad, where it can. Both have to compile from one source tree.
library;

import 'prism_engine_stub.dart'
    if (dart.library.ffi) 'prism_engine_native.dart' as impl;
import 'weather_influence.dart';

/// How the engine reports itself to the UI, so "no sound" is never a mystery.
enum EngineStatus {
  /// Nothing attempted yet.
  idle,

  /// Extracting stems / loading the native library.
  starting,

  /// Rendering audio.
  playing,

  /// Deliberately silent — takeover, or the room is paused.
  silenced,

  /// This build cannot host the engine at all (web). Not an error; a fact.
  unsupported,

  /// Something went wrong; see [PrismEngine.lastError].
  failed,
}

abstract class PrismEngine {
  /// Creates the right implementation for this platform: the real FFI engine
  /// where `dart:ffi` exists, a no-op where it does not.
  factory PrismEngine() = impl.PlatformPrismEngine;

  EngineStatus get status;

  /// Human-readable reason [status] is [EngineStatus.failed] or
  /// [EngineStatus.unsupported]. Null otherwise.
  String? get lastError;

  /// Notifies on any [status] change so the UI can surface it.
  Stream<EngineStatus> get statusChanges;

  /// Prepares the engine and begins rendering. Safe to call more than once.
  ///
  /// Never throws: a venue dashboard must keep working when audio does not, so
  /// failures land in [status]/[lastError] rather than breaking the app.
  Future<void> start();

  /// Plays [moodId] — one of the six ids in `theme/moods.dart`.
  ///
  /// Unknown ids are ignored rather than defaulting, because a silent default
  /// means a room quietly playing the wrong thing.
  ///
  /// [transition] is how long the room takes to ease from the current vibe to
  /// this one — `Guardrails.transitionDuration`, i.e. the Seamless / Gentle /
  /// Lively setting. [alignToBar] lets the change wait for the outgoing music's
  /// next loop boundary so nothing is cut mid-phrase.
  ///
  /// Both are nullable rather than defaulted on purpose: a default here would
  /// have to be repeated by every implementation (Dart requires it of
  /// implementers), and the value actually used would then come from whichever
  /// class happened to run — a divergence nothing would catch. Null means "the
  /// engine's own default", resolved in one place.
  Future<void> setMood(String moodId, {Duration? transition, bool? alignToBar});

  /// Folds an environmental signal into the pinned mood.
  ///
  /// The room keeps playing whatever mood it is playing; this only changes how
  /// that mood sounds — see `weather_influence.dart` for what the numbers mean
  /// and why they are as small as they are.
  ///
  /// Separate from [setMood] because the two change independently and at very
  /// different rates. Weather moves on a 15-minute timer while the mood stays
  /// put, and routing it through [setMood] would either be ignored (that method
  /// returns early when the mood has not changed) or trigger a pointless scene
  /// crossfade — up to 60 seconds of the room easing into the mood it is
  /// already playing.
  ///
  /// Applied to the current mood immediately if one is playing, and remembered
  /// for the next one either way. Idempotent, and cheap: it publishes a PSV,
  /// which the engine ramps into like any other change. Nothing steps and no
  /// audio is reloaded.
  Future<void> applyInfluence(PsvNudge nudge);

  /// Smoothed level of what the engine is emitting, 0–1, or null when it is not
  /// playing.
  ///
  /// **Not room noise.** prism-core has no capture path and no microphone; this
  /// is Prism's own output, measured after the limiter. The UI must label it as
  /// such — the Floor hero's meter says "Output" for exactly this reason.
  ///
  /// Null rather than 0 when silent, stopped or unsupported: the engine holds
  /// its last reading when nothing is pulling audio, and a stale number is
  /// worse than an honest blank. `NoiseMeter` already renders null as an empty
  /// track and a dash.
  double? get outputLevel;

  /// Stops rendering so someone else can own the speakers. This is what
  /// Takeover calls, and what Pause calls. Idempotent.
  Future<void> silence();

  /// Resumes rendering after [silence]. Idempotent.
  Future<void> resume();

  Future<void> dispose();
}
