/// Second-layer defensive validation for telemetry.
///
/// The typed event classes in `contract/telemetry_event.dart` are the primary
/// control: a caller cannot *express* a prohibited field. This layer exists to
/// catch a programming error in that first layer — a new event type added
/// carelessly, a hand-built map, a contract mirror edited without re-running
/// the parity test. It runs twice on every event: once **before persistence**
/// and again **before transmission**, so a value cannot reach the queue or the
/// network by slipping past a single call site.
///
/// It never silently strips or rewrites anything. Silent repair would hide the
/// very bug this layer is here to surface. A failure fails the capture: the
/// event is not enqueued, a non-sensitive diagnostic counter is incremented
/// against a fixed reason code, and the caller is unaffected.
///
/// Reason codes are the backend's own vocabulary
/// ([TelemetryContract.rejectionReasonCodes]) so a local rejection and a
/// server rejection can be compared directly.
library;

import 'contract/telemetry_contract.dart';

/// Outcome of validating one event or envelope.
class TelemetryValidation {
  const TelemetryValidation.ok() : reason = null, field = null;
  const TelemetryValidation.rejected(this.reason, {this.field});

  /// One of [TelemetryContract.rejectionReasonCodes]; null when valid.
  final String? reason;

  /// The offending field name — populated **only** when the name is itself
  /// allowlisted by the contract. A key the client invented is never carried
  /// here, mirroring the backend's rule that an invented key is never echoed.
  final String? field;

  bool get isValid => reason == null;
}

/// Validates serialised telemetry against contract v1.0 and a prohibited-data
/// denylist.
abstract final class PrivacyGuard {
  const PrivacyGuard._();

  /// Every field name the contract declares, anywhere. A key in this set is
  /// structurally known and is checked against its spec rather than the
  /// denylist; a key outside it is denylist-classified first.
  ///
  /// Without this exemption the denylist would reject `event_name` (contains
  /// the token `name`) — the allowlist has to win for names it owns.
  static const Set<String> _contractKnownKeys = {
    'contract_version', 'sent_at', 'app', 'events', //
    'platform', 'app_version', 'app_build', 'os_version',
    'event_name', 'event_id', 'client_ts',
    'launch_type', 'is_first_launch',
    'assessment_session_id', 'flow_version', 'entry_point',
    'step_index', 'step_count',
    'completion_status', 'duration_ms',
    'presentation_contract_version',
    'search_mode', 'admin_area_code', 'result_count',
    'facility_id', 'source',
    'action_type',
    'article_id', 'content_version',
    'rating', 'category',
  };

  /// Keys that indicate an attempt to smuggle arbitrary data through a bag.
  static const Set<String> _containerKeys = {
    'metadata', 'meta', 'context', 'ctx', 'extra', 'extras', 'properties', //
    'props', 'data', 'payload', 'attributes', 'attrs', 'params', 'custom',
    'fields', 'tags', 'dimensions', 'traits',
  };

  /// Prototype-pollution and other structurally unsafe keys.
  static const Set<String> _unsafeKeys = {
    '__proto__', 'constructor', 'prototype', '__defineGetter__', //
    '__defineSetter__', '__lookupGetter__', '__lookupSetter__',
  };

  /// Word-level denylist, matched against the tokens of a non-contract key.
  ///
  /// Grouped by the prohibition each token serves so a future reader can tell
  /// which rule a rejection came from.
  static const Set<String> _prohibitedTokens = {
    // Symptoms, complaints and the assessment path
    'symptom', 'symptoms', 'complaint', 'complaints', 'presenting', //
    'answer', 'answers', 'response', 'responses', 'selection', 'selections',
    'question', 'questions', 'qid', 'step', 'path', 'history', 'alias',
    'aliases', 'token', 'tokens', 'vocabulary',
    // Clinical output
    'condition', 'conditions', 'diagnosis', 'diagnoses', 'differential',
    'differentials', 'prediction', 'predictions', 'likelihood', 'result',
    'results', 'outcome', 'score', 'scores', 'scoring', 'weight', 'weights',
    'contribution', 'contributions', 'urgency', 'triage', 'severity',
    'redflag', 'redflags', 'flag', 'flags', 'rule', 'rules', 'kb',
    'explanation', 'recommendation',
    // Sensitive clinical status
    'pregnancy', 'pregnant', 'gestation', 'hiv', 'sti', 'mental',
    // Free text
    'narrative', 'narratives', 'note', 'notes', 'comment', 'comments',
    'freetext', 'text', 'body', 'message', 'description', 'reason',
    // Identity
    'name', 'firstname', 'lastname', 'surname', 'fullname', 'email', 'mail',
    'phone', 'msisdn', 'mobile', 'tel', 'telephone', 'contact', 'account',
    'user', 'userid', 'uid', 'patient', 'subject', 'profile', 'dob',
    'birthdate', 'nin', 'bvn',
    // Location
    'latitude', 'longitude', 'lat', 'lon', 'lng', 'coord', 'coords',
    'coordinate', 'coordinates', 'geo', 'geolocation', 'gps', 'address',
    'street', 'postcode', 'zip', 'ward', 'lga', 'query', 'q',
    // Credentials
    'authorization', 'auth', 'bearer', 'cookie', 'cookies', 'secret',
    'secrets', 'password', 'passwd', 'credential', 'credentials', 'apikey',
    'jwt', 'session', 'sessionid', 'csrf', 'signature', 'header', 'headers',
    // Device identity and fingerprinting
    'device', 'deviceid', 'imei', 'imsi', 'serial', 'androidid', 'idfa',
    'idfv', 'gaid', 'adid', 'advertising', 'fingerprint', 'installid',
    'install', 'carrier', 'timezone', 'locale', 'screen', 'useragent',
  };

