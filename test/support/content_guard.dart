/// Shared content tripwire for the Learn deck and the Help articles.
///
/// Both surfaces are product education, not clinical content, and both are
/// guarded by the same rule — so the rule lives in one place rather than
/// being copied into two test files that can drift apart.
library;

/// Diagnosis words are only acceptable as a DENIAL — "does not diagnose",
/// "not a diagnosis", "do not include your diagnosis". That is the CDSS
/// disclaimer, or a warning to the reader, and it is the opposite of
/// clinical content. An affirmative use ("we diagnose", "your diagnosis
/// is") is exactly what must never ship without clinical review.
///
/// Negation is scoped to the sentence containing the word, not to a fixed
/// number of characters before it: "Do not include your name, phone number,
/// symptoms, diagnosis or other personal health information" negates at the
/// start of a long sentence, and a denial in a *previous* sentence must not
/// license an affirmative claim in the next one.
///
/// Returns the offending sentence, or null when every occurrence is negated.
String? affirmativeDiagnosisClaim(String text) {
  const List<String> negations = [
    'not ',
    'never ',
    'cannot ',
    "can't ",
    'without ',
    'no ',
  ];
  for (final String sentence in text.split(RegExp(r'[.!?]'))) {
    final String lower = sentence.toLowerCase();
    if (!lower.contains('diagnos')) continue;
    if (!negations.any(lower.contains)) return sentence.trim();
  }
  return null;
}
