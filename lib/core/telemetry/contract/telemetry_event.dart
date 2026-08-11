/// Typed, allowlisted telemetry events — contract v1.0.
///
/// The type system is the primary privacy control. There is no constructor
/// anywhere in this file that accepts a free-form map, a `metadata` bag, or a
/// `String` where the contract declares an enum. A caller cannot express a
/// prohibited field, so it cannot accidentally send one. `privacy_guard.dart`
/// is the second, defensive layer behind this one — it exists to catch a
/// *programming* error in this file, not to sanitise caller input.
///
/// Every enum below is closed against `telemetry_contract.dart`, which is in
/// turn checked against the backend allowlist by `contract_parity_test.dart`.
library;

import 'telemetry_contract.dart';

/// Base for the 12 allowlisted events.
///
/// Subclasses expose only the properties their event declares. `event_id` and
/// `client_ts` are *not* here: they are stamped once by `TelemetryService` at
/// the moment of capture and then carried immutably through the queue and
/// every retry, which is what makes server-side de-duplication work.
sealed class TelemetryEvent {
  const TelemetryEvent();

  /// One of [TelemetryContract.eventNames].
  String get eventName;

  /// Event-specific properties, wire-named. Null-valued optional properties
  /// are omitted rather than serialised as `null` — the backend's allowlist
  /// treats an explicit `null` as an invalid type, not as absence.
  Map<String, Object?> toProperties();

  /// Drops null optional values so subclasses can build maps declaratively.
  static Map<String, Object?> _compact(Map<String, Object?> raw) {
    final out = <String, Object?>{};
    raw.forEach((key, value) {
      if (value != null) out[key] = value;
    });
    return out;
  }
}

// ── Enumerations ────────────────────────────────────────────────────────────

enum LaunchType {
  cold('cold'),
  warm('warm');

  const LaunchType(this.wire);
  final String wire;
}

enum AssessmentEntryPoint {
  home('home'),
  library('library'),
  facilityLocator('facility_locator'),
  deepLink('deep_link');

  const AssessmentEntryPoint(this.wire);
  final String wire;
}

enum CompletionStatus {
  /// The engine produced an output and the user was shown a result.
  ///
  /// **This value is used for the red-flag interrupt path too.** Reporting
  /// `interrupted` there would make the completion status a red-flag
  /// indicator, and a red-flag match is clinical data the contract forbids.
  completed('completed'),

  /// The user cancelled the assessment themselves.
  abandoned('abandoned'),

  /// A *technical* interruption — engine failure, missing artifacts, or the
  /// first-launch-offline path. Never a clinical outcome.
  interrupted('interrupted');

  const CompletionStatus(this.wire);
  final String wire;
}

enum FacilitySearchMode {
  nearby('nearby'),
  manualArea('manual_area'),
  name('name');

  const FacilitySearchMode(this.wire);
  final String wire;
}

/// Origin surface for `facility_view`. Wider than [FacilityActionSource] — the
/// contract allows `map` and `saved` here and only here.
enum FacilityViewSource {
  searchResults('search_results'),
  map('map'),
  saved('saved'),
  emergencyScreen('emergency_screen');

  const FacilityViewSource(this.wire);
  final String wire;
}

/// Origin surface for `facility_call` and `directions_open`.
enum FacilityActionSource {
  searchResults('search_results'),
  facilityDetail('facility_detail'),
  emergencyScreen('emergency_screen');

  const FacilityActionSource(this.wire);
  final String wire;
}

enum EmergencyActionType {
  callEmergencyNumber('call_emergency_number'),
  viewEmergencyGuidance('view_emergency_guidance'),
  dismissEmergencyBanner('dismiss_emergency_banner'),
  openNearestFacility('open_nearest_facility');

  const EmergencyActionType(this.wire);
  final String wire;
}

enum FeedbackCategory {
  usability('usability'),
  performance('performance'),
  content('content'),
  other('other');

