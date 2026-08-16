import 'package:flutter/material.dart';
import '../../core/constants/symptom_display_map.dart';
import '../../core/telemetry/contract/telemetry_event.dart';
import 'assessment_controller.dart';
import 'loading_screen.dart';
import 'models/followup_question.dart';
import 'question_engine.dart';

/// QB-002 / IM-002 — evaluate a red-flag clarifier the moment it is answered
/// instead of after the last follow-up question.
///
/// Default off. Enable with `--dart-define=W3_IMMEDIATE_RED_FLAG=true`.
///
/// With the flag off `_onNext` takes exactly the path it took before, which is
/// the rollback: nothing is persisted, no artifact is published, and reverting
/// cannot introduce an under-triage that was not already present — the fix only
/// makes evaluation *earlier*.
///
/// Authoritative handoff: wellapath-knowledge-base @ aa7a2f13,
/// `mobile_handoff/question_flow_v1/IM002_SAFETY_FIX.md`
/// (sha256 6bc1863d…5df9d29c).
const bool kImmediateRedFlagEnabled = bool.fromEnvironment(
  'W3_IMMEDIATE_RED_FLAG',
);

class FollowupScreen extends StatefulWidget {
  final AssessmentController assessmentController;
  final VoidCallback onCancel;
  final String primarySymptomLabel;

  const FollowupScreen({
    super.key,
    required this.assessmentController,
    required this.onCancel,
    required this.primarySymptomLabel,
  });

  @override
  State<FollowupScreen> createState() => _FollowupScreenState();
}

class _FollowupScreenState extends State<FollowupScreen> {
  static const Color _primary = Color(0xFF6B4EFF);

  late final List<FollowupQuestion> _questions;
  int _currentQuestion = 0;
  final Map<int, dynamic> _answers = {};

  /// Questions whose answer has already been written to the controller, so a
  /// re-entrant `_onNext` or the final `_commitAnswers()` sweep cannot commit
  /// the same answer twice.
  final Set<int> _committed = <int>{};

  /// Set once a transition has been decided and never cleared on the interrupt
  /// path. A second tap arriving before the first navigation completes finds
  /// this true and returns, so exactly one transition wins.
  bool _transitionInProgress = false;

  static const Map<String, String> _durationTokens = {
    'Less than 3 days': 'days_1_3',
    '3 to 7 days': 'days_3_7',
    '8 to 14 days': 'days_7_plus',
    'More than 14 days': 'weeks_2_plus',
  };

  @override
  void initState() {
    super.initState();
    _questions = QuestionEngine.generateQuestions(
      widget.assessmentController.symptomTokens,
    );
  }

  String _severityToken(double value) {
    if (value <= 0.25) return 'mild';
    if (value <= 0.5) return 'moderate';
    if (value <= 0.75) return 'severe';
    return 'very_severe';
  }

  String? _displayNameForToken(String token) {
    for (final entry in kSymptomDisplayMap.entries) {
      if (entry.value == token) return entry.key;
    }
    return null;
  }

