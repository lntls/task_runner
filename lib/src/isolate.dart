import 'dart:async';
import 'dart:isolate';

typedef Task<R> = FutureOr<R> Function();

class _Message<R> {
  _Message(this.task, this.respoonsePort);

  final Task<R> task;

  final SendPort respoonsePort;
}

class IsolateService {
  IsolateService._() {
    _port.handler = _handleMessage;
    _current = this;
  }

  static IsolateService? _current;
  static IsolateService get current {
    if (_current == null) {
      throw StateError('Do not use IsolateService in root isolate.');
    }

    return _current!;
  }

  final _port = RawReceivePort();

  void _close() {
    _port.close();
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

      message.respoonsePort.send(List.filled(1, result));
    } catch (e, stackTrace) {
      message.respoonsePort.send(List<Object?>.filled(2, null)
        ..[0] = e
        ..[1] = stackTrace);
    }
  }
}

class IsolateLocal {
  IsolateLocal._() {
    _current = this;
  }

  static IsolateLocal? _current;
  static IsolateLocal get current {
    if (_current == null) {
      throw StateError('Do not use IsolateLocal in root isolate.');
    }

    return _current!;
  }

  final _data = <Type, Object?>{};

  void put<T>(T value) {
    _data[T] = value;
  }

  T get<T>() {
    return _data[T] as T;
  }

  T remove<T>() {
    return _data.remove(T) as T;
  }

  bool contains<T>() {
    return _data.containsKey(T);
  }
}

class IsolateClient {
  IsolateClient._(this._isolate, this._sendPort);

  static Future<IsolateClient> create({String? debugName}) async {
    final completer = Completer<SendPort>();
    final resultPort = RawReceivePort();
    resultPort.handler = (SendPort sendPort) {
      resultPort.close();
      completer.complete(sendPort);
    };

    final Isolate isolate;
    final SendPort port;
    try {
      isolate = await Isolate.spawn(
        (SendPort sendPort) {
          IsolateService._();
          IsolateLocal._();
          sendPort.send(IsolateService.current._port.sendPort);
        },
        resultPort.sendPort,
        debugName: debugName,
      );
      port = await completer.future;
    } catch (error, stackTrace) {
      resultPort.close();
      completer.completeError(error, stackTrace);
      rethrow;
    }

    return IsolateClient._(isolate, port);
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
      return IsolateService.current._close();
    });
  }
}
