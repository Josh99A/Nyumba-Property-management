// ignore_for_file: prefer_initializing_formals

import 'package:uuid/uuid.dart';

import 'id_generator.dart';

final class UuidIdGenerator implements IdGenerator {
  const UuidIdGenerator({Uuid uuid = const Uuid()}) : _uuid = uuid;

  final Uuid _uuid;

  @override
  String generate() => _uuid.v7();
}
