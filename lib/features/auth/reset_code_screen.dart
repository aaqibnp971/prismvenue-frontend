import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/auth_repo.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/otp_boxes.dart';
import '../../shared/widgets/primary_button.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'reset_email_screen.dart';
import 'widgets/auth_shell.dart';

/// S00-3 "Enter code — 6-digit code from the email". Helper shows the email
/// in 700 `textPrimary`; OTP row per §2 S00-3; "Didn't get it? Resend code"
/// with the link part in accent. Wrong-code state is undesigned (§6-B1);
/// helper copy around the email is assumed (see open_questions.md).
class ResetCodeScreen extends ConsumerStatefulWidget {
  const ResetCodeScreen({super.key});

  @override
  ConsumerState<ResetCodeScreen> createState() => _ResetCodeScreenState();
}

class _ResetCodeScreenState extends ConsumerState<ResetCodeScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  String? _error;

  /// Doubles as the busy guard and the label state, so a slow network cannot
  /// queue three codes.
  var _resending = false;

  /// Confirmation for a resend, cleared when the code is edited.
  String? _resent;

  Future<void> _resend(String email) async {
    setState(() {
      _resending = true;
      _error = null;
      _resent = null;
    });
    try {
      await ref.read(authRepoProvider).sendResetCode(email);
      if (mounted) setState(() => _resent = 'A new code is on its way.');
    } catch (e) {
      if (mounted) setState(() => _error = messageFor(e));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _verify() async {
    final email = ref.read(resetEmailProvider);
    setState(() => _error = null);
    try {
      // The token returned here is what authorises the password change on the
      // next screen — see resetTokenProvider.
      final resetToken =
          await ref.read(authRepoProvider).verifyResetCode(email, _code.text);
      ref.read(resetTokenProvider.notifier).set(resetToken);
    } catch (e) {
      if (mounted) setState(() => _error = messageFor(e));
      return;
    }
    if (!mounted) return;
    context.go('/reset/new');
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final email = ref.watch(resetEmailProvider);
    return AuthShell(
      heading: 'Enter the code',
      onBack: () => context.go('/reset/email'),
      helperWidget: Text.rich(
        TextSpan(
          text: 'Enter the 6-digit code we sent to ',
          children: [
            TextSpan(
                text: email,
                style: PrismType.body.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary)),
            const TextSpan(text: '.'),
          ],
        ),
        style:
            PrismType.body.copyWith(fontSize: 15, color: palette.textSecondary),
      ),
      children: [
        // OTP row — taps focus a hidden digits-only field.
        GestureDetector(
          onTap: () => _focus.requestFocus(),
          child: Stack(
            children: [
              Offstage(
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: TextField(
                    controller: _code,
                    focusNode: _focus,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(counterText: ''),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              OtpBoxes(value: _code.text),
            ],
          ),
        ),
        ErrorNote(message: _error),
        // Success needs a signal too, not just failure — the whole complaint
        // was that a resend looked exactly like doing nothing.
        if (_resent != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_resent!,
                style: PrismType.meta.copyWith(
                    fontWeight: FontWeight.w600, color: palette.green)),
          ),
        const SizedBox(height: 22),
        PrimaryButton(label: 'Verify', auth: true, expanded: true, onTap: _verify),
        const SizedBox(height: 18),
        AuthFooterLink(
          // Was an unawaited call: success and failure looked identical --
          // nothing moved either way -- so users tapped it repeatedly and had
          // no way to know whether a second code was coming.
          onTap: _resending ? null : () => _resend(email),
          child: Text.rich(
            TextSpan(
              text: "Didn't get it? ",
              children: [
                TextSpan(
                    text: _resending ? 'Sending…' : 'Resend code',
                    style: PrismType.bodySm.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.accent)),
              ],
            ),
            style: PrismType.bodySm
                .copyWith(fontSize: 13, color: palette.textSecondary),
          ),
        ),
      ],
    );
  }
}
