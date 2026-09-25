/// Shared content tripwire for the Learn deck, the myth cards and the Help
/// articles.
///
/// All three surfaces are product education, not clinical content, and all
/// three are guarded by the same rules — so the rules live in one place
/// rather than being copied into test files that drift apart.
///
/// The guard is **fail-closed**: a clinical word is a failure unless the
/// sentence matches one of the narrow, explicitly approved shapes below.
/// Copy that trips it is not necessarily wrong — it needs clinical review,
/// which is the point.
library;

/// Sentence boundaries include line breaks, not only `.`/`!`/`?`. A claim on
/// its own line with no full stop after it must not inherit the negation of
/// the line above.
final RegExp _sentenceBreak = RegExp(r'[.!?\n\r]');

/// A coordinating conjunction ends the reach of a negation: in "is not a
/// substitute for a doctor, **and** it will diagnose your illness" the "not"
/// governs the first claim only.
const String _stillGoverned =
    r'(?:(?!\b(?:and|but|however|although|though|only)\b).)*?';

/// A negation that actually governs [term] — it precedes the word in the
/// same sentence with no conjunction in between. This admits "cannot examine
/// you, diagnose an illness" and "do not include your name, phone number,
/// symptoms, diagnosis", and rejects a negation that has moved on to a
/// different claim before the word appears.
bool _deniedIn(String sentenceLower, String term) => RegExp(
  r"\b(?:not|never|cannot|can't|no)\b" + _stillGoverned + RegExp.escape(term),
).hasMatch(sentenceLower);

/// Naming the human who diagnoses is the other approved shape: "a diagnosis
/// should come from a qualified healthcare professional" attributes the act
/// away from the app rather than claiming it. Both halves are required — an
/// attributing verb *and* a qualified human — so "a clinician would diagnose
/// the cause" and "your diagnosis from the doctor is ready" stay blocked.
final RegExp _attributedToHuman = RegExp(
  r'diagnos\w*[^.]*\b(?:come|comes|made|given|provided|issued)\s+(?:from|by)\b'
  r'[^.]*\b(?:healthcare professional|clinician|doctor|medical professional)\b',
);

/// ...and never while the same sentence also puts the product in that role,
/// so "the diagnosis comes from WellaPath and your doctor" stays blocked.
/// Matched on whole words: "an appropriate assessment" must not read as
/// "app".
final RegExp _appAsSubject = RegExp(r'\b(?:wellapath|we|us|our|app)\b');

/// Diagnosis words are acceptable only as a governed DENIAL ("does not
/// diagnose", "not a diagnosis", "do not include your diagnosis") or as an
/// ATTRIBUTION to a qualified human. An affirmative use by the product
/// ("we diagnose", "your diagnosis is") is exactly what must never ship
/// without clinical review.
///
/// Returns the offending sentence, or null when every occurrence is
/// acceptable.
String? affirmativeDiagnosisClaim(String text) {
  for (final String sentence in text.split(_sentenceBreak)) {
    final String lower = sentence.toLowerCase();
    if (!lower.contains('diagnos')) continue;
    if (_deniedIn(lower, 'diagnos')) continue;
    if (_attributedToHuman.hasMatch(lower) && !_appAsSubject.hasMatch(lower)) {
      continue;
    }
    return sentence.trim();
  }
  return null;
}

/// Condition and symptom names. Banned outright on every education surface,
/// **including inside a denial**: "we do not diagnose malaria" still puts a
/// condition in front of the reader, and the engine owns that vocabulary.
const List<String> conditionVocabulary = [
  'malaria',
  'typhoid',
  'cholera',
  'meningitis',
  'sepsis',
  'pregnan',
  'fever',
  'headache',
  'cough',
  'vomit',
  'diarrh',
  'rash',
  'bleeding',
  'seizure',
  'chest pain',
  'you may have',
  'we think you',
  'you should take',
];

/// Clinical *acts* — what a clinician does, which WellaPath does not.
/// Acceptable only as a governed denial ("it cannot ... prescribe
/// treatment"), never as something the app offers.
const List<String> clinicalActionVocabulary = [
  'dosage',
  'medicine',
  'tablet',
  'antibiotic',
  'prescribe',
  'treatment',
];

/// Returns the first condition word found in [text], or null. Absolute.
String? conditionVocabularyHit(String text) {
  final String lower = text.toLowerCase();
  for (final String term in conditionVocabulary) {
    if (lower.contains(term)) return term;
  }
  return null;
}

/// Returns the offending sentence when a clinical act appears without a
/// denial governing it, or null.
String? unnegatedClinicalAction(String text) {
  for (final String sentence in text.split(_sentenceBreak)) {
    final String lower = sentence.toLowerCase();
    for (final String term in clinicalActionVocabulary) {
      if (lower.contains(term) && !_deniedIn(lower, term)) {
        return sentence.trim();
      }
    }
  }
  return null;
}
