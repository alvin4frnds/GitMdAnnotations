import 'package:url_launcher/url_launcher.dart';

import 'github_oauth_adapter.dart';

/// Production [BrowserLauncher] that opens the verification URI in a
/// Chrome Custom Tab via `url_launcher`. Errors are swallowed on purpose:
/// the Device Flow poll loop still works if the user opens the URL
/// manually from the on-screen `user_code`. Callers that need visibility
/// into launch failures should add logging at the `AuthPort` boundary.
class DefaultBrowserLauncher implements BrowserLauncher {
  const DefaultBrowserLauncher();

  @override
  Future<void> openVerificationUri(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // TODO: logger — record the failure; don't break the flow.
    }
  }
}
