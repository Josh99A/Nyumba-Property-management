export const SUPPORTED_LOCALES = ['en', 'lg', 'sw', 'ar'] as const;

export type SupportedLocale = typeof SUPPORTED_LOCALES[number];

export type NotificationTemplateKey =
  | 'new_application'
  | 'new_enquiry'
  | 'tenant_notice'
  | 'new_review'
  | 'review_response'
  | 'support_reply'
  | 'support_resolved';

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
  // Deliberately neutral: the notification must not reveal the score. A push
  // reading "you got 2 stars" on a lock screen invites a reaction written in
  // the worst possible frame of mind, and the reply is public.
  new_review: {
    en: {
      title: 'New tenant review',
      body: 'One of your tenants left a review. Open Nyumba to read and reply.',
    },
    lg: {
      title: 'Okwogera okupya okw’omupangisa',
      body: 'Omu ku bapangisa bo awadde endowooza. Ggulawo Nyumba osome era oddemu.',
    },
    sw: {
      title: 'Maoni mapya ya mpangaji',
      body: 'Mmoja wa wapangaji wako ameacha maoni. Fungua Nyumba usome na ujibu.',
    },
    ar: {
      title: 'مراجعة جديدة من مستأجر',
      body: 'ترك أحد مستأجريك مراجعة. افتح نيومبا للقراءة والرد.',
    },
  },
  review_response: {
    en: {
      title: 'Your landlord replied',
      body: 'There is a public reply to the review you left.',
    },
    lg: {
      title: 'Nnyini nnyumba addemu',
      body: 'Waliwo okuddamu okw’olukale ku ndowooza gye wawadde.',
    },
    sw: {
      title: 'Mwenye nyumba amejibu',
      body: 'Kuna jibu la hadharani kwa maoni uliyoacha.',
    },
    ar: {
      title: 'ردّ مالك العقار',
      body: 'هناك ردّ علني على المراجعة التي كتبتها.',
    },
  },
  // The reply itself is deliberately not in the body. A support answer can name
  // an amount, an account, or a tenant, and a lock screen is not a private
  // surface; the notification says where to look, not what was said.
  support_reply: {
    en: {
      title: 'Nyumba support replied',
      body: 'There is a new reply on your support conversation.',
    },
    lg: {
      title: 'Obuyambi bwa Nyumba buddemu',
      body: 'Waliwo okuddamu okupya ku mboozi yo ey’obuyambi.',
    },
    sw: {
      title: 'Msaada wa Nyumba umejibu',
      body: 'Kuna jibu jipya kwenye mazungumzo yako ya msaada.',
    },
    ar: {
      title: 'ردّ دعم نيومبا',
      body: 'هناك ردّ جديد على محادثة الدعم الخاصة بك.',
    },
  },
  support_resolved: {
    en: {
      title: 'Your support request was resolved',
      body: 'Open Nyumba to check it, or reply if it is not sorted.',
    },
    lg: {
      title: 'Okusaba kwo okw’obuyambi kumaliriddwa',
      body: 'Ggulawo Nyumba okukebera, oba oddemu bw’oba tekunnaggwa.',
    },
    sw: {
      title: 'Ombi lako la msaada limetatuliwa',
      body: 'Fungua Nyumba ukague, au jibu kama bado halijakamilika.',
    },
    ar: {
      title: 'تمّت معالجة طلب الدعم الخاص بك',
      body: 'افتح نيومبا للتحقق، أو ردّ إذا لم تُحل المشكلة.',
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
