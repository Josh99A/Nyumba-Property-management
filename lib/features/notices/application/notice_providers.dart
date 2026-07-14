import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../domain/notice.dart';

final noticesProvider = StreamProvider<List<Notice>>((ref) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.notices.watchAll();
});

final createNoticeProvider = Provider<CreateNotice>(CreateNotice.new);

class CreateNotice {
  const CreateNotice(this._ref);

  final Ref _ref;

  Future<Notice> call(CreateNoticeInput input) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.notices.create(input);
  }
}
