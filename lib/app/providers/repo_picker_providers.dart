import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ports/github_repos_port.dart';
import '../controllers/repo_picker_controller.dart';

/// Binds the [GitHubReposPort] implementation at composition root. Tests
/// override this via `ProviderContainer(overrides: [...overrideWithValue(fake)])`.
final gitHubReposPortProvider = Provider<GitHubReposPort>((ref) {
  throw UnimplementedError(
    'gitHubReposPortProvider must be overridden at composition root',
  );
});

/// Top-level repo-picker state surfaced to the UI. See
/// [RepoPickerController].
final repoPickerControllerProvider =
    AsyncNotifierProvider<RepoPickerController, RepoPickerState>(
  RepoPickerController.new,
);
