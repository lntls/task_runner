import 'package:task_runner/task_runner.dart';

void main() {
  final taskRunner = TaskRunner();
  taskRunner.run(() {
    print('Hello TaskRunner!');
  });
  taskRunner.run(() {
    IsolateLocal.current.put<int>(100);
    IsolateLocal.current.get<int>();
  });
  taskRunner.run(() {
    print('IsolateLocal: ${IsolateLocal.current.get<int>()}');
  });
  taskRunner.close();
}
