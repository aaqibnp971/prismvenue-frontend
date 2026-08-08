import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/session.dart';
import '../../app/venue_header.dart';
import '../../data/repositories/playback_repo.dart';
import '../../data/repositories/schedule_repo.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../shared/widgets/schedule_rail.dart';
import '../../theme/moods.dart';
import 'widgets/confirm_auto_dialog.dart';
import 'widgets/confirm_vibe_dialog.dart';
import 'widgets/hero_card.dart';
import 'widgets/mood_grid.dart';

/// S01 Floor — THE floor-staff home (all roles). Body = row: main column
/// (padding 15, gap 20: hero card + moods block) + schedule rail (w268
/// fixed). Landscape layout; portrait reflow is Phase 4 (§6-A1).
///
/// Edges (§4): tile tap → confirm-vibe dialog → floor · "Take over" →
/// /takeover · paused-state ⇄ default via the hero button.
class FloorScreen extends ConsumerWidget {
  const FloorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final playback = ref.watch(nowPlayingProvider);
    final noise = ref.watch(noiseProvider);
    final takeover = ref.watch(takeoverStateProvider);
    final schedule = ref.watch(todayScheduleProvider);
    final header = ref.watch(venueHeaderProvider);
    if (user == null) return const SizedBox.shrink(); // router redirects

    return Scaffold(
      body: Column(
        children: [
          PrismTopBar(
            title: header.title,
            subtitle: header.subtitle,
            statusDot: header.statusDot,
            user: user,
          ),
          Expanded(
            // §6-A1: portrait keeps the same structure; the rail moves below
            // the mood grid as a horizontal strip (breakpoint derived —
            // exact iPad breakpoints are §6-B2).
            child: LayoutBuilder(
              builder: (context, constraints) {
                // iPad portrait bodies run 744–834 wide; landscape ≥1024.
                final portrait = constraints.maxWidth < 900;

                final main = playback.when(
                  // These were both SizedBox.shrink(), on the grounds that the
                  // mock emits synchronously so they are transient. That
                  // stopped being true the moment the real API landed: a
                  // failure painted an empty screen with a nav bar, no message
                  // and no way to retry.
                  loading: () => const SizedBox(
                      height: 260, child: LoadingState()),
                  error: (e, st) => SizedBox(
                    height: 260,
                    child: ErrorState(
                      error: e,
                      onRetry: () => ref.invalidate(nowPlayingProvider),
                    ),
                  ),
                  data: (state) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HeroCard(
                        state: state,
                        // Null, not 62. That fallback was a frame sample value
                        // rendered as live telemetry, so a zone whose sensor
                        // had never reported showed a confident 62%.
                        noise: noise.value,
                        onTogglePause: () async {
                          final repo = ref.read(playbackRepoProvider);
                          try {
                            if (state.paused) {
                              await repo.resume();
                            } else {
                              await repo.pause(by: user.name.split(' ').first);
                            }
                          } catch (e) {
                            // Without this the request fails and the room
                            // simply carries on playing, with nothing on
                            // screen to say why.
                            if (context.mounted) showPrismError(context, e);
                          }
                        },
                        // Hidden during a takeover: S02 already owns the
                        // hand-back ("Return to Prism now"), and two competing
                        // controls for the same room is how the dashboard and
                        // the speakers end up disagreeing.
                        onReturnToAuto: takeover.value?.active == true
                            ? null
                            : () async {
                                final confirmed =
                                    await showConfirmAutoDialog(context);
                                if (confirmed != true) return;
                                try {
                                  await ref
                                      .read(playbackRepoProvider)
                                      .returnToAuto();
                                } catch (e) {
                                  if (context.mounted) {
                                    showPrismError(context, e);
                                  }
                                }
                              },
                        onTakeOver: () => context.go('/takeover'),
                      ),
                      const SizedBox(height: 20),
                      MoodGrid(
                        currentMoodId: state.moodId,
                        paused: state.paused,
                        onMoodTap: (mood) =>
                            _onMoodTap(context, ref, mood, state.moodId),
                      ),
                    ],
                  ),
                );

                if (portrait) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        main,
                        const SizedBox(height: 20),
                        schedule.when(
                          loading: () => const SizedBox.shrink(),
                          error: (e, st) => const SizedBox.shrink(),
                          data: (today) => ScheduleRail(
                            entries: today.entries,
                            nowIndex: today.nowIndex,
                            selfDrive: today.selfDrive,
                            offSchedule:
                                playback.value?.offSchedule ?? false,
                            horizontal: true,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(15),
                        child: main,
                      ),
                    ),
                    schedule.when(
                      loading: () => const SizedBox(width: 268),
                      error: (e, st) => const SizedBox(width: 268),
                      data: (today) => ScheduleRail(
                            entries: today.entries,
                            nowIndex: today.nowIndex,
                            selfDrive: today.selfDrive,
                            offSchedule:
                                playback.value?.offSchedule ?? false,
                          ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMoodTap(BuildContext context, WidgetRef ref, Mood mood,
      String currentMoodId) async {
    if (mood.id == currentMoodId) return; // tapping the playing tile is inert
    final confirmed = await showConfirmVibeDialog(context, mood: mood);
    if (confirmed != true) return;
    try {
      await ref.read(playbackRepoProvider).setMood(mood.id);
    } catch (e) {
      if (context.mounted) showPrismError(context, e);
    }
  }
}
