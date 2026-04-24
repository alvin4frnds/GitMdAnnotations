import 'dart:convert';

import '../entities/changelog_entry.dart';
import '../entities/job.dart';
import '../entities/job_ref.dart';
import '../entities/phase.dart';
import '../entities/repo_ref.dart';
import '../entities/source_kind.dart';
import '../entities/spec_file.dart';
import '../ports/file_system_port.dart';
import 'changelog_parser.dart';

/// Domain service that discovers jobs and spec files on disk via the
/// injected [FileSystemPort]. Pure domain logic (no Flutter, no dart:io);
/// composes the port, does not define one. See IMPLEMENTATION.md §4.3.
class SpecRepository {
  SpecRepository({required this.fs, required this.workdir});

  final FileSystemPort fs;

  /// Absolute POSIX path to the working tree of the `claude-jobs` checkout.
  /// Each job folder lives at `$workdir/jobs/pending/<jobId>/`.
  final String workdir;

  static final RegExp _jobIdPattern = RegExp(r'^spec-[a-z0-9-]+$');
  static final RegExp _revisionPattern = RegExp(r'^04-spec-v(\d+)\.md$');

  String _jobDir(String jobId) => '$workdir/jobs/pending/$jobId';

  /// Lists every folder under `jobs/pending/` as a resolved [Job]. Folders
  /// whose name doesn't match [JobRef]'s pattern, or that contain no
  /// recognised spec file, are silently skipped.
  Future<List<Job>> listOpenJobs(RepoRef repo) async {
    final List<FsEntry> entries;
    try {
      entries = await fs.listDir('$workdir/jobs/pending');
    } on FsNotFound {
      return const [];
    }
    final jobs = <Job>[];
    for (final entry in entries) {
      if (!entry.isDirectory) continue;
      if (!_jobIdPattern.hasMatch(entry.name)) continue;
      final children = await fs.listDir(entry.path);
      final names = {for (final c in children) c.name};
      final sourceKind = _detectSourceKind(names);
      if (sourceKind == null) continue;
      final phase = _resolvePhase(names);
      if (phase == null) continue;
      jobs.add(Job(
        ref: JobRef(repo: repo, jobId: entry.name),
        phase: phase,
        sourceKind: sourceKind,
      ));
    }
    return List.unmodifiable(jobs);
  }

  /// Loads the latest spec for a job. Preference: highest-numbered
  /// `04-spec-v<N>.md` (numeric sort) -> `02-spec.md` -> `spec.pdf`.
  /// PDF bytes are base64-encoded into [SpecFile.contents] since the
  /// entity types contents as `String`; the review pipeline decodes it.
  /// Throws [SpecNotFound] when nothing matches.
  Future<SpecFile> loadSpec(JobRef job) async {
    final dir = _jobDir(job.jobId);
    final names = await _listNames(dir);
    if (names == null) throw SpecNotFound(job);
    final rev = _latestRevision(names);
    if (rev != null) return _loadMarkdown('$dir/$rev');
    if (names.contains('02-spec.md')) return _loadMarkdown('$dir/02-spec.md');
    if (names.contains('spec.pdf')) return _loadPdf('$dir/spec.pdf');
    if (names.contains('spec.svg')) return _loadSvg('$dir/spec.svg');
    throw SpecNotFound(job);
  }

  /// Reads the `## Changelog` section of the latest markdown spec, or the
  /// sibling `CHANGELOG.md` for a PDF job. Empty when the section or file
  /// is missing.
  Future<List<ChangelogEntry>> readChangelog(JobRef job) async {
    final dir = _jobDir(job.jobId);
    final names = await _listNames(dir);
    if (names == null) return const [];
    final rev = _latestRevision(names);
    if (rev != null) return parseChangelog(await fs.readString('$dir/$rev'));
    if (names.contains('02-spec.md')) {
      return parseChangelog(await fs.readString('$dir/02-spec.md'));
    }
    if ((names.contains('spec.pdf') || names.contains('spec.svg')) &&
        names.contains('CHANGELOG.md')) {
      return parseChangelog(await fs.readString('$dir/CHANGELOG.md'));
    }
    return const [];
  }

