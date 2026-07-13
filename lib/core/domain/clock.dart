abstract interface class Clock {
  DateTime now();
}

final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

final class FixedClock implements Clock {
  const FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value.toUtc();
}
