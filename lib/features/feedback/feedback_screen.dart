/// "How was your experience?" — two short steps, then a truthful outcome.
///
/// Reachable only when `FeatureFlags.feedbackEnabled` is on, which it is not
/// in any ordinary build. With no backend, the final step tells the truth:
/// feedback cannot be sent yet. It does not save to the device, does not
/// queue for later, and never claims to have submitted anything.
///
/// The optional comment field is built and styled but **switched off** until
/// a backend exists, because a free-text box is where health information
/// ends up. When it is switched on it carries the warning verbatim.
library;

import 'package:flutter/material.dart';

import '../../shared/theme/brand.dart';
import '../../shared/widgets/wella.dart';
import 'feedback_submission.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({
    super.key,
    this.submitter = FeedbackSubmitter.none,
    this.commentFieldEnabled = false,
    this.appVersion = '',
    this.platform = '',
  });

  /// Production passes the default, which cannot send. Tests inject one.
  final FeedbackSubmitter submitter;

  /// The comment box stays off until a backend and a privacy review exist.
  final bool commentFieldEnabled;

  final String appVersion;
  final String platform;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  FeedbackRating? _rating;
  FeedbackCategory? _category;
  final TextEditingController _comment = TextEditingController();
  FeedbackResult? _result;
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final FeedbackRating? rating = _rating;
    final FeedbackCategory? category = _category;
    if (rating == null || category == null || _sending) return;
    setState(() => _sending = true);

    final FeedbackResult result = await widget.submitter.submit(
      FeedbackPayload(
        rating: rating,
        category: category,
        comment: widget.commentFieldEnabled && _comment.text.trim().isNotEmpty
            ? _comment.text.trim()
            : null,
        appVersion: widget.appVersion,
        platform: widget.platform,
      ),
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: AppBar(
        backgroundColor: Brand.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Feedback', style: Brand.title),
      ),
      body: SafeArea(
        child: _result != null
            ? _Outcome(result: _result!, onClose: () => Navigator.pop(context))
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  Brand.gutter,
                  Brand.space2,
                  Brand.gutter,
                  Brand.space8,
                ),
                children: [
                  const Text('How was your experience?', style: Brand.display),
                  const SizedBox(height: Brand.space4),
                  for (final FeedbackRating rating in FeedbackRating.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Brand.space2),
                      child: _ChoiceRow(
                        label: rating.label,
                        selected: _rating == rating,
                        onTap: () => setState(() => _rating = rating),
                      ),
                    ),

                  if (_rating != null) ...[
                    const SizedBox(height: Brand.space6),
                    const Text(
                      'What would you like to tell us about?',
                      style: Brand.title,
                    ),
                    const SizedBox(height: Brand.space4),
                    for (final FeedbackCategory category
                        in FeedbackCategory.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Brand.space2),
                        child: _ChoiceRow(
                          label: category.label,
                          selected: _category == category,
                          onTap: () => setState(() => _category = category),
                        ),
                      ),
                  ],

                  if (_category != null) ...[
                    const SizedBox(height: Brand.space6),
                    _CommentField(
                      controller: _comment,
                      enabled: widget.commentFieldEnabled,
                    ),
                    const SizedBox(height: Brand.space6),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _sending ? null : _send,
                        style: FilledButton.styleFrom(
                          backgroundColor: Brand.primary,
                          disabledBackgroundColor: Brand.disabledSurface,
                          disabledForegroundColor: Brand.disabledText,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              Brand.radiusControl,
                            ),
                          ),
                        ),
                        child: Text(
                          _sending ? 'Sending…' : 'Send feedback',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// A selectable row. Selection is shown by a filled check AND a border
/// change, never by colour alone.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? Brand.primarySurface : Brand.surface,
        borderRadius: BorderRadius.circular(Brand.radiusControl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Brand.radiusControl),
          child: Container(
            constraints: const BoxConstraints(minHeight: Brand.minTapTarget),
            padding: const EdgeInsets.symmetric(
              horizontal: Brand.space4,
              vertical: Brand.space3,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.radiusControl),
              border: Border.all(
                color: selected ? Brand.primary : Brand.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 22,
                  color: selected ? Brand.primary : Brand.inkSoft,
                ),
                const SizedBox(width: Brand.space3),
                Expanded(child: Text(label, style: Brand.bodyStrong)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommentField extends StatelessWidget {
  const _CommentField({required this.controller, required this.enabled});

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Anything else? (optional)', style: Brand.cardTitle),
        const SizedBox(height: Brand.space2),
        Container(
          padding: const EdgeInsets.all(Brand.space3),
          decoration: BoxDecoration(
            color: Brand.emergencySurface,
            borderRadius: BorderRadius.circular(Brand.radiusControl),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.privacy_tip_outlined,
                size: 19,
                color: Brand.emergencyText,
              ),
              const SizedBox(width: Brand.space2),
              Expanded(
                child: Text(
                  'Please do not include your name, phone number, symptoms, '
                  'diagnosis or other personal health information.',
                  style: Brand.caption.copyWith(color: Brand.emergencyText),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Brand.space2),
        TextField(
          controller: controller,
          enabled: enabled,
          maxLines: 4,
          maxLength: 500,
          decoration: InputDecoration(
            filled: true,
            fillColor: enabled ? Brand.surface : Brand.disabledSurface,
            hintText: enabled
                ? 'What could be better?'
                : 'Comments open when feedback is switched on',
            hintStyle: Brand.body.copyWith(
              color: enabled ? Brand.inkSoft : Brand.disabledText,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Brand.radiusControl),
              borderSide: const BorderSide(color: Brand.border),
            ),
          ),
        ),
      ],
    );
  }
}

/// The honest ending. `unavailable` is the only outcome an ordinary build
/// can reach, and it says so plainly rather than thanking anyone.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.result, required this.onClose});

  final FeedbackResult result;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final (String title, String body, WellaMood mood) = switch (result) {
      FeedbackResult.sent => (
        'Thank you',
        'Your feedback has been sent. It helps us make WellaPath clearer.',
        WellaMood.celebrating,
      ),
      FeedbackResult.failed => (
        'That did not send',
        'Something went wrong on the way. Nothing was saved on your phone — '
            'please try again later.',
        WellaMood.calm,
      ),
      FeedbackResult.unavailable => (
        'Feedback is not open yet',
        'We have not switched feedback on, so nothing was sent and nothing '
            'was saved on your phone. Please check back after the next '
            'update.',
        WellaMood.calm,
      ),
    };

    return Padding(
      padding: const EdgeInsets.all(Brand.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The outcome scrolls and Close stays pinned. A fixed Column with
          // a Spacer overflowed at large text sizes and pushed the only way
          // out of the screen off the bottom.
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: Brand.space4),
                Center(child: Wella(size: 120, mood: mood)),
                const SizedBox(height: Brand.space6),
                Text(title, style: Brand.display),
                const SizedBox(height: Brand.space2),
                Text(body, style: Brand.body),
              ],
            ),
          ),
          const SizedBox(height: Brand.space4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onClose,
              style: OutlinedButton.styleFrom(
                foregroundColor: Brand.primary,
                side: const BorderSide(color: Brand.primary),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Brand.radiusControl),
                ),
              ),
              child: const Text(
                'Close',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
