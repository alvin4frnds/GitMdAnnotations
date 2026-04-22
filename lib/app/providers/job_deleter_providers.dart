import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/job_deleter.dart';
import 'review_providers.dart';
import 'spec_providers.dart';
import 'sync_providers.dart';

/// Composition of the delete-job domain service. Recomputed whenever any
/// bound port is replaced so test fakes propagate automatically.
final jobDeleterProvider = Provider<JobDeleter>(
  (ref) => JobDeleter(
    fs: ref.watch(fileSystemProvider),
    git: ref.watch(gitPortProvider),
    drafts: ref.watch(reviewDraftStoreProvider),
  ),
);
