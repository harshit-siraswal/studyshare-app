import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/utils/admin_access.dart';

void main() {
  group('admin access helpers', () {
    test('empty capability list does not grant ban permission', () {
      final profile = <String, dynamic>{
        'role': appRoleCollegeUser,
        'college_id': 'college-1',
        'admin_capabilities': const <String>[],
      };

      expect(resolveEffectiveProfileRole(profile), appRoleCollegeUser);
      expect(canBanUsersProfile(profile), isFalse);
    });

    test('empty capability map does not grant ban permission', () {
      final profile = <String, dynamic>{
        'role': appRoleCollegeUser,
        'college_id': 'college-1',
        'admin_capabilities': const <String, dynamic>{},
      };

      expect(resolveEffectiveProfileRole(profile), appRoleCollegeUser);
      expect(canBanUsersProfile(profile), isFalse);
    });

    test('explicit capability list grants only listed capabilities', () {
      final profile = <String, dynamic>{
        'role': appRoleCollegeUser,
        'college_id': 'college-1',
        'admin_capabilities': const <String>['upload_resource'],
      };

      expect(hasAdminCapability(profile, 'upload_resource'), isTrue);
      expect(canBanUsersProfile(profile), isFalse);
    });

    test('admin without explicit capabilities receives admin defaults', () {
      final profile = <String, dynamic>{
        'role': appRoleAdmin,
        'college_id': 'college-1',
      };

      expect(resolveEffectiveProfileRole(profile), appRoleAdmin);
      expect(canBanUsersProfile(profile), isTrue);
    });
  });
}
