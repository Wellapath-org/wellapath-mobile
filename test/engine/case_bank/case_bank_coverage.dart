import 'case_bank_models.dart';

/// Static validation of a delivered case bank against E8.1 exit criteria 1-3.
///
/// Criterion 4 (all 13 global red flag rules exercised) is a property of the
/// run, not the bank, so it lives on [CaseBankReport] instead.
///
/// This checks the bank the data engineer delivered, before a single case is
/// run — a bank that does not meet coverage cannot produce a meaningful pass
/// rate no matter what the engine does.
class CaseBankCoverage {
  const CaseBankCoverage({
    required this.cases,
    required this.knownConditionIds,
    required this.emergencyConditionIds,
    this.minimumCases = 200,
    this.minimumPerCondition = 3,
    this.minimumPerEmergencyCondition = 5,
  });

  final List<CaseBankCase> cases;

  /// Every `condition_id` in the knowledge base artifact.
  final Set<String> knownConditionIds;

  /// Conditions whose `urgency_default` is `emergency`.
  final Set<String> emergencyConditionIds;

  final int minimumCases;
  final int minimumPerCondition;
  final int minimumPerEmergencyCondition;

  Map<String, int> get casesPerCondition {
    final Map<String, int> counts = <String, int>{};
    for (final CaseBankCase c in cases) {
      counts[c.conditionTarget] = (counts[c.conditionTarget] ?? 0) + 1;
    }
    return counts;
  }

  /// Cases whose `condition_target` is not a knowledge base condition id —
  /// edge cases (empty input, conflicting symptoms, red flag sweeps) are
  /// expected to land here rather than being miscounted as condition coverage.
  List<CaseBankCase> get unmappedCases => cases
      .where((CaseBankCase c) => !knownConditionIds.contains(c.conditionTarget))
      .toList();

  Set<String> get conditionsBelowMinimum {
    final Map<String, int> counts = casesPerCondition;
    return knownConditionIds
        .where((String id) => (counts[id] ?? 0) < minimumPerCondition)
        .toSet();
  }

  Set<String> get emergencyConditionsBelowMinimum {
    final Map<String, int> counts = casesPerCondition;
    return emergencyConditionIds
        .where((String id) => (counts[id] ?? 0) < minimumPerEmergencyCondition)
        .toSet();
  }

  int get safetyCriticalCount =>
      cases.where((CaseBankCase c) => c.safetyCritical).length;

  /// Cases the brief says should be marked safety critical (expected urgency
  /// `emergency`) but which the bank left unmarked. Reported rather than
  /// auto-corrected — the flag is the data engineer's to own.
  List<CaseBankCase> get unmarkedSafetyCriticalCases => cases
      .where(
        (CaseBankCase c) =>
            c.expectedUrgency == 'emergency' && !c.safetyCritical,
      )
      .toList();

  bool get meetsMinimumCases => cases.length >= minimumCases;
  bool get meetsPerConditionMinimum => conditionsBelowMinimum.isEmpty;
  bool get meetsEmergencyMinimum => emergencyConditionsBelowMinimum.isEmpty;

  bool get passes =>
      meetsMinimumCases && meetsPerConditionMinimum && meetsEmergencyMinimum;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'total_cases': cases.length,
    'minimum_cases_required': minimumCases,
    'meets_minimum_cases': meetsMinimumCases,
    'conditions_in_kb': knownConditionIds.length,
    'conditions_below_minimum': conditionsBelowMinimum.toList()..sort(),
    'emergency_conditions_in_kb': emergencyConditionIds.length,
    'emergency_conditions_below_minimum':
        emergencyConditionsBelowMinimum.toList()..sort(),
    'unmapped_or_edge_cases': unmappedCases.length,
    'safety_critical_cases': safetyCriticalCount,
    'emergency_cases_not_marked_safety_critical': unmarkedSafetyCriticalCases
        .map((CaseBankCase c) => c.caseId)
        .toList(),
    'passes': passes,
  };
}
