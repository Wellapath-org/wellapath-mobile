import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/community/domain/community_permissions.dart';
import 'package:wellapath_mobile/features/community/domain/moderation.dart';

typedef _C = CommunityCapability;

/// API_CONTRACT.md §11.1, transcribed independently of the implementation.
const Map<_C, List<bool>> _expected = {
  //                          member moderator admin
  _C.readContent: [true, true, true],
  _C.createContent: [true, true, true],
  _C.deleteOwnContent: [true, true, true],
  _C.reportContent: [true, true, true],
  _C.claimProfession: [true, true, true],
  _C.viewReportsQueue: [false, true, true],
  _C.revealIdentity: [false, true, true],
  _C.hideContent: [false, true, true],
  _C.removeContent: [false, true, true],
  _C.restrictAccount: [false, true, true],
  _C.viewAuditLog: [false, true, true],
  _C.suspendAccount: [false, false, true],
  _C.verifyProfessional: [false, false, true],
  _C.changeRole: [false, false, true],
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

  test('roles are strictly nested: member ⊂ moderator ⊂ admin', () {
    final Set<_C> m = CommunityPermissions.matrix[CommunityRole.member]!;
    final Set<_C> mod = CommunityPermissions.matrix[CommunityRole.moderator]!;
    final Set<_C> a = CommunityPermissions.matrix[CommunityRole.admin]!;
    expect(mod.containsAll(m) && mod.length > m.length, isTrue);
    expect(a.containsAll(mod) && a.length > mod.length, isTrue);
  });

  test('only admins verify professionals', () {
    expect(
      CommunityRole.values.where(
        (CommunityRole r) => CommunityPermissions.can(r, _C.verifyProfessional),
      ),
      [CommunityRole.admin],
    );
  });

  test('restricted keeps read only; suspended has nothing', () {
    for (final CommunityRole role in CommunityRole.values) {
      for (final _C c in CommunityCapability.values) {
        expect(
          CommunityPermissions.can(role, c, status: AccountStatus.restricted),
          c == _C.readContent,
        );
        expect(
          CommunityPermissions.can(role, c, status: AccountStatus.suspended),
          isFalse,
        );
      }
    }
  });

  test('unknown wire role/status fail to least privilege', () {
    expect(
      CommunityPermissions.roleFromWire('superuser'),
      CommunityRole.member,
    );
    expect(CommunityPermissions.roleFromWire(null), CommunityRole.member);
    expect(
      CommunityPermissions.statusFromWire('weird'),
      AccountStatus.suspended,
    );
    final CommunityViewer v = CommunityViewer.fromJson(<String, dynamic>{
      'account_id': 'acc_1',
      'role': 'root',
      'status': 'active',
    });
    expect(v.can(_C.hideContent), isFalse);
  });

  test('every moderation action maps to a non-member capability', () {
    for (final ModerationActionType a in ModerationActionType.values) {
      expect(
        CommunityPermissions.can(CommunityRole.member, a.requires),
        isFalse,
        reason: a.name,
      );
    }
    expect(ModerationActionType.suspendAccount.requires, _C.suspendAccount);
    expect(
      CommunityPermissions.can(
        CommunityRole.moderator,
        ModerationActionType.suspendAccount.requires,
      ),
      isFalse,
    );
  });
}
