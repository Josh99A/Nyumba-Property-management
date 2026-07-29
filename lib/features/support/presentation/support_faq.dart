import '../domain/support_ticket.dart';

/// An answer a landlord can get without waiting for one.
///
/// The cheapest support ticket is the one nobody had to open, and this list
/// costs a static array. Every entry earns its place by being a question the
/// product actually provokes — a subscription that reads "pending" after
/// payment, a tenant who cannot sign in — rather than by filling a section.
///
/// [category] is what the composer preselects when someone opens the composer
/// from that answer, so a person who read the wrong answer still lands in the
/// right queue.
final class SupportAnswer {
  const SupportAnswer({
    required this.question,
    required this.answer,
    required this.category,
  });

  final String question;
  final String answer;
  final SupportCategory category;
}

const List<SupportAnswer> supportAnswers = <SupportAnswer>[
  SupportAnswer(
    question: 'Why does my subscription still say pending?',
    answer:
        'A payment you sent by mobile money or cash is confirmed by the Nyumba '
        'team, not automatically. That usually happens the same working day. '
        'Your workspace opens the moment it is confirmed — nothing is lost in '
        'the meantime.',
    category: SupportCategory.billing,
  ),
  SupportAnswer(
    question: 'My tenant paid in cash. How do I record it?',
    answer:
        'Open Finances, choose Record a payment, and pick the tenant and the '
        'period it covers. Nyumba generates the receipt and the tenant sees it '
        'in their portal straight away.',
    category: SupportCategory.payments,
  ),
  SupportAnswer(
    question: 'My tenant says the payment they reported is still waiting.',
    answer:
        'A payment a tenant reports is a claim until you confirm it, so their '
        'balance does not move on their say-so. Open Finances to confirm or '
        'reject it — they are told either way.',
    category: SupportCategory.payments,
  ),
  SupportAnswer(
    question: 'My tenant cannot sign in.',
    answer:
        'A tenant reaches their portal by claiming the invitation you sent to '
        'their email or phone. If that invitation was never opened, resend it '
        'from the tenant\'s page. They cannot create their own account.',
    category: SupportCategory.tenants,
  ),
  SupportAnswer(
    question: 'How long does a listing stay published?',
    answer:
        'Thirty days. You are warned before it expires and can renew it in one '
        'tap, which starts a fresh thirty days without rewriting the advert.',
    category: SupportCategory.listings,
  ),
  SupportAnswer(
    question: 'Why will my listing not publish?',
    answer:
        'A public advert needs at least one photo of the rental space and a '
        'unit that is actually available. Photos on the property record are '
        'private and are never used on an advert.',
    category: SupportCategory.listings,
  ),
  SupportAnswer(
    question: 'How do I add someone to my team?',
    answer:
        'Open Team and invite them by email. You choose exactly what they can '
        'reach — a caretaker handling maintenance never sees your finances.',
    category: SupportCategory.account,
  ),
  SupportAnswer(
    question: 'My photos failed to upload.',
    answer:
        'Photos upload when your device next reaches the internet, so a weak '
        'connection delays them rather than losing them. If one keeps failing, '
        'it is usually over the 5 MB limit — retake it at a smaller size.',
    category: SupportCategory.listings,
  ),
];
