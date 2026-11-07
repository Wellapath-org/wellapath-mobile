/// The single decision "may Community be shown on this device right now?".
///
/// Two keys must both turn (`docs/community/FEATURE_FLAG_SPEC.md` §1):
///
///  1. the compile-time define `COMMUNITY_SCAFFOLD_ENABLED` (default false);
///  2. the server flag from `GET /v1/features`.
///
/// Everything fails closed. A fetch error, a timeout, a malformed body, an
/// unknown state, `disabled`, or `community_allowed != true` all mean hidden.
/// Only an allow is cached, in memory, for [cacheTtl]; an error discards it.
library;

import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import 'community_features.dart';

/// Off unless the build passes `--dart-define=COMMUNITY_SCAFFOLD_ENABLED=true`.
const bool kCommunityScaffoldEnabled = bool.fromEnvironment(
  'COMMUNITY_SCAFFOLD_ENABLED',
);

class CommunityGate {
  CommunityGate({
    required this.compileTimeEnabled,
    CommunityFeatureSource? source,
    this.cacheTtl = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _source = source,
       _clock = clock ?? DateTime.now;

  /// The production gate. In a default build the compile flag is false, no
  /// source is constructed and no request is ever made.
  factory CommunityGate.fromEnvironment() {
    return CommunityGate(
      compileTimeEnabled: kCommunityScaffoldEnabled,
      source: kCommunityScaffoldEnabled
          ? RemoteCommunityFeatureSource(() => ApiClient.instance)
          : null,
    );
  }

  /// A gate that can never open. Useful as an explicit default.
  factory CommunityGate.closed() {
    return CommunityGate(compileTimeEnabled: false);
  }

  final bool compileTimeEnabled;
  final CommunityFeatureSource? _source;
  final Duration cacheTtl;
  final DateTime Function() _clock;

  DateTime? _allowedUntil;

  /// Whether Community may be shown. [fresh] bypasses the cache (used when
  /// actually entering Community, so the kill switch is honoured at once).
  Future<bool> isOpen({bool fresh = false}) async {
    if (!compileTimeEnabled) return false;
    final CommunityFeatureSource? source = _source;
    if (source == null) return false;

    final DateTime now = _clock();
    final DateTime? until = _allowedUntil;
    if (!fresh && until != null && now.isBefore(until)) return true;

    _allowedUntil = null;
    try {
      final CommunityFeatures features = await source.fetch();
      if (!features.permitsEntry) return false;
      _allowedUntil = now.add(cacheTtl);
      return true;
    } catch (e) {
      // Fail closed. The error is not shown to the user: Community simply is
      // not there, exactly as in a default build.
      debugPrint('community gate: closed (${e.runtimeType})');
      return false;
    }
  }

  /// Drops any cached allow — called on a kill-switch response.
  void invalidate() {
    _allowedUntil = null;
  }
}
