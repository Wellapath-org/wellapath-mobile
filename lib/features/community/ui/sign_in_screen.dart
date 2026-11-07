import 'package:flutter/material.dart';

import '../../../shared/theme/brand.dart';
import '../data/community_auth_service.dart';
import '../data/community_repositories.dart';
import '../domain/community_validation.dart';
import 'community_scope.dart';

/// Email-OTP sign-in **and** sign-up (contract §3.3 A1/A2): the same two
/// steps either way; the server creates the account on first sign-in.
/// Pops `true` once signed in.
///
/// No password, no phone/SMS, and no TOTP (members never need it).
class CommunitySignInScreen extends StatefulWidget {
  const CommunitySignInScreen({super.key, required this.auth});

  final CommunityAuthService auth;

  @override
  State<CommunitySignInScreen> createState() => _CommunitySignInScreenState();
}

class _CommunitySignInScreenState extends State<CommunitySignInScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  String? _sentTo;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final String email;
    try {
      email = normaliseEmail(_email.text);
    } on CommunityValidationException {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.requestOtp(email);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sentTo = email;
        _code.clear();
      });
    } catch (e) {
      if (!mounted) return;
      // §4.3: never auto-retry an auth call after a 429; show the wait.
      setState(() {
        _busy = false;
        _error = communityErrorText(
          e,
          fallback: 'We could not send a code. Please try again.',
        );
      });
    }
  }

  Future<void> _verify() async {
    final String? email = _sentTo;
    if (email == null) return;
    final String code;
    try {
      code = validateOtpCode(_code.text);
    } on CommunityValidationException {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.verifyOtp(email: email, code: code);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      String message = communityErrorText(
        e,
        fallback: 'Sign-in did not work. Please try again.',
      );
      if (e is CommunityException) {
        if (e.code == CommunityErrorCode.invalidCode) {
          message =
              'That code is wrong or has expired. Check it, or ask for a '
              'new code.';
        } else if (e.code == CommunityErrorCode.accountSuspended) {
          message = 'This account cannot sign in to Community right now.';
        }
      }
      setState(() {
        _busy = false;
        _error = message;
      });
    }
  }

  void _showRecovery() {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext _) => const CommunityRecoverySheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? sentTo = _sentTo;
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: AppBar(
        title: const Text('Sign in to Community'),
        backgroundColor: Brand.surface,
        foregroundColor: Brand.ink,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Brand.gutter),
          children: [
            if (sentTo == null) ...[
              const Text(
                'Enter your email and we will send you a 6-digit code. If '
                'you are new, this also creates your Community account.',
                style: Brand.body,
              ),
              const SizedBox(height: Brand.space3),
              // CLINICAL REVIEW REQUIRED: states how health data is handled.
              const Text(
                'Community is separate from your health checks in WellaPath. '
                'Nothing from a check is shared with Community.',
                key: Key('signin_separation_note'),
                style: Brand.caption,
              ),
              const SizedBox(height: Brand.space4),
              TextField(
                key: const Key('signin_email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                maxLength: CommunityLimits.emailMax,
                decoration: InputDecoration(
                  labelText: 'Email',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Brand.space3),
              FilledButton(
                key: const Key('signin_send_code'),
                onPressed: _busy ? null : _requestCode,
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.primary,
                  minimumSize: const Size.fromHeight(Brand.minTapTarget),
                ),
                child: const Text('Send code'),
              ),
            ] else ...[
              Text(
                'Enter the 6-digit code we sent to $sentTo. It expires in '
                '5 minutes.',
                style: Brand.body,
              ),
              const SizedBox(height: Brand.space4),
              TextField(
                key: const Key('signin_code'),
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Code',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Brand.space3),
              FilledButton(
                key: const Key('signin_verify'),
                onPressed: _busy ? null : _verify,
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.primary,
                  minimumSize: const Size.fromHeight(Brand.minTapTarget),
                ),
                child: const Text('Sign in'),
              ),
              TextButton(
                key: const Key('signin_resend'),
                onPressed: _busy ? null : _requestCode,
                child: const Text('Send a new code'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _sentTo = null;
                        _error = null;
                      }),
                child: const Text('Use a different email'),
              ),
            ],
            const SizedBox(height: Brand.space4),
            TextButton(
              key: const Key('signin_recovery'),
              onPressed: _showRecovery,
              child: const Text('Cannot sign in, or lost your phone?'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Account recovery entry (contract §3.3, recovery paths 1 and 3).
class CommunityRecoverySheet extends StatelessWidget {
  const CommunityRecoverySheet({super.key});

  static const String lostDevice =
      'Lost or replaced your phone? Sign in here with the same email. Your '
      'Community account comes with you. Then open Account and choose '
      '"Sign out other devices".';

  static const String lostEmail =
      'No longer have access to your email? Contact WellaPath support. We '
      'will check it is really you before changing anything.';

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Padding(
        padding: EdgeInsets.all(Brand.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Getting back into Community', style: Brand.title),
            SizedBox(height: Brand.space3),
            Text(
              lostDevice,
              key: Key('recovery_lost_device'),
              style: Brand.body,
            ),
            SizedBox(height: Brand.space3),
            Text(lostEmail, style: Brand.body),
          ],
        ),
      ),
    );
  }
}
