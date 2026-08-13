import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'error_note.dart';
import 'secondary_button.dart';

/// PLACEHOLDER — no full-screen error state was designed (§6-B1,
/// `open_questions.md`), so like [ErrorNote] this is built from existing
/// palette and type tokens only, and replacing it with the designed treatment
/// is a change in one file.
///
/// The third surface, alongside the inline note and the transient snackbar:
/// what a screen shows when the thing it exists to display could not be
/// fetched at all.
///
/// It exists because Floor, Venue detail and Zone detail all mapped both
/// `loading` and `error` to `SizedBox.shrink()`. The comment on Floor said
/// these were "transient" because the mock emitted synchronously — true when it
/// was written, and untrue from the moment the real API landed. An API failure
/// painted an empty screen with a nav bar, no message and no way to retry, and
/// the user could not tell it apart from a venue that genuinely had no zones.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, this.error, this.onRetry, this.message});

  /// The failure, rendered through [messageFor] so the server's own wording
  /// reaches the user verbatim.
  final Object? error;

  /// Overrides [error] when there is nothing thrown to describe — an id that
  /// resolved to nothing, say.
  final String? message;

  /// Null hides the retry, for the cases where retrying cannot help (a venue
  /// that does not exist will not start existing).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final text = message ?? (error == null ? 'Something went wrong.' : messageFor(error!));

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 30, color: palette.textTertiary),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: PrismType.body.copyWith(color: palette.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              SecondaryButton(label: 'Try again', onTap: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}

/// What a screen shows while its first fetch is in flight.
///
/// Separate from [ErrorState] because they are not the same situation and were
/// being conflated: both mapped to an empty box, so a slow network and a failed
/// one looked identical, and neither looked different from success with no
/// data.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: palette.textTertiary,
        ),
      ),
    );
  }
}
