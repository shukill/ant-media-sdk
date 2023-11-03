// ignore_for_file: avoid_print, prefer_final_fields, prefer_typing_uninitialized_variables

import 'dart:io';

typedef OnMessageCallback = void Function(dynamic msg);
typedef OnCloseCallback = void Function(int code, String reason);
typedef OnOpenCallback = void Function();

class SimpleWebSocket {
  String _url;
  var _socket;
  OnOpenCallback? onOpen;
  OnMessageCallback? onMessage;
  OnCloseCallback? onClose;

  SimpleWebSocket(this._url);

  connect() async {
    try {
      _socket = await WebSocket.connect(_url);
      //_socket = await _connectForSelfSignedCert(_url);

      if (onOpen != null) {
        onOpen!();
      }

      _socket.listen((data) {
        if (onMessage != null) {
          onMessage!(data);
        }
      }, onDone: () {
        if (onClose != null) {
          onClose!(_socket.closeCode, _socket.closeReason);
        }
      });
    } catch (e) {
      if (onClose != null) {
        onClose!(500, e.toString());
      }
    }
  }

  void send(data) {
    if (_socket != null) {
      _socket.add(data);
      print('send: $data');
    }
  }

  close() {
    if (_socket != null) _socket.close();
  }
}
