import '../../auth/domain/user_session.dart';

final class MarketplaceNavigationAction {
  const MarketplaceNavigationAction({required this.label, required this.path});

  final String label;
  final String path;
}

MarketplaceNavigationAction marketplaceNavigationAction(UserSession? session) {
  if (session == null) {
    return const MarketplaceNavigationAction(
      label: 'Sign in',
      path: '/sign-in',
    );
  }
  final workspacePath = session.workspacePath;
  final needsOnboarding =
      session.role == AppRole.client && !session.isAnonymous;
  if (workspacePath == null && needsOnboarding) {
    return const MarketplaceNavigationAction(
      label: 'Complete setup',
      path: '/onboarding',
    );
  }
  if (workspacePath == null) {
    return const MarketplaceNavigationAction(
      label: 'Explore',
      path: '/explore',
    );
  }
  return MarketplaceNavigationAction(
    label: 'My workspace',
    path: workspacePath,
  );
}
