/// What the Community screens need from sign-in, independent of transport.
library;

import 'package:flutter/foundation.dart';

import '../domain/community_error.dart';
import '../domain/community_session.dart';
import '../domain/community_validation.dart';
import 'community_auth_api.dart';
import 'community_session_manager.dart';

abstract interface class CommunityAuthService implements Listenable {
  /// Signed in now, or a stored refresh token may resume a session.
  Future<bool> hasSession();

  /// A1. Always succeeds unless rate limited or offline (no enumeration).
  Future<void> requestOtp(String email);

  /// A2. Returns true when this sign-in created the account (sign-up).
  Future<bool> verifyOtp({required String email, required String code});

  /// A4 for this device; clears local tokens whatever the server says.
  Future<void> signOut();

  /// After account deletion: erase every Community secret on the device.
  Future<void> forgetDevice();

  /// A5: signed-in devices (account recovery aid).
  Future<List<DeviceSession>> devices();

  /// A6: sign out every other device (account recovery after a lost device).
  Future<int> signOutOtherDevices();
}

/// The production implementation over the session manager.
class SessionCommunityAuthService implements CommunityAuthService {
  SessionCommunityAuthService(this._session, this._devices);

  final CommunitySessionManager _session;
  final CommunityDeviceSessionsApi _devices;

  @override
  void addListener(VoidCallback listener) => _session.addListener(listener);

  @override
  void removeListener(VoidCallback listener) {
    _session.removeListener(listener);
  }

  @override
  Future<bool> hasSession() async {
    return _session.state == CommunitySignInState.signedIn ||
        await _session.hasStoredSession();
  }

  @override
  Future<void> requestOtp(String email) => _session.requestOtp(email);

  @override
  Future<bool> verifyOtp({required String email, required String code}) async {
    final TokenPair pair = await _session.verifyOtp(email: email, code: code);
    return pair.accountCreated;
  }

  @override
  Future<void> signOut() => _session.signOut();

  @override
  Future<void> forgetDevice() => _session.forgetDevice();

  @override
  Future<List<DeviceSession>> devices() => _devices.list();

  @override
  Future<int> signOutOtherDevices() => _devices.revokeOthers();
}

/// A local stand-in for tests and the in-memory dev backend. Accepts any
/// well-formed email with the code [acceptedCode]; nothing leaves the device.
class InMemoryCommunityAuthService extends ChangeNotifier
    implements CommunityAuthService {
  InMemoryCommunityAuthService({
    this.signedIn = false,
    this.acceptedCode = '123456',
  });

  bool signedIn;
  final String acceptedCode;
  final List<String> requestedFor = <String>[];
  bool forgotten = false;

  @override
  Future<bool> hasSession() async => signedIn;

  @override
  Future<void> requestOtp(String email) async {
    requestedFor.add(normaliseEmail(email));
  }

  @override
  Future<bool> verifyOtp({required String email, required String code}) async {
    normaliseEmail(email);
    if (validateOtpCode(code) != acceptedCode) {
      throw const CommunityException(CommunityErrorCode.invalidCode);
    }
    signedIn = true;
    notifyListeners();
    return false;
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
    notifyListeners();
  }

  @override
  Future<void> forgetDevice() async {
    forgotten = true;
    await signOut();
  }

  @override
  Future<List<DeviceSession>> devices() async => const <DeviceSession>[];

  @override
  Future<int> signOutOtherDevices() async => 0;
}

/// The default-build stand-in: Community is not configured, so there is no
/// session and every action refuses. Never reachable while the gate is
/// closed; it exists so the default build constructs nothing real.
class DisabledCommunityAuthService extends ChangeNotifier
    implements CommunityAuthService {
  @override
  Future<bool> hasSession() async => false;

  Never _off() => throw StateError('Community is not configured');

  @override
  Future<void> requestOtp(String email) async => _off();

  @override
  Future<bool> verifyOtp({required String email, required String code}) async =>
      _off();

  @override
  Future<void> signOut() async {}

  @override
  Future<void> forgetDevice() async {}

  @override
  Future<List<DeviceSession>> devices() async => _off();

  @override
  Future<int> signOutOtherDevices() async => _off();
}
