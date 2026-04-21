import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/entities/repo_ref.dart';

/// Dev-loop escape hatch for the missing RepoPicker (see
/// `docs/PROGRESS.md` §93 — deferred). When the app is built with
/// `--dart-define=DEV_SEED_ENABLED=true` the composition root stubs
/// [currentWorkdirProvider] + [currentRepoProvider] with a local seeded
/// workdir so the JobList screen has something to show on desktop /
/// emulator testing. Tablet release builds leave the flag unset and the
/// seed is a no-op.
const bool _kDevSeedEnabled = bool.fromEnvironment('DEV_SEED_ENABLED');
const String _kDevSeedOwner =
    String.fromEnvironment('DEV_SEED_REPO_OWNER', defaultValue: 'dev-local');
const String _kDevSeedRepo =
    String.fromEnvironment('DEV_SEED_REPO_NAME', defaultValue: 'dev-seed');

/// Resolved dev-seed state: where the seeded workdir lives on disk plus
/// the synthetic [RepoRef] the UI should present as "currently selected".
class DevSeed {
  const DevSeed({required this.workdir, required this.repo});
  final String workdir;
  final RepoRef repo;
}

/// Materializes the dev-seed workdir on disk and returns a [DevSeed]
/// when `DEV_SEED_ENABLED=true`, else `null`. Idempotent — re-running on
/// an already-seeded workdir leaves the existing files alone.
Future<DevSeed?> prepareDevSeed() async {
  if (!_kDevSeedEnabled) return null;
  final docs = await getApplicationDocumentsDirectory();
  final workdir = '${docs.path}/dev-seed-workdir';
  await _seedJob(workdir, 'spec-demo', _demoSpecMarkdown);
  return DevSeed(
    workdir: workdir,
    repo: const RepoRef(owner: _kDevSeedOwner, name: _kDevSeedRepo),
  );
}

Future<void> _seedJob(String workdir, String jobId, String spec) async {
  final jobDir = Directory('$workdir/jobs/pending/$jobId');
  await jobDir.create(recursive: true);
  final specFile = File('${jobDir.path}/02-spec.md');
  if (!await specFile.exists()) {
    await specFile.writeAsString(spec);
  }
}

const String _demoSpecMarkdown = '''# Dev-seed demo spec

This spec was materialized by `DEV_SEED_ENABLED=true`. It exists only so
the Emulator / desktop dev loop has a job to open before the real
RepoPicker ships. Tablet release builds never see this file.

## Overview

Scribble on the canvas with the mouse to verify
`ALLOW_MOUSE_ANNOTATION=true` lets non-stylus pointers through.

## Changelog

- 2026-04-21 — seeded
''';
