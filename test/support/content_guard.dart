/// Shared content tripwire for the Learn deck, the myth cards and the Help
/// articles.
///
/// All three surfaces are product education, not clinical content, and all
/// three are guarded by the same rules — so the rules live in one place
/// rather than being copied into test files that drift apart.
///
/// ## The invariant
///
/// **These phrasings are approved; everything else goes to clinical review.**
///
/// Diagnosis words are checked against an explicit allowlist of approved
/// shapes, not by detecting negation generically. Two earlier versions tried
/// generic detection — first a 40-character lookback, then a
/// negation-governs-the-word rule — and both leaked, because the ways one
/// clause can end and another begin are open-ended: `and`, `but`, `so`,
/// `yet`, `because`, `while`, `;`, an em dash. Each round closed the examples
/// a reviewer happened to try, which converges on the examples rather than on
/// a rule. An allowlist cannot widen by accident: new copy that says
/// something new fails until a human approves the shape and adds it here.
///
/// Failing this guard does not mean the copy is wrong. It means a person has
/// to look at it.
library;

/// Sentence boundaries include line breaks, not only `.`/`!`/`?`. A claim on
/// its own line with no full stop after it must not borrow the wording of the
/// line above.
final RegExp _sentenceBreak = RegExp(r'[.!?\n\r]');

/// The approved DENIAL shapes — the product saying what it does not do, or
/// telling the reader what not to type. Each is deliberately narrow, and each
/// corresponds to wording a human has signed off.
final List<RegExp> _approvedDenials = [
  // "not a diagnosis", "never a diagnosis", "not your diagnosis"
  RegExp(r'\b(?:not|never)\s+(?:a|an|the|your)\s+diagnos'),

  // "does not diagnose", "will not diagnose", "can not diagnose"
  RegExp(r'\b(?:does|do|did|will|would|can|could|must|should)\s+not\s+diagnos'),

  // "cannot diagnose", and the negated verb list it heads:
  // "cannot examine you, diagnose an illness, prescribe treatment". Each
  // listed item is a short comma-separated verb phrase — no conjunction and
  // no other clause separator may intervene, so "cannot examine you while it
  // diagnoses your illness" is not covered.
  RegExp(r"\b(?:cannot|can't)\s+(?:[a-z]+(?:\s+[a-z]+){0,3},\s+){0,3}diagnos"),

  // A warning about what the reader must not type. The list of things not to
  // include is long by nature, so this shape allows the distance.
  RegExp(r'\bdo not\s+(?:include|enter|share|send|type|write)\b[^.]*diagnos'),
];

/// The approved ATTRIBUTION shapes — naming the qualified human whose job a
/// diagnosis is. Held separately because only these are vetoed when the
/// sentence also puts the product in that role.
final List<RegExp> _approvedAttributions = [
  // "a diagnosis should come from a qualified healthcare professional". A
  // modal is required, so "the diagnosis comes from X" — a claim about where
  // a diagnosis does come from — is not covered.
  RegExp(
    r'\bdiagnos\w*\s+(?:should|must|can only|may only)\s+'
    r'(?:come|be made|be given|be provided|be reached)\s+from\s+[^.]*'
    r'\b(?:healthcare professional|clinician|doctor|medical professional)\b',
  ),

  // Attribution, the other way round: "only a qualified doctor can give you a
  // diagnosis".
  RegExp(
    r'\bonly\b[^.]*'
    r'\b(?:healthcare professional|clinician|doctor|medical professional)\b'
    r'[^.]*\b(?:give|gives|provide|provides|make|makes|reach|reaches)\b'
    r'[^.]*diagnos',
  ),
];

/// An approved attribution must not also put the product in the clinician's
/// role, so "a diagnosis should come from WellaPath and your doctor" stays
/// blocked. Matched on whole words: "an appropriate assessment" must not read
/// as "app".
final RegExp _appAsSubject = RegExp(r'\b(?:wellapath|we|us|our|app)\b');

/// Returns the offending sentence, or null when every sentence containing a
/// diagnosis word matches an approved shape.
String? affirmativeDiagnosisClaim(String text) {
  for (final String sentence in text.split(_sentenceBreak)) {
    final String lower = sentence.toLowerCase();
    if (!lower.contains('diagnos')) continue;
    final bool denied = _approvedDenials.any((RegExp s) => s.hasMatch(lower));
    // A denial may of course name the product ("WellaPath does not
    // diagnose") — the veto applies to attribution only.
    if (denied) continue;
    final bool attributed = _approvedAttributions.any(
      (RegExp s) => s.hasMatch(lower),
    );
    if (attributed && !_appAsSubject.hasMatch(lower)) continue;
    return sentence.trim();
  }
  return null;
}

/// Condition and symptom names. Banned outright on every education surface,
/// **including inside a denial**: "we do not diagnose malaria" still puts a
/// condition in front of the reader, and the engine owns that vocabulary.
///
/// The three phrases at the end are absolute for the same reason — a sentence
/// that needs "what you should take", even to deny it, is a sentence about
/// medication, and a person should approve it.
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
/// Acceptable only in a clause a denial governs ("it cannot ... prescribe
/// treatment"), never as something the app offers.
///
/// "tablet" is here in its medicine sense. Copy that needs the device sense
/// ("on a phone or tablet") will trip this, which is the intended cost of
/// keeping the word listed.
const List<String> clinicalActionVocabulary = [
  'dosage',
  'medicine',
  'tablet',
  'antibiotic',
  'prescribe',
  'treatment',
];

/// Whole-word-ish matching: anchored at the start of a word so "rash" does
/// not fire on "crash", while the deliberate prefixes ("pregnan", "diarrh",
/// "vomit") still reach "pregnancy", "diarrhoea" and "vomiting".
RegExp _termPattern(String term) => RegExp('\\b${RegExp.escape(term)}');

/// Returns the first condition word found in [text], or null. Absolute.
String? conditionVocabularyHit(String text) {
  final String lower = text.toLowerCase();
  for (final String term in conditionVocabulary) {
    if (_termPattern(term).hasMatch(lower)) return term;
  }
  return null;
}

/// Everything that ends the reach of a negation. Unlike the diagnosis
/// allowlist this is a blocklist, so it is deliberately wide: a comma
/// continues a negated list ("cannot examine you, diagnose an illness,
/// prescribe treatment"), and anything else starts a new claim the negation
/// no longer covers.
const String _clauseContinues =
    r'(?:(?![;:()–—]|\b(?:and|but|or|so|yet|however|although|'
    r'though|while|because|since|if|when|after|before|unless|whereas|then|'
    r'only)\b).)*?';

/// Returns the offending sentence when a clinical act appears in a clause no
/// denial governs, or null.
String? unnegatedClinicalAction(String text) {
  for (final String sentence in text.split(_sentenceBreak)) {
    final String lower = sentence.toLowerCase();
    for (final String term in clinicalActionVocabulary) {
      if (!_termPattern(term).hasMatch(lower)) continue;
      final bool governed = RegExp(
        r"\b(?:not|never|cannot|can't|no)\b" +
            _clauseContinues +
            r'\b' +
            RegExp.escape(term),
      ).hasMatch(lower);
      if (!governed) return sentence.trim();
    }
  }
  return null;
}
