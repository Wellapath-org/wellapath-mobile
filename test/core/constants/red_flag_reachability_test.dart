import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/constants/symptom_display_map.dart';

/// E9 — can a user actually *report* a universal danger sign?
///
/// The case bank exercises all 13 global red flag rules by feeding tokens
/// straight to the engine, so it cannot see whether the UI lets a user select
/// those tokens in the first place. Found during E9.3 demo 1: `seizures` was
/// in [kSymptomDisplayMap] but under no body area, reachable only through the
/// picker's "Show all symptoms" fallback.
///
/// A rule that cannot be triggered from the UI is not a safety net.

Set<String> _globalRedFlagTokens() {
  final File file = File('test/fixtures/artifacts/rules.ng.v2.2.json');
  final Map<String, dynamic> json =
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return (json['rules'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where((Map<String, dynamic> r) {
        final Object? appliesTo = r['applies_to'];
        return appliesTo is List && appliesTo.contains('all');
      })
      .map((Map<String, dynamic> r) => r['token'] as String)
      .toSet();
}

/// Tokens selectable by walking into a body area — the path a user actually
/// takes. Excludes the "Show all symptoms" fallback.
Set<String> _tokensReachableByBodyArea() {
  final Set<String> tokens = <String>{};
  for (final List<String> labels in kBodyAreaSymptoms.values) {
    for (final String label in labels) {
      final String? token = kSymptomDisplayMap[label];
      if (token != null) tokens.add(token);
    }
  }
  return tokens;
}

void main() {
  test('seizures is reachable from the Head body area', () {
    expect(
      kBodyAreaSymptoms['Head'],
      contains('Seizures'),
      reason:
          'Seizures is the canonical universal danger sign — a caregiver '
          'looking under Head for convulsions must find it',
    );
    expect(kSymptomDisplayMap['Seizures'], 'seizures');
    expect(_tokensReachableByBodyArea(), contains('seizures'));
  });

  test('every label listed under a body area resolves to a token', () {
    final List<String> unresolved = <String>[];
    kBodyAreaSymptoms.forEach((String area, List<String> labels) {
      for (final String label in labels) {
        if (!kSymptomDisplayMap.containsKey(label)) {
          unresolved.add('$area/$label');
        }
      }
    });

    expect(unresolved, isEmpty, reason: 'labels with no display map entry');
  });

  test('ALL 13 global red flag tokens are selectable in the picker', () {
    // The gap this closes: 12 of the 13 were absent from kSymptomDisplayMap
    // entirely, so no UI path could reach them. Display names come from the
    // data engineer's red_flag_display_map.json.
    final Set<String> selectable = kSymptomDisplayMap.values.toSet();
    final Set<String> missing = _globalRedFlagTokens().difference(selectable);

    expect(missing, isEmpty, reason: 'not selectable by any UI path');
  });

  test('ALL 13 global red flag tokens are reachable via a body area', () {
    // Stronger than the above: reachable by walking into a body area, not
    // only through the picker's "Show all symptoms" fallback.
    final Set<String> missing = _globalRedFlagTokens().difference(
      _tokensReachableByBodyArea(),
    );

    expect(missing, isEmpty, reason: 'not reachable from any body area');
  });
}
