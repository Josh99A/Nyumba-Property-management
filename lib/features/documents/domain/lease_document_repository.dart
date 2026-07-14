import 'lease_document.dart';

abstract interface class LeaseDocumentRepository {
  Stream<List<LeaseDocument>> watchAll({String? landlordId, String? tenantId});
  Future<List<LeaseDocument>> getAll({String? landlordId, String? tenantId});
  Future<LeaseDocument?> getById(String id);
  Future<LeaseDocument> create(CreateLeaseDocumentInput input);
}