  // ── Value-shape detectors ─────────────────────────────────────────────────

  /// A coordinate pair, or a lone decimal precise enough to be one.
  ///
  /// Requires 4+ fractional digits so ordinary version strings (`1.0`, `2.4`,
  /// `1.4.2`) can never match — those top out at one fractional group.
  static final RegExp _coordinateLike = RegExp(
    r'^-?\d{1,3}\.\d{4,}\s*[,;]\s*-?\d{1,3}\.\d{4,}$|^-?\d{1,3}\.\d{6,}$',
  );

  static final RegExp _emailLike = RegExp(r'^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$');

  /// International (`+2348…`) or bare national-length digit runs.
  ///
  /// Applied to event property values only. `app_build` is digits-only and up
  /// to 10 characters, so it would collide — it lives in the app context and
  /// is validated on a different path, never through here.
  static final RegExp _phoneLike = RegExp(r'^\+\d{7,15}$|^\d{10,15}$');

  /// Three base64url segments — a JWT or similarly structured credential.
  static final RegExp _jwtLike = RegExp(
    r'^[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}$',
  );

  /// No allowlisted value in contract v1.0 legitimately contains whitespace —
  /// every one is an enum, an opaque ID, a dotted version or an ISO timestamp.
  /// Whitespace therefore means prose got in.
  static final RegExp _whitespace = RegExp(r'\s');

  // ── Public API ────────────────────────────────────────────────────────────

  /// Validates one fully serialised event: the three common fields plus its
  /// event-specific properties, flat, wire-named.
  ///
  /// [now] is injected so expiry is testable and so the queue can re-check an
  /// event's age at flush time against the same rule.
  static TelemetryValidation validateEvent(
    Map<String, Object?> event, {
    required DateTime now,
  }) {
    final eventName = event['event_name'];
    if (eventName is! String) {
      return const TelemetryValidation.rejected(
        'missing_required_property',
        field: 'event_name',
      );
    }
    final spec = TelemetryContract.events[eventName];
    if (spec == null) {
      return const TelemetryValidation.rejected('unknown_event');
    }

    // Keys first: an unsafe or prohibited key is rejected before any of its
    // constraints are considered, so a hostile key never reaches a code path
    // that might log it.
    for (final key in event.keys) {
      final keyVerdict = _classifyKey(key);
      if (keyVerdict != null) return TelemetryValidation.rejected(keyVerdict);
    }

    // Common fields.
    for (final common in TelemetryContract.commonEventFields) {
      final verdict = _checkField(common, event[common.field]);
      if (!verdict.isValid) return verdict;
    }

    final clientTs = event['client_ts'] as String;
    final tsVerdict = validateClientTimestamp(clientTs, now: now);
    if (!tsVerdict.isValid) return tsVerdict;

    // Event-specific properties: every key present must be declared, and every
    // declared-required property must be present.
    const commonNames = {'event_name', 'event_id', 'client_ts'};
    for (final entry in event.entries) {
      if (commonNames.contains(entry.key)) continue;
      final propertySpec = spec.property(entry.key);
      if (propertySpec == null) {
        // The key survived the denylist but this event does not declare it.
        return const TelemetryValidation.rejected('unknown_property');
      }
      final verdict = _checkField(propertySpec, entry.value);
      if (!verdict.isValid) return verdict;
    }
    for (final propertySpec in spec.properties) {
      if (propertySpec.required && !event.containsKey(propertySpec.field)) {
        return TelemetryValidation.rejected(
          'missing_required_property',
          field: propertySpec.field,
        );
      }
    }

    return const TelemetryValidation.ok();
  }

  /// Validates the app context block sent once per batch.
  static TelemetryValidation validateAppContext(Map<String, Object?> app) {
    for (final key in app.keys) {
      final keyVerdict = _classifyKey(key);
      if (keyVerdict != null) return TelemetryValidation.rejected(keyVerdict);
      if (!_contractKnownKeys.contains(key)) {
        return const TelemetryValidation.rejected('unknown_property');
      }
    }
    for (final spec in TelemetryContract.appContext) {
      final verdict = _checkField(spec, app[spec.field]);
      if (!verdict.isValid) return verdict;
    }
    return const TelemetryValidation.ok();
  }

