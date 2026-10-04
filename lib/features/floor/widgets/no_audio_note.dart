import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/playback_repo.dart';
import '../../../engine/engine_controller.dart';
import '../../../engine/prism_engine.dart';
import '../../../shared/widgets/error_note.dart';

/// Why the room is quiet, when the reason is that its mood cannot be played on
/// this device.
///
/// The engine fails closed: a mood that is in no catalogue, or whose audio is
/// not installed here, silences the room rather than letting another mood
/// stand in for it ([EngineStatus.unavailable]). Silence with nothing on
/// screen is indistinguishable from a broken speaker, so this is the other
/// half of that rule — the reason, in the engine's own words.
///
/// Shown only on the device that plays the room. A phone being used as a
/// remote control is silent by design, and telling its owner that "nothing is
/// playing" would be describing the phone, not the room.
class NoAudioNote extends ConsumerWidget {
  const NoAudioNote({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(prismEngineProvider);
    // `statusChanges` only emits on CHANGE; the getter supplies the value for
    // a note built after the engine went quiet.
    final status = ref.watch(engineStatusProvider).value ?? engine.status;
    final playsHere = ref.watch(nowPlayingProvider).value?.playsHere ?? false;
    if (status != EngineStatus.unavailable || !playsHere) {
      return const SizedBox.shrink();
    }
    return ErrorNote(
      message: engine.lastError ??
          "This room's mood cannot be played on this device. "
              'Nothing is playing.',
    );
  }
}
