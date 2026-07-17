import { describe, expect, it } from 'vitest';

import {
  notificationTemplate,
  supportedLocale,
  SUPPORTED_LOCALES,
} from '../../src/shared/localization';

describe('localized notification templates', () => {
  it('keeps the supported profile locale contract explicit', () => {
    expect(SUPPORTED_LOCALES).toEqual(['en', 'lg', 'sw', 'ar']);
    expect(supportedLocale('sw')).toBe('sw');
    expect(supportedLocale('fr')).toBe('en');
    expect(supportedLocale(null)).toBe('en');
  });

  it('renders each template in every supported locale', () => {
    for (const locale of SUPPORTED_LOCALES) {
      for (const key of ['new_application', 'new_enquiry', 'tenant_notice'] as const) {
        const message = notificationTemplate(key, locale);
        expect(message.title.trim()).not.toBe('');
        expect(message.body.trim()).not.toBe('');
        if (locale !== 'en') {
          expect(message).not.toEqual(notificationTemplate(key, 'en'));
        }
      }
    }

    expect(notificationTemplate('new_application', 'ar').title).toMatch(
      /[\u0600-\u06ff]/,
    );
  });
});