  /// Enforces the 30-day age ceiling and the 24-hour future-skew ceiling.
  static TelemetryValidation validateClientTimestamp(
    String clientTs, {
    required DateTime now,
  }) {
    final parsed = DateTime.tryParse(clientTs);
    if (parsed == null) {
      return const TelemetryValidation.rejected(
        'invalid_format',
        field: 'client_ts',
      );
    }
    final ageMs = now.toUtc().difference(parsed.toUtc()).inMilliseconds;
    if (ageMs > TelemetryContract.maxClientTimestampAgeMs ||
        -ageMs > TelemetryContract.maxClientTimestampSkewMs) {
      return const TelemetryValidation.rejected(
        'timestamp_out_of_range',
        field: 'client_ts',
      );
    }
    return const TelemetryValidation.ok();
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  /// Returns a rejection reason for [key], or null if the key is acceptable.
  static String? _classifyKey(String key) {
    final lower = key.toLowerCase();
    if (_unsafeKeys.contains(lower)) return 'unsafe_key';
    if (_containerKeys.contains(lower)) return 'prohibited_container';
    // A name the contract owns wins over the token denylist — `event_name`
    // must not be rejected for containing `name`.
    if (_contractKnownKeys.contains(key)) return null;

    // Two passes, because separators are not a reliable word boundary.
    // `android_id` splits into `android` + `id`, and neither is denylisted on
    // its own — `id` is far too generic to denylist — so the compound form has
    // to be checked as well. Found by the adversarial test, not by inspection.
    final collapsed = lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (_prohibitedTokens.contains(collapsed)) return 'prohibited_field';

    for (final token in lower.split(RegExp(r'[^a-z0-9]+'))) {
      if (token.isEmpty) continue;
      if (_prohibitedTokens.contains(token)) return 'prohibited_field';
    }
    return null;
  }

  static TelemetryValidation _checkField(
    TelemetryFieldSpec spec,
    Object? value,
  ) {
    if (value == null) {
      if (spec.required) {
        return TelemetryValidation.rejected(
          'missing_required_property',
          field: spec.field,
        );
      }
      return const TelemetryValidation.ok();
    }

    if (value is Map || value is Iterable) {
      return TelemetryValidation.rejected(
        'nested_value_not_allowed',
        field: spec.field,
      );
    }

    switch (spec.type) {
      case TelemetryFieldType.boolean:
        if (value is! bool) {
          return TelemetryValidation.rejected(
            'invalid_type',
            field: spec.field,
          );
        }
        return const TelemetryValidation.ok();

      case TelemetryFieldType.integer:
        if (value is! int) {
          return TelemetryValidation.rejected(
            'invalid_type',
            field: spec.field,
          );
        }
        if ((spec.minimum != null && value < spec.minimum!) ||
            (spec.maximum != null && value > spec.maximum!)) {
          return TelemetryValidation.rejected(
            'value_out_of_range',
            field: spec.field,
          );
        }
        return const TelemetryValidation.ok();

      case TelemetryFieldType.enumeration:
        if (value is! String) {
          return TelemetryValidation.rejected(
            'invalid_type',
            field: spec.field,
          );
        }
        if (!spec.allowedValues!.contains(value)) {
          return TelemetryValidation.rejected(
            'invalid_enum_value',
            field: spec.field,
          );
        }
        return const TelemetryValidation.ok();

      case TelemetryFieldType.string:
        if (value is! String) {
          return TelemetryValidation.rejected(
            'invalid_type',
            field: spec.field,
          );
        }
        // Shape before format: a coordinate pair in `facility_id` would also
        // fail the pattern, but `prohibited_value_shape` is the honest reason
        // and is what the backend reports.
        final shape = _classifyValueShape(value);
        if (shape != null) {
          return TelemetryValidation.rejected(shape, field: spec.field);
        }
        if (spec.maxLength != null && value.length > spec.maxLength!) {
          return TelemetryValidation.rejected(
            'value_too_long',
            field: spec.field,
          );
        }
        final pattern = spec.anchoredPattern;
        if (pattern != null && !pattern.hasMatch(value)) {
          return TelemetryValidation.rejected(
            'invalid_format',
            field: spec.field,
          );
        }
        return const TelemetryValidation.ok();
    }
  }

  /// Returns `prohibited_value_shape` if [value] looks like prohibited data
  /// regardless of which field it arrived in, else null.
  static String? _classifyValueShape(String value) {
    if (value.isEmpty) return null;
    if (_whitespace.hasMatch(value)) return 'prohibited_value_shape';
    if (_coordinateLike.hasMatch(value)) return 'prohibited_value_shape';
    if (_emailLike.hasMatch(value)) return 'prohibited_value_shape';
    if (_phoneLike.hasMatch(value)) return 'prohibited_value_shape';
    if (_jwtLike.hasMatch(value)) return 'prohibited_value_shape';
    return null;
  }
}
