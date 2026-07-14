import type { CommandHandler } from '../shared/handlers';
import { landlordApprove, landlordReinstate, landlordSuspend } from './admin';
import { applicationSubmit, applicationWithdraw, contactSubmit } from './applications';
import { invoiceGenerate, paymentInitiate, paymentRecordManual, receiptRegenerate } from './billing';
import { noticePublish } from './communication';
import { documentDelete, documentFinalizeUpload } from './documents';
import { landlordOnboard, profileUpdate } from './identity';
import { maintenanceAddComment, maintenanceCreate, maintenanceUpdateStatus } from './maintenance';
import { listingPublish, listingRenew, listingSaveDraft, listingUnpublish } from './listings';
import { propertyArchive, propertyCreate, propertyUpdate, unitArchive, unitCreate, unitRestore, unitUpdate } from './portfolio';
import { reportRequest } from './reports';
import { leaseActivate, leaseCreate, leaseEnd, tenantInvite, tenantUpdate } from './tenancy';

// Payload types are enforced by each handler's strict runtime schema before
// the untyped registry boundary is crossed.
export const commandHandlers = new Map<string, CommandHandler<any>>([
  ['profile.update', profileUpdate],
  ['landlord.onboard', landlordOnboard],
  ['landlord.approve', landlordApprove],
  ['landlord.suspend', landlordSuspend],
  ['landlord.reinstate', landlordReinstate],
  ['property.create', propertyCreate],
  ['property.update', propertyUpdate],
  ['property.archive', propertyArchive],
  ['unit.create', unitCreate],
  ['unit.update', unitUpdate],
  ['unit.archive', unitArchive],
  ['unit.restore', unitRestore],
  ['tenant.invite', tenantInvite],
  ['tenant.update', tenantUpdate],
  ['lease.create', leaseCreate],
  ['lease.activate', leaseActivate],
  ['lease.end', leaseEnd],
  ['invoice.generate', invoiceGenerate],
  ['payment.recordManual', paymentRecordManual],
  ['payment.initiate', paymentInitiate],
  ['receipt.regenerate', receiptRegenerate],
  ['maintenance.create', maintenanceCreate],
  ['maintenance.updateStatus', maintenanceUpdateStatus],
  ['maintenance.addComment', maintenanceAddComment],
  ['notice.publish', noticePublish],
  ['listing.saveDraft', listingSaveDraft],
  ['listing.publish', listingPublish],
  ['listing.unpublish', listingUnpublish],
  ['listing.renew', listingRenew],
  ['application.submit', applicationSubmit],
  ['application.withdraw', applicationWithdraw],
  ['contact.submit', contactSubmit],
  ['document.finalizeUpload', documentFinalizeUpload],
  ['document.delete', documentDelete],
  ['report.request', reportRequest],
]);