  const FeedbackCategory(this.wire);
  final String wire;
}

// ── Events ──────────────────────────────────────────────────────────────────

/// The application was brought to the foreground.
class AppOpenEvent extends TelemetryEvent {
  const AppOpenEvent({required this.launchType, this.isFirstLaunch});

  final LaunchType launchType;
  final bool? isFirstLaunch;

  @override
  String get eventName => 'app_open';

  @override
  Map<String, Object?> toProperties() => TelemetryEvent._compact({
    'launch_type': launchType.wire,
    'is_first_launch': isFirstLaunch,
  });
}

/// The user began an assessment.
class AssessmentStartEvent extends TelemetryEvent {
  const AssessmentStartEvent({
    required this.assessmentSessionId,
    this.flowVersion,
    this.entryPoint,
  });

  final String assessmentSessionId;
  final String? flowVersion;
  final AssessmentEntryPoint? entryPoint;

  @override
  String get eventName => 'assessment_start';

  @override
  Map<String, Object?> toProperties() => TelemetryEvent._compact({
    'assessment_session_id': assessmentSessionId,
    'flow_version': flowVersion,
    'entry_point': entryPoint?.wire,
  });
}

/// An assessment step was displayed.
///
/// [stepIndex] is the ordinal position of the step *within the sequence this
/// user actually walked* — a depth counter, not a screen identifier. There is
/// no `question_id`: the contract excludes it in v1.0 (§8), and this flow is
/// branch-dependent, so a per-session sequence of question IDs would be
/// answer-derived.
///
/// `step_count` is deliberately **not exposed on this event**. It is optional
/// in the contract, and the only value this app could put there is the flow
/// total — which is computed by `QuestionEngine.generateQuestions()` from the
/// user's selected symptom tokens. Transmitting it would leak an
/// answer-derived quantity on every step. See `docs/TELEMETRY_MOBILE.md`.
class AssessmentStepViewEvent extends TelemetryEvent {
  const AssessmentStepViewEvent({
    required this.assessmentSessionId,
    required this.stepIndex,
  });

  final String assessmentSessionId;
  final int stepIndex;

  @override
  String get eventName => 'assessment_step_view';

  @override
  Map<String, Object?> toProperties() => {
    'assessment_session_id': assessmentSessionId,
    'step_index': stepIndex,
  };
}

/// An assessment reached a terminal state.
///
/// Carries no urgency, condition, score or red-flag information of any kind —
/// see [CompletionStatus.completed] for why the red-flag path reports the same
/// status as the ordinary results path.
class AssessmentCompleteEvent extends TelemetryEvent {
  const AssessmentCompleteEvent({
    required this.assessmentSessionId,
    required this.completionStatus,
    this.durationMs,
    this.stepCount,
  });

  final String assessmentSessionId;
  final CompletionStatus completionStatus;
  final int? durationMs;

  /// Number of steps the user actually reached — an effort measure, bounded by
  /// the contract at 0–200.
  final int? stepCount;

  @override
  String get eventName => 'assessment_complete';

  @override
  Map<String, Object?> toProperties() => TelemetryEvent._compact({
    'assessment_session_id': assessmentSessionId,
    'completion_status': completionStatus.wire,
    'duration_ms': durationMs,
    'step_count': stepCount,
  });
}

/// The result screen was displayed.
///
/// Emitted by the ordinary results screen **and** the red-flag interrupt
/// screen. Emitting it from only one of them would make its presence or
/// absence a red-flag signal by correlation with `assessment_complete`.
class ResultViewEvent extends TelemetryEvent {
  const ResultViewEvent({
    required this.assessmentSessionId,
    this.presentationContractVersion,
  });

  final String assessmentSessionId;
  final String? presentationContractVersion;

  @override
  String get eventName => 'result_view';

  @override
  Map<String, Object?> toProperties() => TelemetryEvent._compact({
    'assessment_session_id': assessmentSessionId,
    'presentation_contract_version': presentationContractVersion,
  });
}

