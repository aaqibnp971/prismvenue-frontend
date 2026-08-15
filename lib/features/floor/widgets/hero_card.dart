import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../data/models/playback_state.dart';
import '../../../shared/widgets/auto_button.dart';
import '../../../shared/widgets/noise_meter.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/take_over_button.dart';
import '../../../theme/moods.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';

/// Floor hero — §2 S01-1: bg `surface`, border, r14, padding 24×22 (v×h),
/// row gap 20. Pause button 64 circle accent (white icon 20; play icon while
/// paused, S01-2). Center: "NOW PLAYING" caps → mood row (wrap, gap 9: dot
/// 11, name 31 italic serif, pill, context 10.5) → noise row mt10.
/// Right: Take over.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.state,
    required this.noise,
    this.noiseLabel = 'Noise',
    this.takeoverActive = false,
    this.takeOverLabel = 'Take over',
    this.hasPlanToday = true,
    this.onTogglePause,
    this.onTakeOver,
    this.onReturnToAuto,
    this.contextFallback,
  });

  final PlaybackState state;

  /// Shown in place of [PlaybackState.contextLine] while the server has none.
  ///
  /// The server's line is authoritative and always wins — it is pre-formatted
  /// and rendered verbatim, and when telemetry ingest lands it will carry the
  /// occupancy and noise segments no client can know. But nothing writes it
  /// today, so the slot has been permanently blank.
  ///
  /// The designed example is "mid-afternoon · ~60% full · clear" — that last
  /// segment is a weather word, so putting the venue's sky here is filling in
  /// the slot as specified rather than inventing a surface. It is also the only
  /// thing that makes the weather influence visible: without it, the feature
  /// changes the sound and nothing on screen explains why.
  final String? contextFallback;
  /// 0–100, or null when nothing has reported. Null renders an empty track and
  /// a dash rather than inventing a plausible number — see [NoiseMeter].
  final int? noise;

  /// What [noise] is measuring. The Floor screen passes "Output" because it
  /// feeds the engine's own level; the default keeps the designed "Noise"
  /// reading for anything showing real room telemetry.
  final String noiseLabel;

  /// Staff are driving the speakers, so Prism is producing no sound at all.
  ///
  /// The Floor screen used to signal this only by hiding "Return to Auto",
  /// which reads as a missing button rather than as a state. Everything else
  /// on the card carried on as normal — a mood name, a "Playing" badge, an
  /// off-schedule pill — over a room Prism had handed off. This makes the
  /// state legible where the user is actually looking.
  final bool takeoverActive;

  /// Label for the S02 button — see [TakeOverButton.label].
  final String takeOverLabel;

  /// Whether Auto has a schedule to return to — see [AutoButton.hasPlan].
  final bool hasPlanToday;
  final VoidCallback? onTogglePause;
  final VoidCallback? onTakeOver;

  /// Hands the room back to the schedule. Null hides the control — the Floor
  /// screen passes null during a takeover, where S02 already owns the hand-back
  /// and two competing controls would be exactly the dashboard/speaker
  /// disagreement the engine seam exists to prevent.
  final VoidCallback? onReturnToAuto;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final mood = moodById(state.moodId);

    // S01-1 pill: "Prism is driving" (accentSoft). S01-2 swaps it for an
    // amber-tinted "Paused by **Priya** · tap play to resume".
    //
    // Takeover outranks both, because it is the only one of the three where
    // Prism is not producing sound at all. Until this existed the Floor screen
    // said nothing about a takeover — the sole tell was the Auto button
    // quietly disappearing, so a room handed off half an hour ago read as
    // "Off schedule · you chose this vibe" beside a silent output meter, and
    // the honest conclusion was that the app was broken.
    final pill = takeoverActive
        ? const StatusPill(
            text: 'Staff have the room · Prism is handed off',
            tone: PillTone.amber)
        : state.paused
        ? StatusPill(
            text: 'Paused by ${state.pausedBy} · tap play to resume',
            tone: PillTone.amber,
            span: TextSpan(
              text: 'Paused by ',
              children: [
                TextSpan(
                    text: state.pausedBy ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const TextSpan(text: ' · tap play to resume'),
              ],
            ),
          )
        : state.offSchedule
            // Someone chose this vibe, so "Prism is driving" would be a lie —
            // and it is the lie that hides the fact the schedule is not running.
            ? const StatusPill(
                text: 'Off schedule · you chose this vibe', tone: PillTone.amber)
            : const StatusPill(text: 'Prism is driving', dot: true);

    // The two controls together want ~260px. On a phone that leaves the mood
    // name a column barely wider than one word ("Mor / ning / calm"), so below
    // this width they move to their own row underneath instead of competing
    // with the content for the same line.
    // Left of "Take over", so the pair reads left-to-right as "Prism drives"
    // → "I drive". Hidden during a takeover for the same reason the old link
    // was: S02 owns the hand-back there.
    //
    // [stretch] is the stacked case: on their own row the two share the width
    // rather than sitting at their natural size, which at phone widths is
    // wider than the card.
    List<Widget> actions({required bool stretch}) {
      Widget fit(Widget button) =>
          stretch ? Expanded(child: button) : button;
      return [
        if (onReturnToAuto != null) ...[
          fit(AutoButton(
              active: !state.offSchedule,
              hasPlan: hasPlanToday,
              onTap: onReturnToAuto)),
          const SizedBox(width: 10),
        ],
        fit(TakeOverButton(onTap: onTakeOver, label: takeOverLabel)),
      ];
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 22),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 640;
          final content = _content(context, palette, mood, pill);

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                const SizedBox(height: 18),
                Row(children: actions(stretch: true)),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 20),
              ...actions(stretch: false),
            ],
          );
        },
      ),
    );
  }

  Widget _content(
      BuildContext context, PrismPalette palette, Mood mood, Widget pill) {
    return Row(
        children: [
          GestureDetector(
            onTap: onTogglePause,
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: palette.accent, shape: BoxShape.circle),
              child: Icon(
                state.paused ? LucideIcons.play : LucideIcons.pause,
                size: 20,
                color: const Color(0xFFFFFFFF),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NOW PLAYING',
                    style: PrismType.labelCaps
                        .copyWith(color: palette.textSecondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: mood.dot(palette.brightness),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(mood.name,
                        style: PrismType.moodNameHero
                            .copyWith(color: palette.textPrimary)),
                    pill,
                    // The hand-back used to live here as a small "Back to Auto"
                    // link, visible only once the room was already overridden.
                    // It is now the standing AutoButton beside "Take over" —
                    // staff could not discover "just follow the schedule"
                    // without first overriding to make the link appear.
                    Text(
                        state.contextLine.isNotEmpty
                            ? state.contextLine
                            : (contextFallback ?? ''),
                        style: PrismType.microHelper
                            .copyWith(color: palette.textSecondary)),
                  ],
                ),
                const SizedBox(height: 10),
                // "Output", not "Noise": this is Prism's own level after the
                // limiter, not room loudness. reported_noise_pct is the room
                // measurement and nothing writes it — there is no ingest and no
                // microphone in the system — so showing it would be a permanent
                // dash. See lib/engine/engine_controller.dart.
                NoiseMeter(value: noise, label: noiseLabel),
              ],
            ),
          ),
        ],
    );
  }
}
