import 'package:task_runner/task_runner.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests', () {
    final runner = TaskRunner();

    setUp(() {
      // Additional setup goes here.
    });

    test('First Test', () async {
      final result = await runner.run(() => true);

      expect(result, isTrue);
    });

    tearDown(() {
      runner.close();
    });
  });
}
