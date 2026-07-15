import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { actorFromAuth } from '../shared/actor';
import { ENFORCE_APP_CHECK, REGION } from '../shared/config';
import { DomainError } from '../shared/errors';
import { executeCommandCore } from '../shared/router';

export const executeCommand = onCall(
  { region: REGION, enforceAppCheck: ENFORCE_APP_CHECK },
  async (request) => {
    try {
      const actor = actorFromAuth(request.auth);
      return await executeCommandCore(getFirestore(), actor, request.data);
    } catch (error) {
      if (error instanceof DomainError) throw error.toHttpsError();
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', 'request.internalRetryable');
    }
  },
);
