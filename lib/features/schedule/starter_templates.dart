import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/schedule_entry.dart';
import '../../data/repositories/schedule_repo.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/prism_toast.dart';
import '../../theme/moods.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// Starter plans, offered on a week that has none — finding #11.
///
/// ## Why a template rather than a better empty state
///
/// The finding's number is thirty-five saves. Multi-day selection and
/// "Copy day to…" cut that a long way, but both still start from nothing, and
/// the hardest part of a weekly plan is not the typing — it is deciding what
/// the day should sound like at all. A venue that has just been added has an
/// owner staring at an empty grid with six mood names they have never heard.
///
/// A template is one tap to a whole week that is roughly right, which is a
/// much better place to start editing than blank. Every block is an ordinary
/// daypart afterwards, editable and deletable like any other — nothing here is
/// a mode or a special row.
///
/// ## Where the shapes come from
///
/// The three named in the finding: clinic, café, retail. The hours are the
/// obvious ones for each, and the moods are chosen from the six that exist by
/// what each part of the day is for — not tuned by ear, because nobody has
/// heard these rooms. They are a starting point that says so in the copy.
///
/// ## What it deliberately does not do
///
/// It does not consult the venue's open hours. It could, and the temptation is
/// strong, but a template that silently reshapes itself is one nobody can
/// predict from its name, and the blocks are visible and draggable the moment
/// they land. Saying "Mon–Fri, 8am–6pm" and meaning it is worth more than
/// being clever.
class StarterTemplate {
  const StarterTemplate({
    required this.id,
    required this.name,
    required this.summary,
    required this.blocks,
  });

  final String id;
  final String name;

  /// One line under the name, describing the week in words.
  final String summary;

  /// (dayIndex, startHour, endHour, moodId).
  final List<(int, int, int, String)> blocks;

  List<Daypart> toDayparts() => [
        for (final (day, start, end, mood) in blocks)
          Daypart(
            id: '',
            dayIndex: day,
            startHour: start,
            endHour: end,
            moodId: mood,
          ),
      ];
}

/// Monday–Friday, with the same shape each weekday.
List<(int, int, int, String)> _weekdays(List<(int, int, String)> day) => [
      for (var d = 0; d < 5; d++)
        for (final (start, end, mood) in day) (d, start, end, mood),
    ];

/// Every day of the week, same shape.
List<(int, int, int, String)> _everyDay(List<(int, int, String)> day) => [
      for (var d = 0; d < 7; d++)
        for (final (start, end, mood) in day) (d, start, end, mood),
    ];

/// Built rather than const because the day loops are functions. Kept in one
/// list so the picker and any test see the same three.
/// Whether the starter plans can be offered to a room whose moods are
/// [offered].
///
/// The templates are written in the six built-in moods. A room with a
/// catalogue of its own has none of them, and a starter plan there would be
/// seven days of rows the database refuses (migration 023) — so the picker is
/// simply not shown, and the manager gets the empty grid and "+ Add".
bool starterTemplatesFit(Iterable<Mood> offered) {
  final ids = {for (final m in offered) m.id};
  return starterTemplates
      .every((t) => t.blocks.every((b) => ids.contains(b.$4)));
}

final starterTemplates = <StarterTemplate>[
  StarterTemplate(
    id: 'clinic',
    name: 'Clinic',
    summary: 'Mon–Fri, 8am–6pm. Calm in the morning, quiet by the end.',
    blocks: _weekdays(const [
      (8, 12, 'morning-calm'),
      (12, 15, 'daytime-flow'),
      (15, 18, 'wind-down'),
    ]),
  ),
  StarterTemplate(
    id: 'cafe',
    name: 'Café',
    summary: 'Every day, 7am–11pm. Lifts through the afternoon, warm at night.',
    blocks: _everyDay(const [
      (7, 11, 'morning-calm'),
      (11, 15, 'daytime-flow'),
      (15, 18, 'afternoon-lift'),
      (18, 22, 'evening-warmth'),
      (22, 23, 'wind-down'),
    ]),
  ),
  StarterTemplate(
    id: 'retail',
    name: 'Retail',
    summary: 'Every day, 10am–8pm. Steady, with a lift over the busy hours.',
    blocks: _everyDay(const [
      (10, 13, 'daytime-flow'),
      (13, 17, 'afternoon-lift'),
      (17, 20, 'evening-warmth'),
    ]),
  ),
];

/// The empty-week state: three starter plans, or a plain line when the manager
/// would rather build their own.
class StarterTemplatePicker extends ConsumerStatefulWidget {
  const StarterTemplatePicker({super.key, required this.weekStart});

  final DateTime weekStart;

  @override
  ConsumerState<StarterTemplatePicker> createState() =>
      _StarterTemplatePickerState();
}

class _StarterTemplatePickerState extends ConsumerState<StarterTemplatePicker> {
  /// Which template is being written, or null. One at a time, because two
  /// templates landing together would interleave into a plan nobody chose.
  String? _applying;

  Future<void> _apply(StarterTemplate template) async {
    setState(() => _applying = template.id);
    try {
      // Every block onto the recurring plan, not this week's fork: a starter
      // plan is what the venue does every week, and a template that only
      // applied to the week on screen would be a fork nobody asked for.
      await ref.read(scheduleRepoProvider).addDayparts(template.toDayparts());
      if (mounted) showPrismToast(context, '${template.name} plan added');
    } catch (e) {
      if (mounted) showPrismError(context, e);
    } finally {
      if (mounted) setState(() => _applying = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No plan yet',
                  style: PrismType.body.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary)),
              const SizedBox(height: 7),
              Text(
                'Start from one of these and change whatever does not fit, or '
                'add blocks yourself with + Add.',
                textAlign: TextAlign.center,
                style: PrismType.meta
                    .copyWith(fontSize: 11.5, color: palette.textSecondary),
              ),
              const SizedBox(height: 16),
              for (final template in starterTemplates) ...[
                _TemplateCard(
                  template: template,
                  busy: _applying == template.id,
                  // Inert while another one is being written, rather than
                  // hidden: a card that vanishes under the finger is worse
                  // than one that waits.
                  onTap: _applying != null ? null : () => _apply(template),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.busy,
    required this.onTap,
  });

  final StarterTemplate template;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final brightness = Theme.of(context).brightness;
    final moodIds = <String>{for (final b in template.blocks) b.$4};

    return Semantics(
      button: true,
      label: '${template.name} starter plan. ${template.summary}',
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null && !busy ? 0.4 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(busy ? 'Adding ${template.name}…' : template.name,
                          style: PrismType.bodySm.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary)),
                      const SizedBox(height: 3),
                      Text(template.summary,
                          style: PrismType.meta.copyWith(
                              fontSize: 11, color: palette.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // The moods it uses, as dots. The names mean little to someone
                // new; the colours are what they will see in the grid.
                for (final id in moodIds) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: moodById(id).dot(brightness),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
