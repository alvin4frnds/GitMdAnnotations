import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/controllers/repo_picker_controller.dart';
import '../../../app/providers/repo_picker_providers.dart';
import '../../../domain/entities/github_repo.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Screen between sign-in and JobList: lists the signed-in user's GitHub
/// repos and lets them pick one. On pick, [RepoPickerController.pick]
/// clones the repo locally and sets [currentRepoProvider] — the
/// `_AuthGate` in `main.dart` watches that provider and flips to
/// [JobListScreen] automatically.
class RepoPickerScreen extends ConsumerWidget {
  const RepoPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final async = ref.watch(repoPickerControllerProvider);
    return ColoredBox(
      color: t.surfaceBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopChrome(),
          Expanded(child: _Body(async: async)),
        ],
      ),
    );
  }
}

class _TopChrome extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.folder_copy_outlined, size: 18, color: t.textPrimary),
          const SizedBox(width: 10),
          Text(
            'Pick a repository',
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            'GitMdScribe syncs specs from a repo\'s claude-jobs branch.',
            style: TextStyle(color: t.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.async});
  final AsyncValue<RepoPickerState> async;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (async.isLoading && !async.hasValue) {
      return const _LoadingState();
    }
    if (async.hasError && !async.hasValue) {
      return _ErrorState(
        message: async.error.toString(),
        onRetry: () => ref.read(repoPickerControllerProvider.notifier).refresh(),
      );
    }
    final state = async.value;
    return switch (state) {
      null || RepoPickerLoading() => const _LoadingState(),
      RepoPickerAuthError(:final message) => _ErrorState(
          message: 'Sign-in required: $message',
          onRetry: () =>
              ref.read(repoPickerControllerProvider.notifier).refresh(),
        ),
      RepoPickerNetworkError(:final message) => _ErrorState(
          message: 'Network error: $message',
          onRetry: () =>
              ref.read(repoPickerControllerProvider.notifier).refresh(),
        ),
      RepoPickerLoaded(:final repos) =>
        repos.isEmpty ? const _EmptyState() : _RepoList(repos: repos),
      RepoPickerOpening(:final repo) =>
        _OpeningState(repo: repo),
      RepoPickerCloneFailed(
        :final repo,
        :final message,
        :final previousRepos,
      ) =>
        _CloneFailedState(
          repo: repo,
          message: message,
          previousRepos: previousRepos,
        ),
    };
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_off_outlined, size: 32, color: t.textMuted),
          const SizedBox(height: 10),
          Text(
            'No repositories visible to this token.',
            style: TextStyle(color: t.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'Make sure your PAT has the `repo` scope.',
            style: TextStyle(color: t.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CloneFailedState extends StatelessWidget {
  const _CloneFailedState({
    required this.repo,
    required this.message,
    required this.previousRepos,
  });
  final GitHubRepo repo;
  final String message;
  final List<GitHubRepo> previousRepos;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      children: [
        Container(
          color: t.statusDanger.withValues(alpha: 0.10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 18, color: t.statusDanger),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Couldn\'t open ${repo.fullName}',
                      style: appMono(
                        context,
                        size: 12,
                        weight: FontWeight.w600,
                        color: t.statusDanger,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.statusDanger,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: previousRepos.isEmpty
              ? const _EmptyState()
              : _RepoList(repos: previousRepos),
        ),
      ],
    );
  }
}

class _OpeningState extends StatelessWidget {
  const _OpeningState({required this.repo});
  final GitHubRepo repo;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Opening ${repo.fullName}…',
            style: appMono(context, size: 13, color: t.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Cloning the sidecar branch on first pick.',
            style: TextStyle(color: t.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 28, color: t.statusDanger),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.statusDanger, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepoList extends ConsumerWidget {
  const _RepoList({required this.repos});
  final List<GitHubRepo> repos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: repos.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: context.tokens.borderSubtle),
      itemBuilder: (_, i) => _RepoRow(
        repo: repos[i],
        onTap: () =>
            ref.read(repoPickerControllerProvider.notifier).pick(repos[i]),
      ),
    );
  }
}

class _RepoRow extends StatelessWidget {
  const _RepoRow({required this.repo, required this.onTap});
  final GitHubRepo repo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.surfaceBackground,
      child: InkWell(
        onTap: onTap,
        hoverColor: t.surfaceSunken,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                repo.isPrivate
                    ? Icons.lock_outline_rounded
                    : Icons.folder_outlined,
                size: 18,
                color: t.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      repo.fullName,
                      style: appMono(
                        context,
                        size: 13,
                        weight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'default: ${repo.defaultBranch}'
                      '${repo.isPrivate ? " · private" : ""}',
                      style: TextStyle(color: t.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
