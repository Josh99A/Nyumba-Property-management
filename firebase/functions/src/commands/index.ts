import type { CommandHandler } from '../shared/handlers';
import { landlordApprove, landlordReinstate, landlordSuspend, userArchive, userChangeRole, userDelete, userRestore } from './admin';
import { applicationSubmit, applicationWithdraw, contactSubmit } from './applications';
import {
  invoiceGenerate,
  paymentConfirmDeclared,
  paymentDeclare,
  paymentInitiate,
  paymentRecordAgainstTenancy,
  paymentRecordManual,
  paymentRejectDeclared,
  receiptRegenerate,
} from './billing';
import { noticePublish, platformBroadcast } from './communication';
import { documentDelete, documentFinalizeUpload } from './documents';
import {
  landlordOnboard,
  profileRegisterDevice,
  profileUnregisterDevice,
  profileUpdate,
} from './identity';
import { maintenanceAddComment, maintenanceCreate, maintenanceUpdateStatus } from './maintenance';
import { listingPublish, listingRenew, listingSaveDraft, listingUnpublish } from './listings';
import { propertyArchive, propertyCreate, propertyUpdate, unitArchive, unitCreate, unitRestore, unitUpdate } from './portfolio';
import { documentPurge, listingDelete, propertyDelete, unitDelete } from './purge';
import { notificationMarkRead } from './notifications';
import { reportRequest } from './reports';
import { staffClaimInvite, staffInvite, staffRevoke, staffUpdatePermissions } from './staff';
import {
  planUpdate,
  subscriptionConfirmPayment,
  subscriptionDeactivate,
  subscriptionDowngrade,
  subscriptionRejectPayment,
  subscriptionRequestUpgrade,
  subscriptionSelectPlan,
} from './subscription';
import { leaseActivate, leaseCreate, leaseEnd, tenancyEstablish, tenantClaimInvite, tenantInvite, tenantUpdate } from './tenancy';

// Payload types are enforced by each handler's strict runtime schema before
// the untyped registry boundary is crossed.
export const commandHandlers = new Map<string, CommandHandler<any>>([
  ['profile.update', profileUpdate],
  ['profile.registerDevice', profileRegisterDevice],
  ['profile.unregisterDevice', profileUnregisterDevice],
  ['notification.markRead', notificationMarkRead],
  ['landlord.onboard', landlordOnboard],
  ['landlord.approve', landlordApprove],
  ['landlord.suspend', landlordSuspend],
  ['landlord.reinstate', landlordReinstate],
  ['user.archive', userArchive],
  ['user.restore', userRestore],
  ['user.delete', userDelete],
  ['user.changeRole', userChangeRole],
  ['subscription.selectPlan', subscriptionSelectPlan],
  ['subscription.requestUpgrade', subscriptionRequestUpgrade],
  ['subscription.confirmPayment', subscriptionConfirmPayment],
  ['subscription.rejectPayment', subscriptionRejectPayment],
  ['subscription.downgrade', subscriptionDowngrade],
  ['subscription.deactivate', subscriptionDeactivate],
  ['plan.update', planUpdate],
  ['platform.broadcast', platformBroadcast],
  ['staff.invite', staffInvite],
  ['staff.claimInvite', staffClaimInvite],
  ['staff.revoke', staffRevoke],
  ['staff.updatePermissions', staffUpdatePermissions],
  ['property.create', propertyCreate],
  ['property.update', propertyUpdate],
  ['property.archive', propertyArchive],
  ['property.delete', propertyDelete],
  ['unit.create', unitCreate],
  ['unit.update', unitUpdate],
  ['unit.archive', unitArchive],
  ['unit.restore', unitRestore],
  ['unit.delete', unitDelete],
  ['tenant.invite', tenantInvite],
  ['tenant.update', tenantUpdate],
  ['tenant.claimInvite', tenantClaimInvite],
  ['lease.create', leaseCreate],
  ['lease.activate', leaseActivate],
  ['lease.end', leaseEnd],
  // Composite of tenant.invite + lease.create + lease.activate, so the client's
  // single Tenancy aggregate maps to one command and one idempotency key.
  ['tenancy.establish', tenancyEstablish],
  ['invoice.generate', invoiceGenerate],
  ['payment.recordManual', paymentRecordManual],
  ['payment.recordAgainstTenancy', paymentRecordAgainstTenancy],
  ['payment.initiate', paymentInitiate],
  ['payment.declare', paymentDeclare],
  ['payment.confirmDeclared', paymentConfirmDeclared],
  ['payment.rejectDeclared', paymentRejectDeclared],
  ['receipt.regenerate', receiptRegenerate],
  ['maintenance.create', maintenanceCreate],
  ['maintenance.updateStatus', maintenanceUpdateStatus],
  ['maintenance.addComment', maintenanceAddComment],
  ['notice.publish', noticePublish],
  ['listing.saveDraft', listingSaveDraft],
  ['listing.publish', listingPublish],
  ['listing.unpublish', listingUnpublish],
  ['listing.renew', listingRenew],
  ['listing.delete', listingDelete],
  ['application.submit', applicationSubmit],
  ['application.withdraw', applicationWithdraw],
  ['contact.submit', contactSubmit],
  ['document.finalizeUpload', documentFinalizeUpload],
  ['document.delete', documentDelete],
  ['document.purge', documentPurge],
  ['report.request', reportRequest],
]);
