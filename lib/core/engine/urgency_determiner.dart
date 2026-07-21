import 'models/engine_output.dart';

class UrgencyDeterminer {
  const UrgencyDeterminer();

  UrgencyResult determine(
    RedFlagResult redFlagResult,
    ScoringResult scoringResult,
  ) {
    final top = scoringResult.scoredConditions.isNotEmpty
        ? scoringResult.scoredConditions.first
        : null;

    // Priority 1 — global red flag: absolute, cannot be overridden by anything
    if (redFlagResult.redFlagTriggered) {
      return UrgencyResult(
        finalUrgency: 'emergency',
        urgencySource: 'global_red_flag',
        redFlagTriggered: true,
        matchedRuleId: redFlagResult.matchedRuleId,
        topCondition: top?.conditionId,
        urgencyDefaultWas: top?.urgencyDefault,
      );
    }

    // Priority 2 — condition-specific red flag for the top-ranked condition
    if (top != null) {
      for (final override in redFlagResult.conditionSpecificOverrides) {
        final conditionId = override['condition_id'] as String?;
        final overrideUrgency = override['override_urgency'] as String?;
        if (conditionId == top.conditionId && overrideUrgency != null) {
          return UrgencyResult(
            finalUrgency: overrideUrgency,
            urgencySource: 'condition_specific_red_flag',
            redFlagTriggered: false,
            matchedRuleId: override['rule_id'] as String?,
            topCondition: top.conditionId,
            urgencyDefaultWas: top.urgencyDefault,
          );
        }
      }
    }

    // Priority 3 — escalate_emergency demographic modifier on top condition
    if (top != null && top.demographicEffect == 'escalate_emergency') {
      return UrgencyResult(
        finalUrgency: 'emergency',
        urgencySource: 'demographic_escalation',
        redFlagTriggered: false,
        topCondition: top.conditionId,
        urgencyDefaultWas: top.urgencyDefault,
      );
    }

    // Priority 4c — increase_urgency + seasonal modifier → emergency.
    // Checked BEFORE Priority 4a: both branches match on
    // demographicEffect == 'increase_urgency', so the more specific
    // seasonal-combo case must be tested first — otherwise Priority 4a
    // would return early on the one-level escalation and this stronger
    // seasonal escalation would never be reached.
    if (top != null &&
        top.demographicEffect == 'increase_urgency' &&
        top.seasonalModifierApplied != null) {
      return UrgencyResult(
        finalUrgency: 'emergency',
        urgencySource: 'demographic_escalation',
        redFlagTriggered: false,
        topCondition: top.conditionId,
        urgencyDefaultWas: top.urgencyDefault,
      );
    }

    // Priority 4a — increase_urgency demographic modifier alone (no seasonal
    // companion): escalate the top condition's urgency_default one level up.
    if (top != null && top.demographicEffect == 'increase_urgency') {
      return UrgencyResult(
        finalUrgency: _escalateOne(top.urgencyDefault),
        urgencySource: 'demographic_escalation',
        redFlagTriggered: false,
        topCondition: top.conditionId,
        urgencyDefaultWas: top.urgencyDefault,
      );
    }

    // Priority 4b — escalate_urgent demographic modifier on top condition
    if (top != null && top.demographicEffect == 'escalate_urgent') {
      return UrgencyResult(
        finalUrgency: 'urgent',
        urgencySource: 'demographic_escalation',
        redFlagTriggered: false,
        topCondition: top.conditionId,
        urgencyDefaultWas: top.urgencyDefault,
      );
    }

    // Priority 5 — urgency_default of top-ranked condition
    final defaultUrgency = top?.urgencyDefault ?? 'non_urgent';
    return UrgencyResult(
      finalUrgency: defaultUrgency,
      urgencySource: 'urgency_default',
      redFlagTriggered: false,
      topCondition: top?.conditionId,
      urgencyDefaultWas: defaultUrgency,
    );
  }

  // One-level urgency escalation used by Priority 4a.
  String _escalateOne(String urgency) {
    switch (urgency) {
      case 'self_care':
        return 'non_urgent';
      case 'non_urgent':
        return 'urgent';
      default:
        return urgency; // urgent and emergency stay as-is
    }
  }
}
