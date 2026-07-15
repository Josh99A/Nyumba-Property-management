import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../domain/lease_document.dart';

final leaseDocumentsProvider = StreamProvider<List<LeaseDocument>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.leaseDocuments.watchAll();
});

final tenantLeaseDocumentsProvider =
    StreamProvider.family<List<LeaseDocument>, String>((ref, tenantId) async* {
      final deps = await ref.watch(appDependenciesProvider.future);
      yield* deps.leaseDocuments.watchAll(tenantId: tenantId);
    });

final createLeaseDocumentProvider = Provider<CreateLeaseDocument>(
  CreateLeaseDocument.new,
);

class CreateLeaseDocument {
  const CreateLeaseDocument(this._ref);

  final Ref _ref;

  Future<LeaseDocument> call(CreateLeaseDocumentInput input) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.leaseDocuments.create(input);
  }
}
