import 'application.dart';

abstract interface class ApplicationRepository {
  Stream<List<RentalApplication>> watchAll({
    String? applicantId,
    String? listingId,
  });
  Stream<RentalApplication?> watchById(String id);
  Future<List<RentalApplication>> getAll({
    String? applicantId,
    String? listingId,
  });
  Future<RentalApplication?> getById(String id);
  Future<RentalApplication> apply(ApplyForUnitInput input);
  Future<RentalApplication> update(RentalApplication application);
}