  void _onBack(BuildContext context) {
    if (_currentQuestion > 0) {
      setState(() => _currentQuestion -= 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _onNext(BuildContext context) {
    // One transition wins. A double tap, or a tap arriving while navigation is
    // already under way, returns here rather than advancing a second time or
    // slipping past an interrupt.
    if (_transitionInProgress) return;

    if (_currentQuestion < _questions.length - 1) {
      if (kImmediateRedFlagEnabled && _currentAnswerCanAffectRedFlag()) {
        _transitionInProgress = true;

        // Order matters, and this is the whole fix:
        //   1. commit THIS answer  2. evaluate  3. interrupt or advance.
        // Evaluating against state that does not yet include the answer would
        // be the same bug in a new place.
        try {
          _commitAnswer(_currentQuestion);
        } on Object catch (e) {
          // A commit failure must not be read as "no red flag". Fail closed:
          // hand over to the engine, which evaluates properly and surfaces its
          // own error state, rather than advancing past a possible danger sign.
          debugPrint(
            'Follow-up answer commit failed; failing closed to engine',
          );
          assert(() {
            debugPrint('  cause: ${e.runtimeType}');
            return true;
          }());
          _goToEvaluation(context);
          return;
        }

        if (_committedAnswerRaisedRedFlagToken(_currentQuestion)) {
          // Stop here. No step-view event — the next question is never shown,
          // so recording a view of it would both be untrue and make telemetry
          // a red-flag oracle. No setState, so no ordinary frame can appear
          // between this decision and the emergency presentation. The queued
          // questions are discarded, not deferred.
          _goToEvaluation(context);
          return;
        }

        // No red flag: fall through to the ordinary advance, unchanged.
        _transitionInProgress = false;
      }

      // Each follow-up question is a step. The question itself is never
      // recorded — no question ID, no category, no answer. `_questions.length`
      // is derived from the selected symptom tokens, which is exactly why the
      // step-view event carries no `step_count`. An assessment interrupted by
      // a red flag emits fewer of these, exactly as an abandoned one does —
      // which is what keeps the two indistinguishable.
      widget.assessmentController.telemetrySession.recordStepView();
      setState(() => _currentQuestion += 1);
    } else {
      _transitionInProgress = true;
      _commitAnswers();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LoadingScreen(
            assessmentController: widget.assessmentController,
            onCancel: widget.onCancel,
          ),
        ),
      );
    }
  }

  /// Hands the assessment to the existing engine path.
  ///
  /// `LoadingScreen` runs the real `EngineController`, so `RedFlagEvaluator`
  /// makes the clinical decision and `ScoringEngine` is never reached when a
  /// red flag fires. No clinical rule is duplicated here, and no new
  /// presentation is introduced — the interrupt screen this reaches is the
  /// existing one, with the existing emergency actions.
  void _goToEvaluation(BuildContext context) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LoadingScreen(
          assessmentController: widget.assessmentController,
          onCancel: widget.onCancel,
        ),
      ),
    );
  }

  /// True when answering this question could raise a red flag token.
  ///
  /// Derived from the question's own declaration rather than a hardcoded list
  /// of question ids: a clarifier is precisely the question that carries a
  /// `redFlagToken`, so a new clarifier added to `kRedFlagClarifiers` is
  /// covered automatically.
  bool _currentAnswerCanAffectRedFlag() {
    final question = _questions[_currentQuestion];
    return question.type == QuestionType.redFlagClarifier &&
        question.redFlagToken != null;
  }

  /// Whether the answer just committed for [index] actually put that
  /// question's red flag token into the assessment.
  ///
  /// Reads the committed controller state rather than the widget's answer map,
  /// so it cannot disagree with what the engine will see.
  bool _committedAnswerRaisedRedFlagToken(int index) {
    final token = _questions[index].redFlagToken;
    if (token == null) return false;
    return widget.assessmentController.symptomTokens.contains(token);
  }

  /// Commits exactly one question's answer, at most once.
  void _commitAnswer(int index) {
    if (!_committed.add(index)) return;
    if (!_answers.containsKey(index)) return;

    final question = _questions[index];
    final value = _answers[index];

    switch (question.type) {
      case QuestionType.severity:
        widget.assessmentController.setSeverityToken(
          _severityToken(value as double),
        );
      case QuestionType.duration:
        widget.assessmentController.setDurationToken(value as String);
      case QuestionType.additionalSymptoms:
        for (final token in value as Set<String>) {
          widget.assessmentController.addSymptomToken(token);
        }
      case QuestionType.redFlagClarifier:
        // Only an explicit yes raises the red flag. "No" leaves the milder
        // near-miss token as the user reported it.
        if (value == 'Yes' && question.redFlagToken != null) {
          widget.assessmentController.addSymptomToken(question.redFlagToken!);
        }
    }
  }

  void _commitAnswers() {
    for (final index in _answers.keys.toList()..sort()) {
      _commitAnswer(index);
    }
  }

  void _showCancelDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Assessment'),
        content: const Text(
          'Are you sure you want to cancel your symptom assessment?',
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // Recorded before `clearAll()`, so the session still exists.
              // `abandoned` says the user stopped; it says nothing about what
              // had been entered, and nothing was computed at this point.
              widget.assessmentController.telemetrySession.recordComplete(
                CompletionStatus.abandoned,
              );
              widget.assessmentController.clearAll();
              widget.onCancel();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: _primary,
              side: const BorderSide(color: _primary),
            ),
            child: const Text('Yes, cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('No, continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final question = _questions[_currentQuestion];
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                child: _buildQuestion(question),
              ),
            ),
            _buildBottomButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final progress = (_currentQuestion + 1) / _questions.length;
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
                  color: _primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Question ${_currentQuestion + 1} of ${_questions.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 22),
                onPressed: () => _showCancelDialog(context),
              ),
            ],
          ),
        ),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: const Color(0xFFEEEEEE),
          color: _primary,
          minHeight: 3,
        ),
      ],
    );
  }

  Widget _buildQuestion(FollowupQuestion question) {
    switch (question.type) {
      case QuestionType.severity:
        return _buildSeveritySection(question);
      case QuestionType.duration:
        return _buildDurationSection(question);
      case QuestionType.additionalSymptoms:
        return _buildAdditionalSymptomsSection(question);
      case QuestionType.redFlagClarifier:
        return _buildRedFlagClarifierSection(question);
    }
  }

  Widget _buildRedFlagClarifierSection(FollowupQuestion question) {
    final selected = _answers[_currentQuestion] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.questionText,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 20),
        ...question.options.map((option) {
          final isSelected = selected == option;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => setState(() => _answers[_currentQuestion] = option),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected ? _primary : const Color(0xFFE0E0E0),
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? _primary
                              : const Color(0xFFBDBDBD),
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? Center(
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _primary,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      option,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSeveritySection(FollowupQuestion question) {
    final value = (_answers[_currentQuestion] as double?) ?? 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.questionText,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 20),
        _SegmentedSeveritySlider(
          value: value,
          onChanged: (v) => setState(() => _answers[_currentQuestion] = v),
        ),
        const SizedBox(height: 8),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Mild', style: TextStyle(fontSize: 12, color: Colors.black54)),
            Text(
              'Moderate',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            Text(
              'Severe',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            Text(
              'Unbearable',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDurationSection(FollowupQuestion question) {
    final selection = _answers[_currentQuestion] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.questionText,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        ..._durationTokens.entries.map((entry) {
          final isSelected = selection == entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? _primary : const Color(0xFFE0E0E0),
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: () =>
                  setState(() => _answers[_currentQuestion] = entry.value),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    _buildRadioCircle(isSelected),
                    const SizedBox(width: 14),
                    Text(
                      entry.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRadioCircle(bool isSelected) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? _primary : const Color(0xFFBDBDBD),
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: isSelected
          ? Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _primary,
              ),
            )
          : null,
    );
  }

  Widget _buildAdditionalSymptomsSection(FollowupQuestion question) {
    final selected = (_answers[_currentQuestion] as Set<String>?) ?? <String>{};
    final availableTokens = question.options
        .where((token) => _displayNameForToken(token) != null)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.questionText,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        ...availableTokens.map((token) {
          final displayName = _displayNameForToken(token)!;
          return CheckboxListTile(
            title: Text(displayName, style: const TextStyle(fontSize: 15)),
            value: selected.contains(token),
            onChanged: (checked) {
              setState(() {
                final updated = Set<String>.of(selected);
                if (checked == true) {
                  updated.add(token);
                } else {
                  updated.remove(token);
                }
                _answers[_currentQuestion] = updated;
              });
            },
            activeColor: _primary,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            visualDensity: const VisualDensity(vertical: -2),
          );
        }),
      ],
    );
  }

  Widget _buildBottomButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _onBack(context),
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
              onPressed: () => _onNext(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
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

// ─── Segmented severity slider ────────────────────────────────────────────────

class _SegmentedSeveritySlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _SegmentedSeveritySlider({
    required this.value,
    required this.onChanged,
  });

  static const List<Color> _segmentColors = [
    Color(0xFF4ADE80),
    Color(0xFF86EFAC),
    Color(0xFFFDE68A),
    Color(0xFFFBBF24),
    Color(0xFFF97316),
    Color(0xFFEF4444),
    Color(0xFFDC2626),
  ];

  @override
  Widget build(BuildContext context) {
    final activeCount = (value * 7).ceil().clamp(0, 7);
    return Row(
      children: List.generate(7, (i) {
        final isActive = i < activeCount;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged((i + 1) / 7),
            child: Container(
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isActive ? _segmentColors[i] : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        );
      }),
    );
  }
}
