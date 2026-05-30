import 'package:flutter/material.dart';
import '../../core/constants/symptom_display_map.dart';
import 'assessment_controller.dart';
import 'followup_screen.dart';

class SymptomSelectionScreen extends StatefulWidget {
  final AssessmentController assessmentController;
  final VoidCallback onCancel;

  const SymptomSelectionScreen({
    super.key,
    required this.assessmentController,
    required this.onCancel,
  });

  @override
  State<SymptomSelectionScreen> createState() => _SymptomSelectionScreenState();
}

class _SymptomSelectionScreenState extends State<SymptomSelectionScreen> {
  static const Color _primary = Color(0xFF6B4EFF);

  String _primarySymptomLabel() {
    final tokens = widget.assessmentController.symptomTokens;
    if (tokens.isEmpty) return 'your symptoms';
    return kSymptomDisplayMap.entries
        .firstWhere(
          (e) => e.value == tokens.first,
          orElse: () => MapEntry(tokens.first, tokens.first),
        )
        .key;
  }

  void _openSymptomPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.72,
        child: _SymptomPickerSheet(
          assessmentController: widget.assessmentController,
        ),
      ),
    );
  }

  void _onNext(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FollowupScreen(
          assessmentController: widget.assessmentController,
          onCancel: widget.onCancel,
          primarySymptomLabel: _primarySymptomLabel(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.assessmentController,
      builder: (context, _) {
        final tokens = widget.assessmentController.symptomTokens;
        final isEnabled = tokens.isNotEmpty;
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Ok let's proceed with the symptom that's bothering you.",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (tokens.isNotEmpty) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: tokens.map((token) {
                              final label = kSymptomDisplayMap.entries
                                  .firstWhere(
                                    (e) => e.value == token,
                                    orElse: () => MapEntry(token, token),
                                  )
                                  .key;
                              return Chip(
                                label: Text(
                                  label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                                backgroundColor: _primary,
                                deleteIcon: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                onDeleted: () => widget.assessmentController
                                    .removeSymptomToken(token),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide.none,
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                        ],
                        OutlinedButton.icon(
                          onPressed: () => _openSymptomPicker(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Add symptoms'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _primary,
                            side: const BorderSide(color: _primary),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildBottomButtons(context, isEnabled),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(
            children: [
              const Text(
                'Symptom assessment 15%',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 22),
                onPressed: widget.onCancel,
              ),
            ],
          ),
        ),
        LinearProgressIndicator(
          value: 0.15,
          backgroundColor: const Color(0xFFEEEEEE),
          color: _primary,
          minHeight: 3,
        ),
      ],
    );
  }

  Widget _buildBottomButtons(BuildContext context, bool isEnabled) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primary,
                side: const BorderSide(color: _primary),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Back',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: isEnabled ? () => _onNext(context) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE0E0E0),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Next',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Symptom picker bottom sheet ──────────────────────────────────────────────

class _SymptomPickerSheet extends StatefulWidget {
  final AssessmentController assessmentController;

  const _SymptomPickerSheet({required this.assessmentController});

  @override
  State<_SymptomPickerSheet> createState() => _SymptomPickerSheetState();
}

class _SymptomPickerSheetState extends State<_SymptomPickerSheet> {
  static const Color _primary = Color(0xFF6B4EFF);
  final TextEditingController _queryController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  List<MapEntry<String, String>> get _filtered {
    if (_query.isEmpty) return kSymptomDisplayMap.entries.toList();
    final q = _query.toLowerCase();
    return kSymptomDisplayMap.entries
        .where((e) => e.key.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.assessmentController,
      builder: (context, _) {
        final selected = widget.assessmentController.symptomTokens.toSet();
        final entries = _filtered;
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select symptoms',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _queryController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search symptoms',
                  hintStyle: const TextStyle(
                    color: Colors.black38,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(Icons.search, color: Colors.black38),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16),

                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final isSelected = selected.contains(entry.value);
                  return ListTile(
                    title: Text(
                      entry.key,
                      style: const TextStyle(fontSize: 15),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: _primary)
                        : const Icon(
                            Icons.circle_outlined,
                            color: Colors.black26,
                          ),
                    onTap: () {
                      if (isSelected) {
                        widget.assessmentController.removeSymptomToken(
                          entry.value,
                        );
                      } else {
                        widget.assessmentController.addSymptomToken(
                          entry.value,
                        );
                      }
                    },
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
