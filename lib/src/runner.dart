import 'dart:async';

import 'isolate.dart';

class TaskRunnerError extends Error {
  TaskRunnerError({this.debugName, required this.message});

  final String? debugName;

  final String message;

  @override
  String toString() {
    if (debugName != null) {
      return 'TaskRunner($debugName): $message';
    }
    return 'TaskRunner: $message';
  }
}

abstract class TaskRunner {
  /// [size] numbers of isolates.
  factory TaskRunner({
    String? debugName,
    int size = 1,
    OnStart? onStart,
    OnStop? onStop,
  }) {
    if (size > 1) {
      return MutliIsolateTaskRunner(
        debugName: debugName,
        size: size,
        onStart: onStart,
        onStop: onStop,
      );
    } else {
      return SingleIsolateTaskRunner(
        debugName: debugName,
        onStart: onStart,
        onStop: onStop,
      );
    }
  }

  Future<R> run<R>(Task<R> task);

  Future<void> close();
}

class SingleIsolateTaskRunner implements TaskRunner {
  SingleIsolateTaskRunner({
    this.debugName,
    OnStart? onStart,
    OnStop? onStop,
  })  : _onStart = onStart,
        _onStop = onStop;

  final String? debugName;

  final OnStart? _onStart;

  final OnStop? _onStop;

  IsolateClient? _client;

  bool _isClosed = false;

  Completer<void>? _completer;

  int _taskCount = 0;

  void _checkNotClosed() {
    if (_isClosed) {
      throw TaskRunnerError(
        debugName: debugName,
        message: 'This runner already closed.',
      );
    }
  }

  Future<void> _init() async {
    _completer = Completer<void>();
    _client = await IsolateClient.create(
      debugName: debugName,
      onStart: _onStart,
      onStop: _onStop,
    );
    _completer!.complete();
  }

  @override
  Future<void> close() async {
    _checkNotClosed();

    _isClosed = true;
    await _client?.close();
    _client = null;
  }

  @override
  Future<R> run<R>(Task<R> task) async {
    _checkNotClosed();

    _taskCount += 1;

    if (_client == null) {
      if (_completer == null) {
        _init();
      }
      await _completer!.future;
    }

    return _client!.postTask(task).whenComplete(() {
      _taskCount -= 1;

      if (_isClosed && _client != null && _taskCount == 0) {
        _client!.close();
        _client == null;
      }
    });
  }

  void _ping(void Function() action) {
    if (_taskCount == 0) {
      action();
    } else {
      run(() {
        // do nothing.
      })
          .then((_) => action());
    }
  }
}

class MutliIsolateTaskRunner implements TaskRunner {
  MutliIsolateTaskRunner({
    String? debugName,
    int size = 1,
    OnStart? onStart,
    OnStop? onStop,
  }) : _runners = List.generate(
          size,
          (index) {
            return SingleIsolateTaskRunner(
              debugName: debugName == null ? null : '$debugName($index)',
              onStart: onStart,
              onStop: onStop,
            );
          },
          growable: false,
        );

  final List<SingleIsolateTaskRunner> _runners;

  void _waitIdleRunner(void Function(TaskRunner runner) action) {
    void Function(TaskRunner)? pending = action;

    for (final runner in _runners) {
      if (runner._taskCount == 0) {
        pending!(runner);
        pending = null;
        return;
      }

      runner._ping(() {
        if (pending != null) {
          pending!(runner);
          pending = null;
        }
      });
    }
  }

  @override
  Future<void> close() async {
    await Future.wait(
        _runners.map((runner) => runner.close()).toList(growable: false));
  }

  @override
  Future<R> run<R>(Task<R> task) {
    final completer = Completer<R>();
    _waitIdleRunner((runner) {
      runner.run(task).then((result) {
        completer.complete(result);
      }, onError: (e, stackTrace) {
        completer.completeError(e, stackTrace);
      });
    });
    return completer.future;
  }
}

extension TaskRunnerExtension on TaskRunner {
  Future<R> runWithArgs<R, A>(FutureOr<R> Function(A) task, {required A args}) {
    return run(() {
      return task(args);
    });
  }
}