/// The user ran a facility search.
///
/// There is no `admin_area_code` parameter, no coordinate parameter and no
/// query-text parameter — by construction, not by convention. The area-code
/// mapping is unconfirmed (contract §8) and the field is optional, so this
/// client omits it entirely.
class FacilitySearchEvent extends TelemetryEvent {
  const FacilitySearchEvent({required this.searchMode, this.resultCount});

  final FacilitySearchMode searchMode;
  final int? resultCount;

  @override
  String get eventName => 'facility_search';

  @override
  Map<String, Object?> toProperties() => TelemetryEvent._compact({
    'search_mode': searchMode.wire,
    'result_count': resultCount,
  });
}

/// A facility detail surface was opened.
///
/// [facilityId] must be the `facility_id` field of the versioned facilities
/// artifact — never the name, address, coordinates or phone number.
class FacilityViewEvent extends TelemetryEvent {
  const FacilityViewEvent({required this.facilityId, this.source});

  final String facilityId;
  final FacilityViewSource? source;

  @override
  String get eventName => 'facility_view';

  @override
  Map<String, Object?> toProperties() => TelemetryEvent._compact({
    'facility_id': facilityId,
    'source': source?.wire,
  });
}

/// The user initiated a call to a facility. No phone number is carried.
class FacilityCallEvent extends TelemetryEvent {
  const FacilityCallEvent({required this.facilityId, this.source});

  final String facilityId;
  final FacilityActionSource? source;

  @override
  String get eventName => 'facility_call';

  @override
  Map<String, Object?> toProperties() => TelemetryEvent._compact({
    'facility_id': facilityId,
    'source': source?.wire,
  });
}

/// The user opened directions to a facility. No origin or route data.
class DirectionsOpenEvent extends TelemetryEvent {
  const DirectionsOpenEvent({required this.facilityId, this.source});

  final String facilityId;
  final FacilityActionSource? source;

  @override
  String get eventName => 'directions_open';

  @override
  Map<String, Object?> toProperties() => TelemetryEvent._compact({
    'facility_id': facilityId,
    'source': source?.wire,
  });
}

/// The user took an action on an emergency surface.
///
/// There is no session parameter, deliberately: the contract rejects
/// `assessment_session_id` here because correlating an emergency action back
/// to an assessment would imply a red-flag match.
class EmergencyActionEvent extends TelemetryEvent {
  const EmergencyActionEvent({required this.actionType});

  final EmergencyActionType actionType;

  @override
  String get eventName => 'emergency_action';

  @override
  Map<String, Object?> toProperties() => {'action_type': actionType.wire};
}

/// A library article was opened.
///
/// **Not instrumented in the MVP** — there is no Health Library feature and no
/// article identifiers exist. The type is defined so the contract mirror is
/// complete and the serialisation is covered by tests; building the feature is
/// explicitly out of scope for I1.
class LibraryArticleViewEvent extends TelemetryEvent {
  const LibraryArticleViewEvent({required this.articleId, this.contentVersion});

  final String articleId;
  final String? contentVersion;

  @override
  String get eventName => 'library_article_view';

  @override
  Map<String, Object?> toProperties() => TelemetryEvent._compact({
    'article_id': articleId,
    'content_version': contentVersion,
  });
}

/// The user submitted structured feedback.
///
/// **Not instrumented in the MVP** — there is no feedback UI. There is no
/// free-text parameter and there never will be on this endpoint; if a feedback
/// UI is built with a comment box, that text needs its own reviewed intake
/// path and must not be routed through telemetry.
class FeedbackSubmitEvent extends TelemetryEvent {
  const FeedbackSubmitEvent({required this.rating, this.category});

  final int rating;
  final FeedbackCategory? category;

  @override
  String get eventName => 'feedback_submit';

  @override
  Map<String, Object?> toProperties() =>
      TelemetryEvent._compact({'rating': rating, 'category': category?.wire});
}
