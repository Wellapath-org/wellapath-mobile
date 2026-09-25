/// What a feedback submission is, and what it may never contain.
///
/// There is **no production submitter**. [FeedbackSubmitter.none] is the
/// default and it refuses: it sends nothing, saves nothing, queues nothing
/// and reports failure. A mock that pretended to succeed would be worse than
/// no feature at all — people would believe their feedback had been read.
///
/// Tests inject an in-memory submitter to exercise the flow. Production code
/// has no such class, and the UI that calls it is behind
/// `FeatureFlags.feedbackEnabled`, which is off.
///
/// ### The payload, when a backend exists
///
/// [FeedbackPayload] is the whole of it: a rating, a category, an optional
/// comment, the app version and the platform. Deliberately absent, and
/// asserted absent by `test/feedback/feedback_flow_test.dart`: assessment
/// answers, clinical results, location, device identifiers, user
/// identifiers, timestamps precise enough to single someone out, and
/// anything resembling a health record.
library;

import 'package:flutter/foundation.dart';

/// How the experience felt. Three steps, no free scale.
enum FeedbackRating {
  good('Good'),
  okay('Okay'),
  needsImprovement('Needs improvement');

  const FeedbackRating(this.label);

  final String label;
}

/// What the feedback is about.
enum FeedbackCategory {
  easeOfUse('Ease of use'),
  understanding('Understanding the app'),
  findingClinic('Finding a clinic'),
  performance('App performance'),
  accessibility('Accessibility'),
  somethingElse('Something else');

  const FeedbackCategory(this.label);

  final String label;
}

/// The complete outbound shape. Nothing else may be added without a privacy
/// review — see the library comment.
@immutable
class FeedbackPayload {
  const FeedbackPayload({
    required this.rating,
    required this.category,
    required this.appVersion,
    required this.platform,
    this.comment,
  });

  final FeedbackRating rating;
  final FeedbackCategory category;

  /// Optional, and only when the comment field is switched on. The UI warns
  /// against personal or health information; this class does not try to
  /// sanitise prose, because a sanitiser that half-works invites people to
  /// rely on it.
  final String? comment;

  final String appVersion;
  final String platform;

  Map<String, Object?> toJson() => {
    'rating': rating.name,
    'category': category.name,
    if (comment != null && comment!.isNotEmpty) 'comment': comment,
    'app_version': appVersion,
    'platform': platform,
  };
}

/// The result of an attempt. There is no "queued" state on purpose: nothing
/// is held on the device waiting for a connection.
enum FeedbackResult { sent, failed, unavailable }

abstract class FeedbackSubmitter {
  const FeedbackSubmitter();

  /// The production default: no endpoint, so no submission.
  static const FeedbackSubmitter none = _UnavailableSubmitter();

  Future<FeedbackResult> submit(FeedbackPayload payload);
}

class _UnavailableSubmitter extends FeedbackSubmitter {
  const _UnavailableSubmitter();

  @override
  Future<FeedbackResult> submit(FeedbackPayload payload) async =>
      FeedbackResult.unavailable;
}
