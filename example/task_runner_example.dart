import 'package:task_runner/task_runner.dart';

void main() {
  final taskRunner = TaskRunner();
  taskRunner.run(() {
    print('Hello TaskRunner!');
  });
  taskRunner.run(() {
    IsolateService.current.put<int>(100);
    IsolateService.current.get<int>();
  });
  taskRunner.run(() {
    print('IsolateLocal: ${IsolateService.current.get<int>()}');
  });
  taskRunner.close();
}
