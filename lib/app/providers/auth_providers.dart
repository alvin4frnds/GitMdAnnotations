import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ports/auth_port.dart';
import '../../domain/ports/secure_storage_port.dart';
import '../controllers/auth_controller.dart';

/// Binds the [AuthPort] implementation at composition root. Tests override
/// this via `ProviderContainer(overrides: [authPortProvider.overrideWithValue(fake)])`.
final authPortProvider = Provider<AuthPort>((ref) {
  throw UnimplementedError(
    'authPortProvider must be overridden at composition root',
  );
});

/// Binds the [SecureStoragePort] implementation at composition root. Tests
/// override with [FakeSecureStorage].
final secureStorageProvider = Provider<SecureStoragePort>((ref) {
  throw UnimplementedError(
    'secureStorageProvider must be overridden at composition root',
  );
});

/// Top-level auth state surfaced to the UI.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);
