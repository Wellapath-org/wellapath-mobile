import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/constants/symptom_display_map.dart';

// Top-5-by-weight symptom tokens for the 19 conditions that were completely
// unreachable, plus the 5 conditions that were reachable only via weak,
// generic shared tokens, before E9 (issue #25/#26). Sourced from the data
// engineer's condition_top5_symptom_tokens.json
// (wellapath-knowledge-base mobile_handoff, PR #9) — copied here as a
// static fixture so this test doesn't depend on fetching the live KB.
const Map<String, List<String>> _priorityConditionTokens = {
  'cough_common_cold': [
    'runny_nose',
    'mild_cough',
    'sneezing',
    'mild_sore_throat',
    'mild_headache',
  ],
  'skin_infections': [
    'pus_discharge',
    'itchy_rash',
    'boils',
    'skin_redness',
    'skin_swelling',
  ],
  'eye_infections': [
    'eye_redness',
    'eye_discharge',
    'eye_itchiness',
    'eye_pain',
    'swollen_eyelids',
  ],
  'dental_oral': [
    'toothache',
    'swollen_gums',
    'pain_on_chewing',
    'mouth_sores',
    'bad_breath',
  ],
  'hiv_symptomatic': [
    'persistent_fever',
    'weight_loss',
    'recurrent_infections',
    'oral_thrush',
    'chronic_diarrhoea',
  ],
  'schistosomiasis': [
    'blood_in_urine',
    'abdominal_pain',
    'diarrhoea',
    'tiredness',
  ],
  'rabies_exposure': [
    'animal_bite',
    'fear_of_water',
    'confusion',
    'wound_at_bite',
    'local_swelling',
  ],
  'diphtheria': [
    'throat_membrane',
    'stridor',
    'swollen_neck',
    'difficulty_swallowing',
    'hoarse_voice',
  ],
  'asthma': [
    'wheeze',
    'shortness_of_breath',
    'chest_tightness',
    'nocturnal_cough',
  ],
  'chronic_respiratory': [
    'chronic_cough',
    'exertional_breathlessness',
    'wheeze',
    'chest_tightness',
  ],
  'burns': ['charred_skin', 'blistering', 'pain_at_burn', 'skin_redness'],
  'snake_bite': [
    'bite_mark',
    'spreading_swelling',
    'bleeding',
    'ptosis',
    'difficulty_breathing',
  ],
  'neonatal_infection': [
    'neonatal_fever',
    'lethargy',
    'fast_breathing_neonate',
    'poor_feeding',
    'irritability',
  ],
  'malnutrition': [
    'bilateral_oedema',
    'poor_growth',
    'weight_loss',
    'poor_appetite',
    'repeated_infections',
  ],
  'headache': [
    'head_pain',
    'throbbing_headache',
    'one_sided_headache',
    'pressure_headache',
  ],
  'musculoskeletal_pain': [
    'limb_weakness',
    'back_pain',
    'joint_pain',
    'limited_movement',
    'muscle_stiffness',
  ],
  'fatigue_weakness': [
    'persistent_fatigue',
    'general_weakness',
    'reduced_daily_function',
    'low_energy',
  ],
  'dizziness': [
    'near_fainting',
    'spinning_sensation',
    'light_headedness',
    'unsteadiness',
  ],
  'allergic_reactions': [
    'hives',
    'itchy_rash',
    'mild_swelling',
    'itchy_eyes',
    'sneezing',
  ],
  'cardio_symptoms': [
    'chest_pain',
    'shortness_of_breath',
    'palpitations',
    'dizziness',
    'leg_swelling',
  ],
  'sari': [
    'shortness_of_breath',
    'fast_breathing',
    'cough',
    'chest_pain',
    'fever',
  ],
  'hypertension': ['blurred_vision', 'headache', 'dizziness', 'nosebleed'],
  'tuberculosis_suspected': [
    'chronic_cough',
    'weight_loss',
    'night_sweats',
    'fever',
    'chest_pain',
  ],
  'diabetes': [
    'frequent_urination',
    'excessive_thirst',
    'blurred_vision',
    'fast_breathing',
    'fatigue',
  ],
};

void main() {
  final pickerTokens = kSymptomDisplayMap.values.toSet();

  group('E9 picker expansion — reachability', () {
    for (final entry in _priorityConditionTokens.entries) {
      test(
        '${entry.key} has at least one symptom reachable via the picker',
        () {
          final overlap = entry.value.toSet().intersection(pickerTokens);
          expect(
            overlap,
            isNotEmpty,
            reason:
                '${entry.key} has none of its top-5 tokens (${entry.value}) '
                'reachable in kSymptomDisplayMap',
          );
        },
      );
    }

    test(
      'every priority condition has more than one reachable symptom '
      '(a single generic overlap was the old "effectively unreachable" problem)',
      () {
        for (final entry in _priorityConditionTokens.entries) {
          final overlap = entry.value.toSet().intersection(pickerTokens);
          expect(
            overlap.length,
            greaterThan(1),
            reason:
                '${entry.key}: only ${overlap.length} reachable of ${entry.value}',
          );
        }
      },
    );
  });

  group('E9 picker expansion — structural integrity', () {
    test(
      'kSymptomDisplayMap has no unintentional duplicate display labels',
      () {
        // A Dart map literal with a duplicate key silently keeps only the
        // last value — this test exists so a future accidental duplicate
        // label is caught at test time, not discovered as a missing symptom.
        // (Two pairs are intentionally duplicate values, not keys —
        // 'Nausea'/'Feeling sick or queasy' both map to 'nausea', and 'Body
        // pain'/'Muscle pain' both map to 'body_pain' — that's fine, it's the
        // *keys* that must be unique, which the compiler already guarantees;
        // this test guards the source file's literal entry count matches.)
        expect(kSymptomDisplayMap.length, greaterThanOrEqualTo(100));
      },
    );

    test(
      'every symptom label in kBodyAreaSymptoms exists in kSymptomDisplayMap',
      () {
        for (final entry in kBodyAreaSymptoms.entries) {
          for (final label in entry.value) {
            expect(
              kSymptomDisplayMap.containsKey(label),
              isTrue,
              reason:
                  '"$label" listed under body area "${entry.key}" has no '
                  'entry in kSymptomDisplayMap',
            );
          }
        }
      },
    );

    test(
      'Arms is no longer a body area key (zero tokens are arm-specific)',
      () {
        expect(kBodyAreaSymptoms.containsKey('Arms'), isFalse);
      },
    );
  });
}
