/// Injectable runtime seams for telemetry: clock, ID generation, jitter,
/// connectivity and the app context block.
///
/// Every one of these is a source of nondeterminism, and every one is a thing
/// tests need to pin. They live behind interfaces so `TelemetryService` can be
/// constructed with fakes and assert exact timestamps, exact IDs and exact
/// backoff delays.
library;

import 'dart:io' show Platform;
import 'dart:math';

import 'contract/telemetry_contract.dart';

/// Wall-clock source. Production reads the device clock; tests pin it.
abstract class TelemetryClock {
  DateTime nowUtc();
}

class SystemTelemetryClock implements TelemetryClock {
  const SystemTelemetryClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// Generates `event_id` and `assessment_session_id` values.
abstract class TelemetryIdGenerator {
  /// Matches `[A-Za-z0-9_-]{8,64}`. Called once per event, at occurrence.
  String newEventId();

  /// Matches `[A-Za-z0-9_-]{16,64}`. Called once per assessment attempt.
  String newSessionId();
}

/// Cryptographically random IDs.
///
/// [Random.secure] rather than [Random] deliberately: these IDs are the only
/// correlation handle in the whole payload, and a predictable sequence would
/// let one session's IDs be guessed from another's. Nothing here is derived
/// from device identity, account identity, the clock, or any clinical value —
/// the generator takes no inputs at all.
class SecureTelemetryIdGenerator implements TelemetryIdGenerator {
  SecureTelemetryIdGenerator([Random? random])
    : _random = random ?? Random.secure();

  final Random _random;

  /// The contract's ID alphabet, which is base64url minus padding.
  static const String _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';

  String _id(int length) => String.fromCharCodes(
    List<int>.generate(
      length,
      (_) => _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
    ),
  );

  /// 22 characters ≈ 132 bits. Comfortably inside the 8–64 window and far
  /// beyond any realistic collision risk across a 500-event queue.
  @override
  String newEventId() => _id(22);

  /// 24 characters ≈ 144 bits, inside the 16–64 window.
  @override
  String newSessionId() => _id(24);
}

/// Supplies the multiplier applied to a backoff delay.
///
/// Returns a value in `[0.5, 1.0]` in production ("equal jitter"): enough
/// spread to avoid a synchronised retry stampede after a shared outage,
/// without ever collapsing the delay to zero. Tests inject a fixed value to
/// assert exact delays.
abstract class TelemetryJitter {
  double factor();
}

class RandomTelemetryJitter implements TelemetryJitter {
  RandomTelemetryJitter([Random? random]) : _random = random ?? Random();

  final Random _random;

  @override
  double factor() => 0.5 + (_random.nextDouble() * 0.5);
}

/// Fixed jitter, for deterministic tests and for the no-jitter case.
class FixedTelemetryJitter implements TelemetryJitter {
  const FixedTelemetryJitter(this.value);

  final double value;

  @override
  double factor() => value;
}

/// Whether the device believes it can reach the network.
///
/// The app has no connectivity package and adding one was out of scope for
/// I1 — a new dependency needs approval, and this abstraction does not need
/// one to be correct. [OptimisticConnectivity] simply attempts the request and
/// lets the transport classify a failure as retryable, which is the same
/// outcome a connectivity check would produce and is robust against the
/// captive-portal case a connectivity check gets wrong. The seam exists so a
/// reviewed provider can be dropped in later, and so tests can simulate
/// offline deterministically.
abstract class TelemetryConnectivity {
  Future<bool> isOnline();
}

class OptimisticConnectivity implements TelemetryConnectivity {
  const OptimisticConnectivity();

  @override
  Future<bool> isOnline() async => true;
}

/// The `app` block sent once per batch.
///
/// Deliberately narrow. Device model, install ID, advertising ID, carrier,
/// screen metrics and timezone are all rejected by the contract as identifiers
/// or fingerprinting surfaces, and none of them is collected here.
class TelemetryAppContext {
  const TelemetryAppContext({
    required this.platform,
    required this.appVersion,
    required this.appBuild,
    this.osVersion,
  });

  /// `ios` or `android`.
  final String platform;
  final String appVersion;
  final String appBuild;
  final String? osVersion;

