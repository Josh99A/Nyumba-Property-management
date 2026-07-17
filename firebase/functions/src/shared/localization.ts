export const SUPPORTED_LOCALES = ['en', 'lg', 'sw', 'ar'] as const;

export type SupportedLocale = typeof SUPPORTED_LOCALES[number];

export type NotificationTemplateKey =
  | 'new_application'
  | 'new_enquiry'
  | 'tenant_notice';

interface LocalizedNotification {
  title: string;
  body: string;
}

const NOTIFICATION_TEMPLATES: Record<
  NotificationTemplateKey,
  Record<SupportedLocale, LocalizedNotification>
> = {
  new_application: {
    en: {
      title: 'New application',
      body: 'A prospect submitted an application for one of your listings.',
    },
    lg: {
      title: 'Okusaba okupya',
      body: 'Omunoonya amaka aweerezza okusaba ku kamu ku bulangirira bwo.',
    },
    sw: {
      title: 'Ombi jipya',
      body: 'Mteja mtarajiwa ametuma ombi kwa moja ya matangazo yako.',
    },
    ar: {
      title: 'طلب جديد',
      body: 'قدّم عميل محتمل طلبًا لأحد إعلاناتك.',
    },
  },
  new_enquiry: {
    en: {
      title: 'New enquiry',
      body: 'A prospect sent an enquiry about one of your listings.',
    },
    lg: {
      title: 'Okubuuza okupya',
      body: 'Omunoonya amaka abuuza ku kamu ku bulangirira bwo.',
    },
    sw: {
      title: 'Swali jipya',
      body: 'Mteja mtarajiwa ameuliza kuhusu moja ya matangazo yako.',
    },
    ar: {
      title: 'استفسار جديد',
      body: 'أرسل عميل محتمل استفسارًا عن أحد إعلاناتك.',
    },
  },
  tenant_notice: {
    en: {
      title: 'New property notice',
      body: 'A new notice from your property manager is ready in Nyumba.',
    },
    lg: {
      title: 'Obubaka obupya ku nnyumba',
      body: 'Obubaka obupya okuva eri omuddukanya w’ennyumba bulindirira mu Nyumba.',
    },
    sw: {
      title: 'Taarifa mpya ya nyumba',
      body: 'Taarifa mpya kutoka kwa msimamizi wa nyumba yako iko tayari katika Nyumba.',
    },
    ar: {
      title: 'إشعار عقار جديد',
      body: 'يوجد إشعار جديد من مدير العقار جاهز في نيومبا.',
    },
  },
};

export function supportedLocale(raw: unknown): SupportedLocale {
  return typeof raw === 'string'
    && (SUPPORTED_LOCALES as readonly string[]).includes(raw)
    ? raw as SupportedLocale
    : 'en';
}

export function notificationTemplate(
  key: NotificationTemplateKey,
  locale: SupportedLocale,
): LocalizedNotification {
  return NOTIFICATION_TEMPLATES[key][locale];
}
