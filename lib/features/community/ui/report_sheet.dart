import 'package:flutter/material.dart';

import '../../../shared/theme/brand.dart';
import '../data/community_repositories.dart';
import '../domain/community_validation.dart';
import '../domain/report.dart';
import 'community_scope.dart';

/// Opens the report sheet for a post or comment. Returns true if a report
/// was submitted.
Future<bool> showReportSheet(
  BuildContext context, {
  required ReportTargetType targetType,
  required String targetId,
}) async {
  final CommunityScope scope = CommunityScope.of(context);
  final bool? sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext _) => CommunityScope(
      gate: scope.gate,
      services: scope.services,
      child: ReportSheet(targetType: targetType, targetId: targetId),
    ),
  );
  return sent ?? false;
}

class ReportSheet extends StatefulWidget {
  const ReportSheet({
    super.key,
    required this.targetType,
    required this.targetId,
  });

  final ReportTargetType targetType;
  final String targetId;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  ReportReason? _reason;
  final TextEditingController _note = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ReportReason? reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Choose a reason.');
      return;
    }
    final ReportDraft draft;
    try {
      draft = ReportDraft(
        targetType: widget.targetType,
        targetId: widget.targetId,
        reason: reason,
        note: _note.text,
      );
    } on CommunityValidationException {
      setState(() => _error = 'The note is too long.');
      return;
    }
    setState(() => _sending = true);
    try {
      await CommunityScope.of(context).services.community.submitReport(draft);
      if (mounted) Navigator.of(context).pop(true);
    } on CommunityException catch (e) {
      if (!mounted) return;
      if (CommunityScope.handleError(context, e)) return;
      setState(() {
        _sending = false;
        _error = e.code == CommunityErrorCode.conflict
            ? 'You have already reported this.'
            : 'The report could not be sent. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String what = widget.targetType == ReportTargetType.post
        ? 'post'
        : 'comment';
    return Padding(
      padding: EdgeInsets.only(
        left: Brand.gutter,
        right: Brand.gutter,
        top: Brand.space4,
        bottom: MediaQuery.of(context).viewInsets.bottom + Brand.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report this $what', style: Brand.title),
            const SizedBox(height: Brand.space3),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (ReportReason? r) => setState(() => _reason = r),
              child: Column(
                children: [
                  for (final ReportReason r in ReportReason.values)
                    RadioListTile<ReportReason>(
                      key: Key('report_reason_${r.wire}'),
                      value: r,
                      title: Text(r.label),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            TextField(
              key: const Key('report_note'),
              controller: _note,
              maxLength: CommunityLimits.reportNoteMax,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add a note (optional)',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Brand.space3),
            FilledButton(
              key: const Key('report_submit'),
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: Brand.primary,
                minimumSize: const Size.fromHeight(Brand.minTapTarget),
              ),
              child: const Text('Send report'),
            ),
          ],
        ),
      ),
    );
  }
}
