import 'notice.dart';

abstract interface class NoticeRepository {
  Stream<List<Notice>> watchAll({String? landlordId});
  Future<List<Notice>> getAll({String? landlordId});
  Future<Notice?> getById(String id);
  Future<Notice> create(CreateNoticeInput input);
}
