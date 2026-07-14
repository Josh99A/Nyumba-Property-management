import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../domain/application.dart';
import '../domain/listing.dart';

/// Application-layer entry points for marketplace mutations.
final createListingDraftProvider = Provider<CreateListingDraft>(
  CreateListingDraft.new,
);
final publishListingProvider = Provider<PublishListing>(PublishListing.new);
final submitRentalApplicationProvider = Provider<SubmitRentalApplication>(
  SubmitRentalApplication.new,
);

class CreateListingDraft {
  const CreateListingDraft(this._ref);

  final Ref _ref;

  Future<Listing> call(CreateListingInput input) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.listings.createDraft(input);
  }
}

class PublishListing {
  const PublishListing(this._ref);

  final Ref _ref;

  Future<Listing> call(String listingId) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.listings.publish(listingId);
  }
}

class SubmitRentalApplication {
  const SubmitRentalApplication(this._ref);

  final Ref _ref;

  Future<RentalApplication> call(ApplyForUnitInput input) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.applications.apply(input);
  }
}
