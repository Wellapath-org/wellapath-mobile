/// The single decision "may Community be offered on this device right now?".
///
/// Two keys must both turn (FEATURE_FLAG_SPEC §1, contract §6):
///
///  1. the compile-time define `COMMUNITY_SCAFFOLD_ENABLED` (default false),
///     together with a non-empty `COMMUNITY_API_BASE_URL` (default empty);
///  2. the server flag from `GET /v1/features`.
///
/// Everything fails closed. A fetch error, a timeout, a malformed body, an
/// unknown mode, `disabled`, or `community_allowed != true` all mean no
/// Community content. Only an allow is cached, in memory, for [cacheTtl]; an
/// error or a deny discards it.
///
/// One refinement, needed because the server only says `allowed: true` to a
/// signed-in, allowlisted account: when the mode is enabled but there is no
/// session, the gate answers [CommunityGateDecision.signInRequired], so the
/// entry row can offer sign-in. No Community content is reachable in that
/// state; after sign-in the gate is asked again, with the token.
library;

import 'package:flutter/foundation.dart';

import '../data/community_http_client.dart';
import 'community_features.dart';

/// Off unless the build passes `--dart-define=COMMUNITY_SCAFFOLD_ENABLED=true`.
const bool kCommunityScaffoldEnabled = bool.fromEnvironment(
  'COMMUNITY_SCAFFOLD_ENABLED',
);

enum CommunityGateDecision {
  /// Nothing Community-related is shown.
  hidden,

  /// The server mode is enabled but nobody is signed in: offer sign-in only.
  signInRequired,

  /// Signed in and allowed: Community may be entered.
  open,
}

/// Why the gate did not open. Only used to word the message a user sees after
/// tapping the entry; it never changes what the gate allows.
enum CommunityUnavailableReason {
  /// Not compiled in, or no Community API configured.
  notConfigured,

  /// The server mode is `disabled` (kill switch) or unknown.
  disabled,

  /// Signed in, mode enabled, but this account is not allowed (allowlist).
  notAllowed,

  /// `/v1/features` could not be fetched or parsed (fail closed).
  unreachable,
}

/// A gate decision plus, when it is [CommunityGateDecision.hidden], why.
@immutable
class CommunityGateResult {
  const CommunityGateResult(this.decision, [this.reason]);

  final CommunityGateDecision decision;
  final CommunityUnavailableReason? reason;
}

class CommunityGate {
  CommunityGate({
    required this.compileTimeEnabled,
    CommunityFeatureSource? source,
    Future<bool> Function()? isSignedIn,
    this.cacheTtl = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _source = source,
       _isSignedIn = isSignedIn,
       _clock = clock ?? DateTime.now;

  /// The production gate. In a default build the compile flag is false (or
  /// the base URL is empty), no source is used and no request is ever made.
  factory CommunityGate.fromEnvironment({
    CommunityFeatureSource? source,
    Future<bool> Function()? isSignedIn,
  }) {
    final bool enabled =
        kCommunityScaffoldEnabled && kCommunityApiBaseUrl.isNotEmpty;
    return CommunityGate(
      compileTimeEnabled: kCommunityScaffoldEnabled,
      source: enabled ? source : null,
      isSignedIn: isSignedIn,
    );
  }

  /// A gate that can never open. Useful as an explicit default.
  factory CommunityGate.closed() {
    return CommunityGate(compileTimeEnabled: false);
  }

  final bool compileTimeEnabled;
  final CommunityFeatureSource? _source;
  final Future<bool> Function()? _isSignedIn;
  final Duration cacheTtl;
  final DateTime Function() _clock;

  DateTime? _allowedUntil;

  /// Whether Community may be entered. [fresh] bypasses the cache (used when
  /// actually entering Community, so the kill switch is honoured at once).
  Future<bool> isOpen({bool fresh = false}) async {
    return await evaluate(fresh: fresh) == CommunityGateDecision.open;
  }

  Future<CommunityGateDecision> evaluate({bool fresh = false}) async {
    return (await check(fresh: fresh)).decision;
  }

  /// [evaluate] with the reason for a [CommunityGateDecision.hidden] result.
  /// The decision is identical to [evaluate]'s in every case.
  Future<CommunityGateResult> check({bool fresh = false}) async {
    if (!compileTimeEnabled) {
      return const CommunityGateResult(
        CommunityGateDecision.hidden,
        CommunityUnavailableReason.notConfigured,
      );
    }
    final CommunityFeatureSource? source = _source;
    if (source == null) {
      return const CommunityGateResult(
        CommunityGateDecision.hidden,
        CommunityUnavailableReason.notConfigured,
      );
    }

    final DateTime now = _clock();
    final DateTime? until = _allowedUntil;
    if (!fresh && until != null && now.isBefore(until)) {
      return const CommunityGateResult(CommunityGateDecision.open);
    }

    _allowedUntil = null;
    try {
      final CommunityFeatures features = await source.fetch();
      if (features.state == CommunityFlagState.disabled) {
        return const CommunityGateResult(
          CommunityGateDecision.hidden,
          CommunityUnavailableReason.disabled,
        );
      }
      if (features.allowed) {
        _allowedUntil = now.add(cacheTtl);
        return const CommunityGateResult(CommunityGateDecision.open);
      }
      final Future<bool> Function()? probe = _isSignedIn;
      if (probe != null && !await probe()) {
        return const CommunityGateResult(CommunityGateDecision.signInRequired);
      }
      return const CommunityGateResult(
        CommunityGateDecision.hidden,
        CommunityUnavailableReason.notAllowed,
      );
    } catch (e) {
      // Fail closed. The error itself is never shown to the user.
      debugPrint('community gate: closed (${e.runtimeType})');
      return const CommunityGateResult(
        CommunityGateDecision.hidden,
        CommunityUnavailableReason.unreachable,
      );
    }
  }

  /// Drops any cached allow — called on a kill-switch response and on
  /// sign-out.
  void invalidate() {
    _allowedUntil = null;
  }
}
