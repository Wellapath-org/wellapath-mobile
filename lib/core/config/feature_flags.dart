/// Compile-time switches for features whose backend does not exist yet.
///
/// Both default to **off**, and both fail closed: an absent, misspelled or
/// malformed define leaves the feature disabled. Nothing here reads
/// configuration at runtime, so a flag cannot be flipped by a server, a
/// cached response or a preference.
///
/// The rule these encode: **a control that cannot do its job must not be on
/// screen.** Feedback has no endpoint and support chat has no operating
/// process, so in an ordinary build neither is reachable — no greyed-out
/// button, no "coming soon" row, no form that pretends to send. The screens
/// exist, fully built and tested, waiting for the day the backend does.
library;

abstract final class FeatureFlags {
  /// Whether the feedback flow may be reached and submitted.
  ///
  /// Off in every ordinary build. When it is eventually turned on, a real
  /// submission handler must be supplied too — the production default sends
  /// nothing (see `FeedbackSubmitter.none`), so enabling the flag alone
  /// cannot create a fake "thanks, we got it".
  static const bool feedbackEnabled = bool.fromEnvironment('FEEDBACK_ENABLED');

  /// Whether the support-chat entry point is shown.
  ///
  /// Off until there is a backend AND a staffed operating process with
  /// published hours. The design exists so it can be reviewed; it is not
  /// reachable.
  static const bool supportChatEnabled = bool.fromEnvironment(
    'SUPPORT_CHAT_ENABLED',
  );
}
