/// Scoring determinism across the full 239-case bank.
///
/// LOCKED PRINCIPLE #3 puts scoring on-device; a clinical regression is only
/// evidence if the same inputs produce the same outputs every run. Iteration
/// order over a map, a tie broken by insertion order, or an accumulator that
/// depends on which controller instance ran first would all leave the pass
/// rate intact while making any individual sign-off unreproducible.
///
/// This runs the whole bank twice through independently constructed engines
/// and requires the two reports to be identical, field for field — not merely
/// equal in pass count.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'case_bank/artifact_fixtures.dart';
import 'case_bank/case_bank_models.dart';
import 'case_bank/case_bank_runner.dart';

const String _fixturePath = 'test/fixtures/case_bank_v1.json';

CaseBankRunner _freshRunner(PinnedArtifacts artifacts) => CaseBankRunner(
  rules: artifacts.rules,
  tokenDictionary: artifacts.tokenDictionary,
  knowledgeBase: artifacts.conditions,
  configMetadata: artifacts.configMetadata,
  wiring: EngineWiring.asShipped,
);

void main() {
  group('scoring determinism', () {
    late PinnedArtifacts artifacts;
    late List<CaseBankCase> cases;

    setUpAll(() {
      artifacts = loadPinnedArtifacts();
      cases = parseCaseBank(jsonDecode(File(_fixturePath).readAsStringSync()));
    });

    test('the bank loaded for this run holds all 239 cases', () {
      // Guards the two tests below from silently proving determinism over an
      // empty or truncated list.
      expect(cases, hasLength(239));
    });

    test('two independent runs produce identical reports', () {
      final String first = jsonEncode(_freshRunner(artifacts).runAll(cases));
      final String second = jsonEncode(_freshRunner(artifacts).runAll(cases));

      expect(
        second,
        first,
        reason:
            'The engine produced different output for identical input across '
            'two runs. Scoring must be deterministic for a case bank result '
            'to be reproducible evidence rather than a snapshot.',
      );
    });

    test('re-running a single case on a warm engine is stable', () {
      // The runner caches one EngineController per season and reuses it, so a
      // case run after 238 others must still return what it returns alone.
      // This is where accumulated state would show up.
      final CaseBankRunner runner = _freshRunner(artifacts);
      final List<CaseRunResult> warm = runner.runAll(cases).results;

      for (final CaseBankCase testCase in cases) {
        final CaseRunResult repeat = runner.runCase(testCase);
        final CaseRunResult original = warm.firstWhere(
          (CaseRunResult r) => r.testCase.caseId == testCase.caseId,
        );

        expect(
          jsonEncode(repeat.toJson()),
          jsonEncode(original.toJson()),
          reason:
              '${testCase.caseId} changed on re-run against the same engine '
              'instance — the engine is carrying state between cases.',
        );
      }
    });

    test('ranked conditions keep a stable order', () {
      // Top-condition assertions in the bank are only meaningful if ties do
      // not reshuffle between runs.
      final CaseBankRunner a = _freshRunner(artifacts);
      final CaseBankRunner b = _freshRunner(artifacts);

      for (final CaseBankCase testCase in cases) {
        final List<String> first = a
            .outputFor(testCase)
            .topCauses
            .map((Map<String, dynamic> c) => c['condition_id'] as String)
            .toList();
        final List<String> second = b
            .outputFor(testCase)
            .topCauses
            .map((Map<String, dynamic> c) => c['condition_id'] as String)
            .toList();

        expect(
          second,
          first,
          reason:
              '${testCase.caseId} ranked its conditions differently '
              'across two runs.',
        );
      }
    });
  });
}