  // -- helpers --------------------------------------------------------------

  Future<Set<String>?> _listNames(String dir) async {
    try {
      final children = await fs.listDir(dir);
      return {for (final c in children) c.name};
    } on FsNotFound {
      return null;
    }
  }

  SourceKind? _detectSourceKind(Set<String> names) {
    if (names.contains('spec.pdf')) return SourceKind.pdf;
    if (names.contains('spec.svg')) return SourceKind.svg;
    if (names.contains('02-spec.md') ||
        names.any(_revisionPattern.hasMatch)) {
      return SourceKind.markdown;
    }
    return null;
  }

  /// Thin wrapper around [Phase.resolve]. For PDF-only or SVG-only folders
  /// (no markdown signal), mirrors the same truth table with `spec.pdf` /
  /// `spec.svg` as Phase.spec.
  Phase? _resolvePhase(Set<String> names) {
    try {
      return Phase.resolve(names);
    } on ArgumentError {
      if (names.contains('05-approved')) return Phase.approved;
      if (names.any(_revisionPattern.hasMatch)) return Phase.revised;
      if (names.contains('03-review.md')) return Phase.review;
      if (names.contains('spec.pdf')) return Phase.spec;
      if (names.contains('spec.svg')) return Phase.spec;
      return null;
    }
  }

  String? _latestRevision(Set<String> names) {
    var bestN = -1;
    String? best;
    for (final n in names) {
      final m = _revisionPattern.firstMatch(n);
      if (m == null) continue;
      final v = int.parse(m.group(1)!);
      if (v > bestN) {
        bestN = v;
        best = n;
      }
    }
    return best;
  }

  Future<SpecFile> _loadMarkdown(String path) async {
    final contents = await fs.readString(path);
    return SpecFile(
      path: path,
      sha: _contentSha(utf8.encode(contents)),
      contents: contents,
      sourceKind: SourceKind.markdown,
    );
  }

  Future<SpecFile> _loadPdf(String path) async {
    final bytes = await fs.readBytes(path);
    return SpecFile(
      path: path,
      sha: _contentSha(bytes),
      contents: base64.encode(bytes),
      sourceKind: SourceKind.pdf,
    );
  }

  /// SVG is plain XML on disk but SpecFile.contents isn't consumed for
  /// SVG-kind specs (non-annotatable — the reader opens the file directly
  /// from [path]). Keep the loader symmetric with [_loadPdf] so callers get
  /// a content-hash seeded from the raw bytes.
  Future<SpecFile> _loadSvg(String path) async {
    final bytes = await fs.readBytes(path);
    return SpecFile(
      path: path,
      sha: _contentSha(bytes),
      contents: base64.encode(bytes),
      sourceKind: SourceKind.svg,
    );
  }

  /// Deterministic 40-hex content hash. Placeholder for git's blob SHA
  /// (T10 will supply the real value). Runs FNV-1a (32-bit) five times
  /// with different salts and concatenates each 8-char digest. Stays
  /// inside 32-bit unsigned arithmetic so it's correct on VM and web.
  static String _contentSha(List<int> bytes) {
    const salts = <int>[
      0x00000000, 0x9E3779B1, 0x85EBCA77, 0xC2B2AE3D, 0x27D4EB2F,
    ];
    final buf = StringBuffer();
    for (final salt in salts) {
      buf.write(_fnv1a32(bytes, salt).toRadixString(16).padLeft(8, '0'));
    }
    return buf.toString();
  }

  static int _fnv1a32(List<int> bytes, int salt) {
    const mask32 = 0xFFFFFFFF;
    const fnvPrime32 = 0x01000193;
    var h = (0x811C9DC5 ^ salt) & mask32;
    for (final b in bytes) {
      h = (h ^ (b & 0xff)) & mask32;
      h = (h * fnvPrime32) & mask32;
    }
    return h;
  }
}

/// Thrown by [SpecRepository.loadSpec] when no spec file can be found.
class SpecNotFound implements Exception {
  const SpecNotFound(this.job);
  final JobRef job;
  @override
  String toString() => 'SpecNotFound(${job.jobId})';
}
