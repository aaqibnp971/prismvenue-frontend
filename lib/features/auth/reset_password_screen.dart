import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/auth_repo.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/prism_field.dart';
import '../../shared/widgets/prism_icons.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'reset_email_screen.dart';
import 'widgets/auth_shell.dart';

/// S00-4 "New password — enter and confirm". Two labelled password fields
/// ("New password" accent border / "Confirm password" `borderStrong`),
/// match-hint row mt12 (14 check + "At least 8 characters · both match"
/// 11.5/600 `green` — shown as in the frame; validation is undesigned,
/// §6-B9), then "Save new password" → back to S00-1.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  /// Matches the server's own floor (`ResetSavePasswordRequest.password`,
  /// `min_length=8`). Checking it here turns a 422 into a sentence.
  static const _minLength = 8;

  @override
  void initState() {
    super.initState();
    // The match hint is live, so it has to rebuild as either field changes.
    _password.addListener(_onFieldChanged);
    _confirm.addListener(_onFieldChanged);
  }

  void _onFieldChanged() => setState(() {});

  @override
  void dispose() {
    _password.removeListener(_onFieldChanged);
    _confirm.removeListener(_onFieldChanged);
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _error;

  bool get _longEnough => _password.text.length >= _minLength;

  /// Requires a non-empty confirm: two blank fields "match", and treating that
  /// as valid is how an empty password reaches the server.
  bool get _matches =>
      _confirm.text.isNotEmpty && _password.text == _confirm.text;

  bool get _valid => _longEnough && _matches;

  Future<void> _save() async {
    // The whole job of the confirm field. Before this it was declared, wired to
    // a text field, disposed — and never compared to anything, so a mistyped
    // confirm locked the user out of the account they were trying to recover.
    if (!_longEnough) {
      setState(() => _error = 'Use at least $_minLength characters.');
      return;
    }
    if (!_matches) {
      setState(() => _error = 'Those two passwords do not match.');
      return;
    }

    final email = ref.read(resetEmailProvider);
    final resetToken = ref.read(resetTokenProvider);
    if (resetToken == null) {
      // Reachable by navigating straight to /reset/new — the router treats all
      // /reset/* paths as public. Without the token the server would refuse
      // anyway; failing here says why instead of showing a generic error.
      setState(() => _error = 'Verify the emailed code first.');
      return;
    }
    setState(() => _error = null);
    try {
      await ref.read(authRepoProvider).saveNewPassword(
            email: email,
            password: _password.text,
            resetToken: resetToken,
          );
    } catch (e) {
      if (mounted) setState(() => _error = messageFor(e));
      return;
    }
    // Single-use: drop it so a stale token cannot be replayed.
    ref.read(resetTokenProvider.notifier).set(null);
    if (!mounted) return;
    context.go('/signin');
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return AuthShell(
      heading: 'Set a new password',
      onBack: () => context.go('/reset/code'),
      children: [
        PrismField(
          auth: true,
          label: 'New password',
          controller: _password,
          obscure: true,
          focusedOverride: true,
        ),
        const SizedBox(height: 14),
        PrismField(
          auth: true,
          label: 'Confirm password',
          controller: _confirm,
          obscure: true,
          strongBorder: true,
        ),
        const SizedBox(height: 12),
        // The frame draws this row already satisfied. Shipped that way it was a
        // green tick asserting "both match" over two fields that did not — the
        // one piece of feedback on the screen actively lying. It now tracks the
        // fields: green only once both conditions actually hold.
        Row(
          children: [
            PrismCheck(
                size: 14,
                color: _valid ? palette.green : palette.textTertiary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'At least $_minLength characters · both match',
                style: PrismType.meta.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _valid ? palette.green : palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
        ErrorNote(message: _error),
        const SizedBox(height: 22),
        PrimaryButton(
            label: 'Save new password', auth: true, expanded: true, onTap: _save),
      ],
    );
  }
}
