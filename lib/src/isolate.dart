import 'dart:async';
import 'dart:isolate';

typedef Task<R> = FutureOr<R> Function();
typedef OnStart = void Function();
typedef OnStop = void Function();

class _Message<R> {
  _Message(this.task, this.responsePort);

  final Task<R> task;

  final SendPort responsePort;
}

class IsolateService {
  IsolateService._(this._onStart, this._onStop) {
    if (_current != null) {
      throw StateError('IsolateService already created.');
    }

    _current = this;
  }

  static IsolateService? _current;
  static IsolateService get current {
    if (_current == null) {
      throw StateError('IsolateService not created.');
    }

    if (_current!.isStopped) {
      throw StateError('IsolateService already stopped.');
    }

    return _current!;
  }

  final OnStart? _onStart;

  final OnStop? _onStop;

  final _port = RawReceivePort();

  final _data = <Type, Object?>{};

  bool _isStopped = false;
  bool get isStopped => _isStopped;

  void put<T>(T value) {
    _data[T] = value;
  }

  T? get<T>() {
    return _data[T] as T?;
  }

  T? remove<T>() {
    return _data.remove(T) as T?;
  }

  bool contains<T>() {
    return _data.containsKey(T);
  }

  void _start(void Function(SendPort) action) {
    try {
      _onStart?.call();
    } finally {
      _port.handler = _handleMessage;
      action(_port.sendPort);
    }
  }

  void _stop() {
    try {
      _onStop?.call();
    } finally {
      _isStopped = true;
      _port.close();
    }
  }

  Future<void> _handleMessage(_Message message) async {
    try {
      final Object? result;
      final potentiallyAsyncResult = message.task();
      if (potentiallyAsyncResult is Future) {
        result = await potentiallyAsyncResult;
      } else {
        result = potentiallyAsyncResult;
      }

      message.responsePort.send(List.filled(1, result));
    } catch (e, stackTrace) {
      message.responsePort.send(List<Object?>.filled(2, null)
        ..[0] = e
        ..[1] = stackTrace);
    }
  }
}

class IsolateClient {
  IsolateClient._(this._isolate, this._sendPort);

  static Future<IsolateClient> create({
    String? debugName,
    OnStart? onStart,
    OnStop? onStop,
  }) async {
    final completer = Completer<SendPort>();
    final resultPort = RawReceivePort();
    resultPort.handler = (SendPort sendPort) {
      resultPort.close();
      completer.complete(sendPort);
    };

    try {
      final message = List<Object?>.filled(3, null)
        ..[0] = resultPort.sendPort
        ..[1] = onStart
        ..[2] = onStop;
      final isolate = await Isolate.spawn(
        (List<Object?> message) {
          final sendPort = message[0] as SendPort;
          IsolateService._(
            message[1] as OnStart?,
            message[2] as OnStop?,
          )._start((port) => sendPort.send(port));
        },
        message,
        debugName: debugName,
      );

      return IsolateClient._(isolate, await completer.future);
    } catch (error, stackTrace) {
      resultPort.close();
      completer.completeError(error, stackTrace);
      rethrow;
    }
  }

  final Isolate _isolate;

  final SendPort _sendPort;

  Future<R> postTask<R>(Task<R> task) {
    final completer = Completer<R>();
    final respoonsePort = RawReceivePort();
    respoonsePort.handler = (List<Object?> respoonse) {
      respoonsePort.close();
      if (respoonse.length == 2) {
        completer.completeError(respoonse[0]!, respoonse[1] as StackTrace);
      } else {
        completer.complete(respoonse[0] as R);
      }
    };

    _sendPort.send(_Message(task, respoonsePort.sendPort));

    return completer.future;
  }

  Future<void> close() {
    return postTask(() {
      return IsolateService.current._stop();
    });
  }
}
