import 'package:flutter/material.dart';
import '../../core/constants/symptom_display_map.dart';
import 'assessment_controller.dart';
import 'followup_screen.dart';

class SymptomSelectionScreen extends StatefulWidget {
  final AssessmentController assessmentController;
  final VoidCallback onCancel;
  final String? selectedBodyArea;

  const SymptomSelectionScreen({
    super.key,
    required this.assessmentController,
    required this.onCancel,
    this.selectedBodyArea,
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
          selectedBodyArea: widget.selectedBodyArea,
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
                        if (widget.selectedBodyArea != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Showing symptoms for: ${widget.selectedBodyArea}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B4EFF),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
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
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF6B4EFF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Symptom assessment 15%',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
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
  final String? selectedBodyArea;

  const _SymptomPickerSheet({
    required this.assessmentController,
    this.selectedBodyArea,
  });

  @override
  State<_SymptomPickerSheet> createState() => _SymptomPickerSheetState();
}

class _SymptomPickerSheetState extends State<_SymptomPickerSheet> {
  static const Color _primary = Color(0xFF6B4EFF);
  final TextEditingController _queryController = TextEditingController();
  String _query = '';
  bool _showAll = false;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  bool get _hasAreaFilter =>
      !_showAll &&
      widget.selectedBodyArea != null &&
      kBodyAreaSymptoms.containsKey(widget.selectedBodyArea);

  List<MapEntry<String, String>> get _baseEntries {
    if (_hasAreaFilter) {
      final names = kBodyAreaSymptoms[widget.selectedBodyArea]!;
      return names
          .where((n) => kSymptomDisplayMap.containsKey(n))
          .map((n) => MapEntry(n, kSymptomDisplayMap[n]!))
          .toList();
    }
    return kSymptomDisplayMap.entries.toList();
  }

  List<MapEntry<String, String>> get _filtered {
    if (_query.isEmpty) return _baseEntries;
    final q = _query.toLowerCase();
    return _baseEntries.where((e) => e.key.toLowerCase().contains(q)).toList();
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
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    _hasAreaFilter
                        ? '${widget.selectedBodyArea} symptoms'
                        : 'Select symptoms',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
            if (_hasAreaFilter)
              TextButton(
                onPressed: () => setState(() => _showAll = true),
                child: const Text(
                  'Show all symptoms',
                  style: TextStyle(color: Color(0xFF6B4EFF), fontSize: 13),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: Text(
                        'No Results Found',
                        style: TextStyle(fontSize: 15, color: Colors.black54),
                      ),
                    )
                  : ListView.separated(
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
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE0E0E0),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Add symptom',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
