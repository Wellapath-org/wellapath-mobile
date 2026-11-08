import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/community/domain/community_me.dart';
import 'package:wellapath_mobile/features/community/domain/community_permissions.dart';
import 'package:wellapath_mobile/features/community/domain/moderation.dart';

typedef _C = CommunityCapability;

/// COMMUNITY_API_CONTRACT.md v1.0-draft §2.1, transcribed independently of
/// the implementation. Export is "any role" (M7); deletion is member-only
/// until demoted (M8, 422 `privileged_account`).
const Map<_C, List<bool>> _expected = {
  //                                    member moderator admin
  _C.readContent: [true, true, true],
  _C.readOwnNotifications: [true, true, true],
  _C.createContent: [true, true, true],
  _C.deleteOwnContent: [true, true, true],
  _C.reportContent: [true, true, true],
  _C.setProfile: [true, true, true],
  _C.claimProfession: [true, true, true],
  _C.exportOwnData: [true, true, true],
  _C.deleteOwnAccount: [true, false, false],
  _C.viewReportQueue: [false, true, true],
  _C.revealIdentity: [false, true, true],
  _C.moderateContent: [false, true, true],
  // §15 row 49: moderators may restrict, suspend and reinstate members.
  _C.restrictSuspendReinstateMember: [false, true, true],
  _C.restrictSuspendReinstatePrivileged: [false, false, true],
  _C.viewAuditLog: [false, true, true],
  _C.verifyProfessional: [false, false, true],
  _C.changeRole: [false, false, true],
  _C.resetTotp: [false, false, true],
};

/// §2.2: what a restricted (read-only) account keeps.
const Set<_C> _restrictedKeeps = {
  _C.readContent,
  _C.readOwnNotifications,
  _C.reportContent, // §15 row 37: reporting is a safety action
  _C.deleteOwnContent, // §8.2 C5
  _C.exportOwnData,
  _C.deleteOwnAccount,
};

void main() {
  test('the matrix covers every capability', () {
    expect(_expected.keys.toSet(), CommunityCapability.values.toSet());
  });

  test('matrix matches the contract cell by cell', () {
    for (final MapEntry<_C, List<bool>> row in _expected.entries) {
      for (int i = 0; i < CommunityRole.values.length; i++) {
        final CommunityRole role = CommunityRole.values[i];
        expect(
          CommunityPermissions.can(role, row.key),
          row.value[i],
          reason: '${role.name} / ${row.key.name}',
        );
      }
    }
  });

  test('moderators may suspend members; only admins act on privileged', () {
    expect(
      CommunityPermissions.can(
        CommunityRole.moderator,
        ModerationActionType.suspendAccount.requires!,
      ),
      isTrue,
    );
    expect(
      CommunityPermissions.can(
        CommunityRole.moderator,
        _C.restrictSuspendReinstatePrivileged,
      ),
      isFalse,
    );
  });

  test('only admins verify professionals', () {
    expect(
      CommunityRole.values.where(
        (CommunityRole r) => CommunityPermissions.can(r, _C.verifyProfessional),
      ),
      [CommunityRole.admin],
    );
  });

  test('restricted may still report, delete own, export, delete account', () {
    for (final _C c in CommunityCapability.values) {
      expect(
        CommunityPermissions.can(
          CommunityRole.member,
          c,
          status: AccountStatus.restricted,
        ),
        _restrictedKeeps.contains(c) && _expected[c]![0],
        reason: c.name,
      );
    }
  });

  test('suspended has nothing', () {
    for (final CommunityRole role in CommunityRole.values) {
      for (final _C c in CommunityCapability.values) {
        expect(
          CommunityPermissions.can(role, c, status: AccountStatus.suspended),
          isFalse,
        );
      }
    }
  });

  test('unknown wire role/status fail to least privilege (§13)', () {
    expect(
      CommunityPermissions.roleFromWire('superuser'),
      CommunityRole.member,
    );
    expect(CommunityPermissions.roleFromWire(null), CommunityRole.member);
    expect(
      CommunityPermissions.statusFromWire('weird'),
      AccountStatus.suspended,
    );
    final CommunityMe me = CommunityMe.fromJson(<String, dynamic>{
      'account_id': 'Xk3abc',
      'email': 'a@b.ng',
      'role': 'root',
      'status': 'paused',
      'restricted_until': null,
      'two_factor_enabled': false,
      'community_allowed': true,
      'created_at': '2026-11-07T10:15:00.000Z',
      'profile': null,
    });
    expect(me.role, CommunityRole.member);
    expect(
      me.can(_C.readContent),
      isFalse,
      reason: 'unknown status = suspended',
    );
  });

  test('every moderation action needs a non-member capability', () {
    for (final ModerationActionType a in ModerationActionType.values) {
      final _C? needs = a.requires;
      if (needs == null) {
        // User-originated: withdraw own claim, delete own account.
        expect(
          a,
          anyOf(
            ModerationActionType.withdrawProfessional,
            ModerationActionType.deleteAccount,
          ),
        );
        continue;
      }
      expect(
        CommunityPermissions.can(CommunityRole.member, needs),
        isFalse,
        reason: a.name,
      );
    }
  });
}
