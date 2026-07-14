import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../domain/property.dart';
import '../domain/unit.dart';

/// Application-layer entry points for portfolio mutations. Presentation
/// invokes these instead of repositories so orchestration, policy checks,
/// and the workspace lifecycle stay out of widgets.
final createPropertyProvider = Provider<CreateProperty>(CreateProperty.new);
final createUnitProvider = Provider<CreateUnit>(CreateUnit.new);
final getPropertyByIdProvider = Provider<GetPropertyById>(GetPropertyById.new);

class CreateProperty {
  const CreateProperty(this._ref);

  final Ref _ref;

  Future<Property> call(CreatePropertyInput input) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.properties.create(input);
  }
}

class CreateUnit {
  const CreateUnit(this._ref);

  final Ref _ref;

  Future<Unit> call(CreateUnitInput input) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.units.create(input);
  }
}

class GetPropertyById {
  const GetPropertyById(this._ref);

  final Ref _ref;

  Future<Property?> call(String propertyId) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.properties.getById(propertyId);
  }
}
