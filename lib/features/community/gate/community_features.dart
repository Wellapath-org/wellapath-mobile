/// The server's answer from `GET /v1/features` (contract §6), and where it
/// comes from.
library;

import 'package:flutter/foundation.dart';

import '../data/community_http_client.dart';

enum CommunityFlagState {
  disabled,
  internal,
  closedBeta,
  public;

  String get wire {
    switch (this) {
      case CommunityFlagState.disabled:
        return 'disabled';
      case CommunityFlagState.internal:
        return 'internal';
      case CommunityFlagState.closedBeta:
        return 'closed_beta';
      case CommunityFlagState.public:
        return 'public';
    }
  }
}

@immutable
class CommunityFeatures {
  const CommunityFeatures({required this.state, required this.allowed});

  /// Strict parse: any missing or mistyped value throws, and an unknown
  /// mode is treated as `disabled` (§6, §13); both mean *hidden*.
  factory CommunityFeatures.fromJson(Map<String, dynamic> json) {
    final Object? rawState = json['community'];
    final Object? rawAllowed = json['community_allowed'];
    if (rawState is! String || rawAllowed is! bool) {
      throw const FormatException('malformed /v1/features response');
    }
    for (final CommunityFlagState s in CommunityFlagState.values) {
      if (s.wire == rawState) {
        return CommunityFeatures(state: s, allowed: rawAllowed);
      }
    }
    return CommunityFeatures.disabled;
  }

  static const CommunityFeatures disabled = CommunityFeatures(
    state: CommunityFlagState.disabled,
    allowed: false,
  );

  final CommunityFlagState state;
  final bool allowed;

  /// `disabled` hides Community whatever `community_allowed` says.
  bool get permitsEntry => state != CommunityFlagState.disabled && allowed;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'community': state.wire,
      'community_allowed': allowed,
    };
  }
}

abstract interface class CommunityFeatureSource {
  /// Fetches the current flag. May throw; the gate treats any throw as hidden.
  Future<CommunityFeatures> fetch();
}

/// A fixed answer, for tests and local development.
class StaticCommunityFeatureSource implements CommunityFeatureSource {
  StaticCommunityFeatureSource(this.features);

  CommunityFeatures features;
  int fetchCount = 0;

  @override
  Future<CommunityFeatures> fetch() async {
    fetchCount++;
    return features;
  }
}

/// A source that always fails — used to exercise fail-closed behaviour.
class FailingCommunityFeatureSource implements CommunityFeatureSource {
  const FailingCommunityFeatureSource();

  @override
  Future<CommunityFeatures> fetch() async {
    throw const CommunityFeatureFetchException('unreachable');
  }
}

class CommunityFeatureFetchException implements Exception {
  const CommunityFeatureFetchException(this.reason);

  final String reason;

  @override
  String toString() => 'CommunityFeatureFetchException($reason)';
}

/// `GET /v1/features` on the Community API (`COMMUNITY_API_BASE_URL`).
/// Constructed only when the compile-time flag is on **and** a base URL is
/// configured, so a default build never calls it.
///
/// Sends the bearer token when a session exists (optional auth, §6); without
/// one, `internal`/`closed_beta` always answer `community_allowed: false`.
class RemoteCommunityFeatureSource implements CommunityFeatureSource {
  RemoteCommunityFeatureSource(this._client);

  final CommunityHttpClient _client;

  static const Duration timeout = Duration(seconds: 5);

  @override
  Future<CommunityFeatures> fetch() async {
    final CommunityResponse response = await _client
        .send(
          const CommunityRequest(
            method: 'GET',
            template: '/v1/features',
            auth: CommunityAuth.optional,
          ),
        )
        .timeout(timeout);
    return CommunityFeatures.fromJson(response.json);
  }
}
