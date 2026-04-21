import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/repo_browser_controller.dart';
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
