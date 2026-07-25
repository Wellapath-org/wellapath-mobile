/// Runs [attempt], retrying with exponential backoff on failure.
///
/// Every attempt is capped by [perAttemptTimeout] — a hard wall-clock limit
/// independent of whatever timeout the underlying call configures itself.
/// This matters because e.g. Dio's `receiveTimeout` only measures the gap
/// *between* received chunks, not total transfer duration, and can never
/// fire on a connection that keeps trickling data slowly (see
/// `StagedArtifactLoader`, which this utility was extracted from, and the
/// E8.4/E9 device testing that found this exact failure mode). Wrapping
/// every attempt in an explicit timeout guarantees the retry loop actually
/// engages instead of hanging forever.
///
/// Throws the last error once [maxRetries] is exhausted.
Future<T> retryWithBackoff<T>({
  required Future<T> Function() attempt,
  int maxRetries = 3,
  List<Duration> backoffDurations = const [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ],
  Duration perAttemptTimeout = const Duration(seconds: 15),
}) async {
  assert(
    backoffDurations.length >= maxRetries,
    'backoffDurations must provide at least one entry per retry',
  );

  Object? lastError;
  for (var attemptIndex = 0; attemptIndex <= maxRetries; attemptIndex++) {
    try {
      return await attempt().timeout(perAttemptTimeout);
    } catch (e) {
      lastError = e;
      if (attemptIndex == maxRetries) break;
      await Future<void>.delayed(backoffDurations[attemptIndex]);
    }
  }
  throw lastError!;
}
