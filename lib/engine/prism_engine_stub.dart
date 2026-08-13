/// The engine on platforms that cannot host it — in practice, web.
///
/// Flutter web has no `dart:ffi`, so a native library cannot be loaded at all.
/// This is a hard platform limit, not a missing feature: no amount of wiring
/// makes Chrome play the engine. (A WebAssembly build of prism-core would, but
/// that is a different toolchain and a different binding layer.)
///
/// So the app runs fully in Chrome — zones, schedules, takeover, settings — and
/// is simply silent there. Every call below succeeds and does nothing, which
/// keeps the calling code free of `if (kIsWeb)` branches, and [status] reports
/// [EngineStatus.unsupported] so the UI can say WHY rather than looking broken.
library;

import 'dart:async';

import 'prism_engine.dart';
import 'weather_influence.dart';

class PlatformPrismEngine implements PrismEngine {
  final _status = StreamController<EngineStatus>.broadcast();

  @override
  EngineStatus get status => EngineStatus.unsupported;

  @override
  String? get lastError =>
      'Audio needs a native build. This is the web build, which cannot load '
      'the engine — run the app on iPad, Android or desktop to hear it.';

  @override
  Stream<EngineStatus> get statusChanges => _status.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> setMood(String moodId, {Duration? transition, bool? alignToBar}) async {}

  @override
  Future<void> applyInfluence(PsvNudge nudge) async {}

  @override
  Future<void> silence() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> dispose() async {
    await _status.close();
  }
}
