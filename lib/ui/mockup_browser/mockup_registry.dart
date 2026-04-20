import 'package:flutter/widgets.dart';

import '../../domain/entities/job_ref.dart';
import '../../domain/entities/repo_ref.dart';
import '../screens/annotation_canvas/annotation_canvas_screen.dart';
import '../screens/approval_confirmation/approval_confirmation_screen.dart';
import '../screens/changelog_viewer/changelog_viewer_screen.dart';
import '../screens/conflict_archived/conflict_archived_screen.dart';
import '../screens/job_list/job_list_screen.dart';
import '../screens/new_spec_author/new_spec_author_screen.dart';
import '../screens/review_panel/review_panel_screen.dart';
import '../screens/sign_in/sign_in_screen.dart';
import '../screens/spec_reader_md/spec_reader_md_screen.dart';
import '../screens/spec_reader_pdf/spec_reader_pdf_screen.dart';
import '../screens/submit_confirmation/submit_confirmation_screen.dart';
import '../screens/sync_status_bar/sync_down_screen.dart';
import '../screens/sync_status_bar/sync_up_screen.dart';

class MockupEntry {
  final String label;
  final WidgetBuilder builder;
  const MockupEntry(this.label, this.builder);
}

/// Ordered list of the 12 PRD mockup screens for visual QA.
const List<MockupEntry> mockupRegistry = [
  MockupEntry('1. Sign in', _signIn),
  MockupEntry('2. Sync Down', _syncDown),
  MockupEntry('3. Job list', _jobList),
  MockupEntry('4. Spec reader (markdown)', _specReaderMd),
  MockupEntry('4b. Spec reader (PDF)', _specReaderPdf),
  MockupEntry('5. Annotation canvas', _annotationCanvas),
  MockupEntry('6. Review panel', _reviewPanel),
  MockupEntry('7. Submit confirmation', _submitConfirmation),
  MockupEntry('8. Sync Up', _syncUp),
  MockupEntry('9. Changelog viewer', _changelogViewer),
  MockupEntry('10. Approval confirmation', _approvalConfirmation),
  MockupEntry('11. Conflict archived', _conflictArchived),
  MockupEntry('12. New spec (Phase 2)', _newSpecAuthor),
];

Widget _signIn(BuildContext c) => const SignInScreen();
Widget _syncDown(BuildContext c) => const SyncDownScreen();
Widget _jobList(BuildContext c) => const JobListScreen();
Widget _specReaderMd(BuildContext c) => const SpecReaderMdScreen();

// Mockup JobRef — mirrors bootstrap.dart's `_mockupRepo` and the fake
// filesystem's pre-baked `spec-auth-flow-totp` job folder so the mockup
// canvas shows the same breadcrumb the hardcoded chrome always had.
final _mockupAnnotationJob = JobRef(
  repo: const RepoRef(owner: 'demo', name: 'payments-api'),
  jobId: 'spec-auth-flow-totp',
);

/// PDF-side counterpart to `_mockupAnnotationJob`. Points at the
/// `spec-invoice-pdf-redesign` folder seeded in `_seedMockupFs`
/// (bootstrap.dart) alongside its `spec.pdf`.
final _mockupPdfJob = JobRef(
  repo: const RepoRef(owner: 'demo', name: 'payments-api'),
  jobId: 'spec-invoice-pdf-redesign',
);

const _mockupPdfPath =
    '/mock/jobs/pending/spec-invoice-pdf-redesign/spec.pdf';

Widget _specReaderPdf(BuildContext c) => SpecReaderPdfScreen(
      filePath: _mockupPdfPath,
      jobRef: _mockupPdfJob,
    );

Widget _annotationCanvas(BuildContext c) =>
    AnnotationCanvasScreen(jobRef: _mockupAnnotationJob);
Widget _reviewPanel(BuildContext c) => const ReviewPanelScreen();
Widget _submitConfirmation(BuildContext c) => const SubmitConfirmationScreen();
Widget _syncUp(BuildContext c) => const SyncUpScreen();
Widget _changelogViewer(BuildContext c) => const ChangelogViewerScreen();
Widget _approvalConfirmation(BuildContext c) => const ApprovalConfirmationScreen();
Widget _conflictArchived(BuildContext c) => const ConflictArchivedScreen();
Widget _newSpecAuthor(BuildContext c) => const NewSpecAuthorScreen();
