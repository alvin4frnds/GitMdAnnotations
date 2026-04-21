import 'dart:convert';

import '../../domain/entities/job_ref.dart';
import '../../domain/ports/file_system_port.dart';

/// Decoded draft body persisted between sessions. Answers survive a hot
/// restart so the Review panel can rehydrate on the next open.
class DraftPayload {
  const DraftPayload({required this.answers, required this.freeFormNotes});
  final Map<String, String> answers;
  final String freeFormNotes;
}

/// Pure persistence helper for review drafts. Owns the on-disk shape of
/// `03-review.md.draft`, the path under `appDocsPath`, and tolerant
/// recovery from corrupt / missing drafts.
///
/// Split out from [ReviewController] so the controller can stay at the
/// UI-facing state-machine scale (§2.6) while the draft I/O can be unit-
/// tested independently.
class ReviewDraftStore {
  ReviewDraftStore(this._fs);

  final FileSystemPort _fs;

  Future<void> save(JobRef job, {
    required Map<String, String> answers,
    required String freeFormNotes,
  }) async {
    final path = await _draftPath(job);
    final payload = jsonEncode({
      'answers': answers,
      'freeFormNotes': freeFormNotes,
    });
    await _fs.writeString(path, payload);
  }

  Future<DraftPayload?> load(JobRef job) async {
    try {
      final path = await _draftPath(job);
      final raw = await _fs.readString(path);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final answers = decoded['answers'];
      final notes = decoded['freeFormNotes'];
      return DraftPayload(
        answers: answers is Map
            ? answers.map((k, v) => MapEntry(k.toString(), v.toString()))
            : const <String, String>{},
        freeFormNotes: notes is String ? notes : '',
      );
    } on FsNotFound {
      return null;
    } catch (_) {
      // Corrupt draft — treat as absent. The periodic auto-save will
      // overwrite on the next mutation.
      return null;
    }
  }

  Future<void> delete(JobRef job) async {
    final path = await _draftPath(job);
    await _fs.remove(path);
  }

  Future<String> _draftPath(JobRef job) =>
      _fs.appDocsPath('drafts/${job.jobId}/03-review.md.draft');
}
