import 'package:flutter_test/flutter_test.dart';
import 'package:sysnergi/data/demo_repository.dart';

void main() {
  test('demo history 24 jam berisi data', () async {
    final repo = DemoRepository();
    final h = await repo.history('SYN-0A12', 'P1', const Duration(hours: 24));
    expect(h.length, greaterThan(8));
    final w = await repo.history('SYN-0A41', 'P1', const Duration(days: 7));
    expect(w, isNotEmpty);
    repo.dispose();
  });
}
