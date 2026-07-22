import '../../../core/localization/generated/app_localizations.dart';
import '../domain/staff_permission.dart';

String localizedStaffPermissionLabel(
  AppLocalizations copy,
  StaffPermission permission,
) => switch (permission) {
  StaffPermission.manageProperties => copy.staffPermissionManagePropertiesLabel,
  StaffPermission.manageTenants => copy.staffPermissionManageTenantsLabel,
  StaffPermission.manageBilling => copy.staffPermissionManageBillingLabel,
  StaffPermission.manageMaintenance =>
    copy.staffPermissionManageMaintenanceLabel,
  StaffPermission.manageListings => copy.staffPermissionManageListingsLabel,
  StaffPermission.manageCommunication =>
    copy.staffPermissionManageCommunicationLabel,
  StaffPermission.manageDocuments => copy.staffPermissionManageDocumentsLabel,
  StaffPermission.viewReports => copy.staffPermissionViewReportsLabel,
};

String localizedStaffPermissionDescription(
  AppLocalizations copy,
  StaffPermission permission,
) => switch (permission) {
  StaffPermission.manageProperties =>
    copy.staffPermissionManagePropertiesDescription,
  StaffPermission.manageTenants => copy.staffPermissionManageTenantsDescription,
  StaffPermission.manageBilling => copy.staffPermissionManageBillingDescription,
  StaffPermission.manageMaintenance =>
    copy.staffPermissionManageMaintenanceDescription,
  StaffPermission.manageListings =>
    copy.staffPermissionManageListingsDescription,
  StaffPermission.manageCommunication =>
    copy.staffPermissionManageCommunicationDescription,
  StaffPermission.manageDocuments =>
    copy.staffPermissionManageDocumentsDescription,
  StaffPermission.viewReports => copy.staffPermissionViewReportsDescription,
};
