import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/batch_spec_importer.dart';
import '../controllers/repo_browser_controller.dart';
import '../controllers/repo_selection_controller.dart';
import '../controllers/spec_importer.dart';

/// UI-facing controller for the import-spec flow. See [SpecImportController].
final specImportControllerProvider = NotifierProvider.autoDispose<
    SpecImportController, AsyncValue<SpecImportOutcome?>>(
  SpecImportController.new,
);

/// Directory-browser state scoped to the current workdir.
final repoBrowserControllerProvider = AsyncNotifierProvider.autoDispose<
    RepoBrowserController, RepoBrowserState>(
  RepoBrowserController.new,
);

/// Set of repo-relative paths ticked for a batch convert. See
/// [RepoSelectionController]. `autoDispose` so it dies with the browser
/// route; not cleared on directory navigation (spec-005 OQ-1).
final repoSelectionControllerProvider =
    NotifierProvider.autoDispose<RepoSelectionController, Set<String>>(
  RepoSelectionController.new,
);

/// Batch "Convert N selected" state machine. See [BatchConvertController].
final batchConvertControllerProvider = NotifierProvider.autoDispose<
    BatchConvertController, BatchConvertState>(
  BatchConvertController.new,
);
