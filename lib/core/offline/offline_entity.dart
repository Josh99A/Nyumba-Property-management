enum OfflineEntityType {
  userProfile('user_profiles', 5),
  property('properties', 10),
  unit('units', 20),
  listing('listings', 30),
  application('applications', 40);

  const OfflineEntityType(this.storeName, this.syncPriority);

  final String storeName;
  final int syncPriority;
}

final class AggregateReference {
  const AggregateReference({required this.type, required this.id});

  final OfflineEntityType type;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is AggregateReference && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}
