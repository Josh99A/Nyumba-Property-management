import '../../../core/localization/generated/app_localizations.dart';
import '../domain/user_session.dart';

String localizedAppRole(AppLocalizations copy, AppRole role) => switch (role) {
  AppRole.superAdmin => copy.appRoleSuperAdmin,
  AppRole.admin => copy.appRoleAdmin,
  AppRole.landlord => copy.appRoleLandlord,
  AppRole.staff => copy.appRoleStaff,
  AppRole.tenant => copy.appRoleTenant,
  AppRole.client => copy.appRoleClient,
};
