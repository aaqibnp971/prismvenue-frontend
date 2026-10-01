import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repo.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/prism_bottom_sheet.dart';
import '../../shared/widgets/prism_field.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// Change your password without signing out — finding #17.
///
/// Until now the only way to change a password was to forget it: sign out, ask
/// for a code, read an email, come back. On a shared venue tablet that is a
/// genuinely bad experience, and it is the reason a manager's password becomes
/// something everybody knows and nobody changes.
///
/// Asks for the current one, and the server really does check it by signing in
/// with it. A bearer token alone must not be enough — the tablet is sitting
/// unlocked on a counter.
///
/// Resolves true once the change has been accepted.
Future<bool?> showChangePasswordSheet(BuildContext context) {
  return showPrismSheet<bool>(
    context,
    topBarHeight: PrismTopBar.height,
    sheet: const _ChangePasswordSheet(),
  );
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;

    // Checked here first, exactly as the reset flow does (S00-4), so the
    // server never has to answer a question the device could.
    if (_current.text.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    if (_next.text.length < 8) {
      setState(() => _error = 'Choose a longer password — at least 8 characters.');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = 'Those two do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepoProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = messageFor(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return PrismBottomSheet(
      title: 'Change password',
      primaryLabel: _busy ? 'Saving…' : 'Save password',
      onPrimary: _save,
      onCancel: () => Navigator.of(context).pop(),
      children: [
        const SizedBox(height: 16),
        PrismField(
          label: 'Current password',
          controller: _current,
          obscure: true,
          focusedOverride: true,
        ),
        const SizedBox(height: 12),
        PrismField(label: 'New password', controller: _next, obscure: true),
        const SizedBox(height: 12),
        PrismField(
          label: 'Confirm new password',
          controller: _confirm,
          obscure: true,
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          ErrorNote(message: _error!),
        ],
        const SizedBox(height: 9),
        Text(
          'You stay signed in on this device.',
          style: PrismType.microHelper.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}
