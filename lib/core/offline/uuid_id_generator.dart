import 'package:uuid/uuid.dart';

import '../domain/id_generator.dart';

final class UuidIdGenerator implements IdGenerator {
  UuidIdGenerator({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  @override
  String generate() => _uuid.v7();
}
