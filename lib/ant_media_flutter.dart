// ignore_for_file: prefer_generic_function_type_aliases, constant_identifier_names

import 'dart:async';

import 'package:ant_media_flutter/src/helpers/helper.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:permission_handler/permission_handler.dart';

enum HelperState {
  CallStateNew,
  CallStateBye,
  ConnectionOpen,
  ConnectionClosed,
  ConnectionError,
}

enum AntMediaType { Default, Publish, Play, Peer, Conference, DataChannelOnly }

typedef void HelperStateCallback(HelperState state);
typedef void StreamStateCallback(MediaStream stream);
typedef void OtherEventCallback(dynamic event);
typedef void DataChannelMessageCallback(RTCDataChannel dc, RTCDataChannelMessage data, bool isReceived);
typedef void DataChannelCallback(RTCDataChannel dc);
typedef void ConferenceUpdateCallback(dynamic streams);
typedef void Callbacks(String command, Map mapData);

class DataChannelMessage extends Object {
  RTCDataChannelMessage message;
  bool isRecieved;
  RTCDataChannel channel;
  DataChannelMessage(this.isRecieved, this.channel, this.message);
}

class AntMediaFlutter {
  static AntHelper? anthelper;

  static Future<void> requestPermissions() async {
    await [
      Permission.audio,
      Permission.microphone,
      Permission.camera,
    ].request();
  }

  static Future<bool> startForegroundService() async {
    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: 'Running in background',
      notificationText: 'Background app is running',
      notificationImportance: AndroidNotificationImportance.max,
      notificationIcon: AndroidResource(name: 'background_icon', defType: 'drawable'),
    );
    await FlutterBackground.initialize(androidConfig: androidConfig);
    return FlutterBackground.enableBackgroundExecution();
  }

  static void connect(
    String ip,
    String streamId,
    String roomId,
    AntMediaType type,
    bool userScreen,
    HelperStateCallback onStateChange,
    StreamStateCallback onLocalStream,
    StreamStateCallback onAddRemoteStream,
    DataChannelCallback onDataChannel,
    DataChannelMessageCallback onDataChannelMessage,
    ConferenceUpdateCallback onupdateConferencePerson,
    StreamStateCallback onRemoveRemoteStream,
    List<Map<String, String>> iceServers,
    Callbacks callbacks,
  ) async {
    anthelper = null;
    anthelper ??= AntHelper(
        //host
        ip,

        //streamID
        streamId,

        //roomID
        roomId,

        //onStateChange
        onStateChange,

        //onAddRemoteStream
        onAddRemoteStream,

        //onDataChannel
        onDataChannel,

        //onDataChannelMessage
        onDataChannelMessage,

        //onLocalStream
        onLocalStream,

        //onRemoveRemoteStream
        onRemoveRemoteStream,

        //ScreenSharing
        userScreen,

        // onupdateConferencePerson
        onupdateConferencePerson,

        //iceServers
        iceServers,

        //callbacks
        callbacks)
      ..connect(
        type,
      );
  }
}
