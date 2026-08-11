/// Per-assessment telemetry correlation.
///
/// One instance exists per assessment attempt and holds the opaque
/// `assessment_session_id` that ties `assessment_start`,
/// `assessment_step_view`, `assessment_complete` and `result_view` together.
///
/// ### What the session ID is
///
/// 24 characters from `Random.secure()`. It is **not derived** from symptoms,
/// answers, the clock, device identity, account identity or any clinical
/// state — [SecureTelemetryIdGenerator.newSessionId] takes no arguments at
/// all, which is the simplest possible proof of that.
///
/// ### Lifecycle
///
/// The ID lives and dies with the [AssessmentTelemetrySession] object, which
/// lives and dies with the `AssessmentController` that owns it. That controller
/// is constructed fresh in `HomeScreen._goToIntro()` every time an assessment
/// is launched, so:
///
///  * **Restarting** — going home and starting again builds a new controller,
///    so a new ID. Never reused.
///  * **Back-navigation inside a flow** — the same controller, so the same ID.
///    That is the intent: it is still one assessment.
///  * **Abandoning** — `assessment_complete{abandoned}` is emitted before the
///    controller is discarded, and the ID goes with it.
///  * **Resuming** — not applicable. The MVP does not persist an in-flight
///    assessment; there is nothing to resume and no ID is ever written to
///    disk outside a queued event.
///
/// The ID is retained only as long as queued events referencing it, and those
/// expire at 30 days like everything else in the queue.
library;

import 'contract/telemetry_event.dart';
import 'telemetry.dart';
import 'telemetry_runtime.dart';

/// Version of the on-device assessment flow, sent as `flow_version`.
///
/// The flow has not carried a version before I1. Declared `1.0` for the flow
/// as it stands (intro → sex → age → conditions → [pregnancy] → body area →
/// symptoms → follow-ups) and to be bumped when the step sequence changes.
const String kAssessmentFlowVersion = '1.0';

/// Version of the on-device result presentation contract, sent as
/// `presentation_contract_version`.
///
/// Also previously unversioned. It is deliberately **not** the knowledge-base
/// or rules artifact version: this field describes how a result is presented,
/// not what was computed, and putting a clinical artifact version here would
/// both misreport the field and attach a clinical reference to a user's
/// result view.
const String kPresentationContractVersion = '1.0';

/// Correlation state for one assessment attempt.
///
/// Each emitting method is idempotent where the contract expects one event per
/// assessment, so a widget rebuild or a re-entered route cannot double-count.
class AssessmentTelemetrySession {
  AssessmentTelemetrySession({
    TelemetryIdGenerator? idGenerator,
    TelemetryClock? clock,
  }) : _clock = clock ?? const SystemTelemetryClock(),
       sessionId = (idGenerator ?? SecureTelemetryIdGenerator())
           .newSessionId() {
    _startedAt = _clock.nowUtc();
  }

  final String sessionId;
  final TelemetryClock _clock;
  late final DateTime _startedAt;

  bool _startEmitted = false;
  bool _completeEmitted = false;
  bool _resultViewEmitted = false;
  int _stepsViewed = 0;

  /// How many steps the user actually reached. An effort measure, not a flow
  /// total — see [recordStepView].
  int get stepsViewed => _stepsViewed;

  /// The contract caps `step_index` and `step_count` at 200.
  static const int _maxSteps = 200;

  /// Emits `assessment_start`. Safe to call more than once; only the first
  /// call emits.
  void recordStart({
    AssessmentEntryPoint entryPoint = AssessmentEntryPoint.home,
  }) {
    if (_startEmitted) return;
    _startEmitted = true;
    Telemetry.capture(
      AssessmentStartEvent(
        assessmentSessionId: sessionId,
        flowVersion: kAssessmentFlowVersion,
        entryPoint: entryPoint,
      ),
    );
  }

  /// Emits `assessment_step_view` for the next step reached.
  ///
  /// `step_index` is a **depth counter**, incremented once per step display,
  /// not an identifier for which screen was shown. That matters: the flow is
  /// branch-dependent — the pregnancy step only appears for one answer to the
  /// sex question, and the number of follow-up questions is derived from the
  /// selected symptom tokens. A positional index tied to specific screens
  /// would leak both. A depth counter leaks neither, and still gives the
  /// drop-off funnel the contract says this event is for.
  ///
  /// `step_count` is not sent at all — see [AssessmentStepViewEvent].
  ///
  /// Called from each step screen's `initState`, so re-entering a step by
  /// navigating back and forward counts as another view, which is what "a
  /// step was displayed" means.
  void recordStepView() {
    if (_stepsViewed >= _maxSteps) return;
    final index = _stepsViewed;
    _stepsViewed++;
    Telemetry.capture(
      AssessmentStepViewEvent(assessmentSessionId: sessionId, stepIndex: index),
    );
  }

  /// Emits `assessment_complete`. Only the first call emits, so a cancel
  /// followed by a teardown cannot report the assessment twice.
  ///
  /// **[status] never encodes a clinical outcome.** The red-flag interrupt
  /// path reports [CompletionStatus.completed], exactly like the ordinary
  /// results path; anything else would make this field a red-flag detector.
  void recordComplete(CompletionStatus status) {
    if (_completeEmitted) return;
    _completeEmitted = true;
    final elapsed = _clock.nowUtc().difference(_startedAt).inMilliseconds;
    Telemetry.capture(
      AssessmentCompleteEvent(
        assessmentSessionId: sessionId,
        completionStatus: status,
        durationMs: elapsed.clamp(0, 7200000),
        stepCount: _stepsViewed.clamp(0, _maxSteps),
      ),
    );
  }

  /// Emits `result_view`. Only the first call emits.
  ///
  /// Called from **both** the results screen and the red-flag interrupt
  /// screen. Emitting from only one would make the event's presence a
  /// red-flag signal when joined to `assessment_complete`.
  void recordResultView() {
    if (_resultViewEmitted) return;
    _resultViewEmitted = true;
    Telemetry.capture(
      ResultViewEvent(
        assessmentSessionId: sessionId,
        presentationContractVersion: kPresentationContractVersion,
      ),
    );
  }
}