  Map<String, Object?> toJson() => {
    'platform': platform,
    'app_version': appVersion,
    'app_build': appBuild,
    if (osVersion != null) 'os_version': osVersion,
  };

  /// Builds the context from compile-time defines, falling back to the
  /// pubspec-declared version.
  ///
  /// Version and build come from `--dart-define` (`APP_VERSION`, `APP_BUILD`)
  /// so a release build stamps its real values without a new dependency;
  /// `package_info_plus` would have done this too but is a new package and
  /// needs approval.
  static TelemetryAppContext fromPlatform({
    String? platformOverride,
    String? rawOsVersion,
  }) {
    const definedVersion = String.fromEnvironment(
      'APP_VERSION',
      defaultValue: '1.0.0',
    );
    const definedBuild = String.fromEnvironment('APP_BUILD', defaultValue: '1');
    return TelemetryAppContext(
      platform: platformOverride ?? (Platform.isIOS ? 'ios' : 'android'),
      appVersion: definedVersion,
      appBuild: definedBuild,
      osVersion: normaliseOsVersion(
        rawOsVersion ?? Platform.operatingSystemVersion,
      ),
    );
  }

  /// Reduces a platform OS string to `major[.minor]`.
  ///
  /// The contract rejects full build strings — `17.4.1 (21E236)` must be sent
  /// as `17.4` — because the build suffix narrows the device population enough
  /// to be a fingerprinting signal. Returns null when nothing usable can be
  /// extracted, and `os_version` is then simply omitted; it is optional.
  static String? normaliseOsVersion(String raw) {
    final match = RegExp(r'(\d{1,3})(?:\.(\d{1,3}))?').firstMatch(raw);
    if (match == null) return null;
    final major = match.group(1)!;
    final minor = match.group(2);
    final value = minor == null ? major : '$major.$minor';
    return value.length <= 8 ? value : major;
  }
}

/// Non-sensitive counters for local diagnostics.
///
/// Counts only. No event payloads, no IDs, no field values — a counter cannot
/// leak what it counted. Safe to expose in a debug overlay or a test assertion
/// and safe to leave enabled in a release build, because there is nothing in
/// here worth redacting.
class TelemetryDiagnostics {
  int captureAccepted = 0;
  int droppedOldest = 0;
  int expired = 0;
  int flushAttempts = 0;
  int retries = 0;
  int nonRetryableDrops = 0;
  int corruptedRecordsDiscarded = 0;
  bool sessionDisabled = false;

  /// Accepted captures by event name. Keys are contract event names, which are
  /// fixed vocabulary, not user data.
  final Map<String, int> acceptedByEvent = {};

  /// Local rejections by reason code, from
  /// [TelemetryContract.rejectionReasonCodes]. Never keyed by field value.
  final Map<String, int> rejectedByReason = {};

  void recordAccepted(String eventName) {
    captureAccepted++;
    acceptedByEvent.update(eventName, (v) => v + 1, ifAbsent: () => 1);
  }

  void recordRejected(String reason) {
    rejectedByReason.update(reason, (v) => v + 1, ifAbsent: () => 1);
  }

  /// A snapshot safe to print in any build.
  ///
  /// [queueLength] is passed in rather than read, so this object stays free of
  /// a storage dependency and can be asserted on directly in unit tests.
  Map<String, Object?> snapshot({required int queueLength}) => {
    'queue_length': queueLength,
    'queue_capacity': TelemetryContract.maxQueuedEvents,
    'capture_accepted': captureAccepted,
    'accepted_by_event': Map<String, int>.from(acceptedByEvent),
    'rejected_by_reason': Map<String, int>.from(rejectedByReason),
    'dropped_oldest': droppedOldest,
    'expired': expired,
    'flush_attempts': flushAttempts,
    'retries': retries,
    'non_retryable_drops': nonRetryableDrops,
    'corrupted_records_discarded': corruptedRecordsDiscarded,
    'session_disabled': sessionDisabled,
  };

  void reset() {
    captureAccepted = 0;
    droppedOldest = 0;
    expired = 0;
    flushAttempts = 0;
    retries = 0;
    nonRetryableDrops = 0;
    corruptedRecordsDiscarded = 0;
    sessionDisabled = false;
    acceptedByEvent.clear();
    rejectedByReason.clear();
  }
}
