/// Sealed root of typed §3.7 invariant violations.
sealed class CommitPlannerError implements Exception {
  const CommitPlannerError();
}

class CommitPlannerAnchorKindMismatch extends CommitPlannerError {
  const CommitPlannerAnchorKindMismatch({required this.groupId});
  final String groupId;
}

class CommitPlannerAnchorShaMismatch extends CommitPlannerError {
  const CommitPlannerAnchorShaMismatch({
    required this.groupId,
    required this.anchorSha,
    required this.specSha,
  });
  final String groupId;
  final String anchorSha;
  final String specSha;
}

class CommitPlannerPdfPageSetMismatch extends CommitPlannerError {
  const CommitPlannerPdfPageSetMismatch(
      {required this.svgPages, required this.pngPages});
  final Set<int> svgPages;
  final Set<int> pngPages;
}

class CommitPlannerMissingPair extends CommitPlannerError {
  const CommitPlannerMissingPair(this.reason);
  final String reason;
}
