/// Shared fixtures and fakes for the telemetry tests.
library;

import 'dart:convert';
import 'dart:io';

import 'package:wellapath_mobile/core/telemetry/contract/telemetry_event.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_queue.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_runtime.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_service.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_transport.dart';

/// The backend contract artifacts, vendored from `wellapath-backend` at merge
/// commit 5e13379f19c53ec90cee7958dc029d908c342dcd (PR #29).
const String backendContractCommit = '5e13379f19c53ec90cee7958dc029d908c342dcd';

Map<String, Object?> loadContractArtifact(String name) {
  final file = File('test/fixtures/contracts/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

/// A pinned clock.
class FakeClock implements TelemetryClock {
  FakeClock(this._now);

  DateTime _now;

  void advance(Duration by) => _now = _now.add(by);
  set now(DateTime value) => _now = value;

  @override
  DateTime nowUtc() => _now.toUtc();
}

/// Sequential, predictable IDs so a test can assert an exact value.
class FakeIdGenerator implements TelemetryIdGenerator {
  int eventCounter = 0;
  int sessionCounter = 0;

  @override
  String newEventId() => 'evt_${(eventCounter++).toString().padLeft(16, '0')}';

  @override
  String newSessionId() =>
      'ses_${(sessionCounter++).toString().padLeft(20, '0')}';
}

/// A transport that replays a scripted list of results and records what it was
/// asked to send.
class FakeTransport implements TelemetryTransport {
  FakeTransport(this.script);

  /// Consumed in order. The last entry repeats once exhausted.
  final List<TelemetryTransportResult> script;

  final List<Map<String, Object?>> sent = [];
  int callCount = 0;

  /// Event IDs from every request, in order, including retries.
  List<List<String>> get sentEventIds => sent
      .map(
        (envelope) => (envelope['events'] as List)
            .cast<Map<String, Object?>>()
            .map((e) => e['event_id'] as String)
            .toList(),
      )
      .toList();

  @override
  Future<TelemetryTransportResult> send(Map<String, Object?> envelope) async {
    // Deep-copy: the service reuses payload maps across retries, and a test
    // asserting on `sent` must see what was sent at the time, not the latest
    // state of a shared object.
    sent.add(jsonDecode(jsonEncode(envelope)) as Map<String, Object?>);
    final result = script[callCount.clamp(0, script.length - 1)];
    callCount++;
    return result;
  }
}

const TelemetryTransportResult accepted = TelemetryTransportResult(
  disposition: TelemetryDisposition.accepted,
  statusCode: 202,
);

const TelemetryTransportResult retryable = TelemetryTransportResult(
  disposition: TelemetryDisposition.retryable,
  statusCode: 500,
);

const TelemetryTransportResult rateLimited = TelemetryTransportResult(
  disposition: TelemetryDisposition.retryable,
  statusCode: 429,
);

const TelemetryTransportResult nonRetryable = TelemetryTransportResult(
  disposition: TelemetryDisposition.nonRetryable,
  statusCode: 400,
  reasonCode: 'invalid_envelope',
);

const TelemetryTransportResult telemetryDisabled = TelemetryTransportResult(
  disposition: TelemetryDisposition.disableSession,
  statusCode: 503,
  reasonCode: 'telemetry_disabled',
);

/// A network failure, as the transport reports one.
const TelemetryTransportResult networkFailure = TelemetryTransportResult(
  disposition: TelemetryDisposition.retryable,
);

const TelemetryAppContext testAppContext = TelemetryAppContext(
  platform: 'android',
  appVersion: '1.4.2',
  appBuild: '204',
);

/// Records the delays a flush asked for, and returns instantly.
class RecordingSleeper {
  final List<Duration> delays = [];

  Future<void> call(Duration duration) async => delays.add(duration);
}

/// One valid instance of every allowlisted event, for serialisation and
/// schema-conformance tests.
///
/// Includes `library_article_view` and `feedback_submit`, which the app never
/// emits — their serialisation is still covered so the contract mirror stays
/// honest and so the events are ready if those features are built.
List<TelemetryEvent> allEventFixtures() => const [
  AppOpenEvent(launchType: LaunchType.cold, isFirstLaunch: true),
  AppOpenEvent(launchType: LaunchType.warm),
  AssessmentStartEvent(
    assessmentSessionId: 'ses_00000000000000000001',
    flowVersion: '1.0',
    entryPoint: AssessmentEntryPoint.home,
  ),
  AssessmentStepViewEvent(
    assessmentSessionId: 'ses_00000000000000000001',
    stepIndex: 0,
  ),
  AssessmentCompleteEvent(
    assessmentSessionId: 'ses_00000000000000000001',
    completionStatus: CompletionStatus.completed,
    durationMs: 90000,
    stepCount: 8,
  ),
  AssessmentCompleteEvent(
    assessmentSessionId: 'ses_00000000000000000001',
    completionStatus: CompletionStatus.abandoned,
  ),
  ResultViewEvent(
    assessmentSessionId: 'ses_00000000000000000001',
    presentationContractVersion: '1.0',
  ),
  FacilitySearchEvent(searchMode: FacilitySearchMode.nearby, resultCount: 12),
  FacilitySearchEvent(searchMode: FacilitySearchMode.manualArea),
  FacilityViewEvent(facilityId: 'ng_lag_001', source: FacilityViewSource.map),
  FacilityCallEvent(
    facilityId: 'ng_lag_001',
    source: FacilityActionSource.facilityDetail,
  ),
  DirectionsOpenEvent(
    facilityId: 'ng_lag_001',
    source: FacilityActionSource.searchResults,
  ),
  EmergencyActionEvent(actionType: EmergencyActionType.callEmergencyNumber),
  LibraryArticleViewEvent(articleId: 'art_001', contentVersion: '2.4'),
  FeedbackSubmitEvent(rating: 4, category: FeedbackCategory.usability),
];

/// Serialises [event] the way `TelemetryService.capture` does.
Map<String, Object?> serialiseEvent(
  TelemetryEvent event, {
  String eventId = 'evt_0000000000000001',
  DateTime? clientTs,
}) => {
  'event_name': event.eventName,
  'event_id': eventId,
  'client_ts': DefaultTelemetryService.isoUtc(
    clientTs ?? DateTime.utc(2026, 8, 11, 9, 1, 14, 639),
  ),
  ...event.toProperties(),
};

/// Builds a queue backed by memory, wired to [diagnostics].
TelemetryQueue memoryQueue({
  required TelemetryClock clock,
  required TelemetryDiagnostics diagnostics,
  int capacity = 500,
  TelemetryQueueStore? store,
}) => TelemetryQueue(
  store: store ?? InMemoryTelemetryQueueStore(),
  clock: clock,
  diagnostics: diagnostics,
  capacity: capacity,
);
