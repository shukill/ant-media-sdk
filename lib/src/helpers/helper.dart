// ignore_for_file: non_constant_identifier_names, unnecessary_this, curly_braces_in_flow_control_structures, unnecessary_new, avoid_print, prefer_const_constructors, constant_identifier_names, prefer_collection_literals, prefer_generic_function_type_aliases, prefer_final_fields, unnecessary_string_interpolations, prefer_interpolation_to_compose_strings

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ant_media_flutter/ant_media_flutter.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:record/record.dart';

import '../utils/websocket.dart' if (dart.library.js) '../utils/websocket_web.dart';

class AntHelper extends Object {
  MediaStream? _localStream;
  List<MediaStream> _remoteStreams = [];
  HelperStateCallback onStateChange;
  StreamStateCallback onLocalStream;
  StreamStateCallback onAddRemoteStream;
  StreamStateCallback onRemoveRemoteStream;
  DataChannelMessageCallback onDataChannelMessage;
  DataChannelCallback onDataChannel;
  ConferenceUpdateCallback onupdateConferencePerson;
  Callbacks callbacks;
  bool userScreen;
  String _streamId;
  String _roomId;
  String _host;
  Map<String, dynamic> _config = {};
  Timer? _ping;
  var _mute = false;
  AntMediaType _type = AntMediaType.Default;
  bool DataChannelOnly = false;
  List<Map<String, String>> iceServers;

  AntHelper(this._host, this._streamId, this._roomId, this.onStateChange, this.onAddRemoteStream, this.onDataChannel, this.onDataChannelMessage, this.onLocalStream, this.onRemoveRemoteStream, this.userScreen, this.onupdateConferencePerson, this.iceServers, this.callbacks) {
    final Map<String, dynamic> config = {
      "sdpSemantics": "plan-b",
      'iceServers': iceServers,
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    };
    if (this._type == AntMediaType.DataChannelOnly) DataChannelOnly = true;
    _config = config;
  }

  JsonEncoder _encoder = new JsonEncoder();
  SimpleWebSocket? _socket;

  var _peerConnections = new Map<String, RTCPeerConnection>();
  RTCDataChannel? _dataChannel;
  var _remoteCandidates = [];
  var _currentStreams = [];

  final Map<String, dynamic> _constraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
    },
    'optional': [],
  };

  final Map<String, dynamic> _dc_constraints = {
    'mandatory': {
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  close() {
    if (_localStream != null) {
      _localStream?.dispose();
      _localStream = null;
    }

    _peerConnections.forEach((key, pc) {
      pc.close();
    });
    _socket?.close();
  }

  Future<void> switchCamera() async {
    if (_localStream != null) {
      //  if (_localStream == null) throw Exception('Stream is not initialized');

      final videoTrack = _localStream!.getVideoTracks().firstWhere((track) => track.kind == 'video');
      Helper.switchCamera(videoTrack);
    }
  }

  Future<void> muteMic(bool mute) async {
    if (_localStream != null) {
      final audioTrack = _localStream!.getAudioTracks().firstWhere((track) => track.kind == 'audio');
      Helper.setMicrophoneMute(mute, audioTrack);
    }
  }

  Future<void> toggleCam(bool state) async {
    //true for on
    if (_localStream != null) {
      final videoTrack = _localStream!.getVideoTracks().firstWhere((track) => track.kind == 'video');
      videoTrack.enabled = state;
    }
  }

  void bye() {
    var request = new Map();
    request['command'] = 'stop';
    request['streamId'] = _streamId;

    _sendAntMedia(request);
  }

  void disconnectPeer() {
    var request = new Map();
    request['streamId'] = _streamId;
    request['command'] = 'leave';
    _sendAntMedia(request);
  }

  void onMessage(
    message,
  ) async {
    Map<String, dynamic> mapData = message;
    var command = mapData['command'];
    print('current command is ' + command);

    switch (command) {
      case 'start':
        {
          var id = mapData['streamId'];

          this.onStateChange(HelperState.CallStateNew);

          _peerConnections[id] = await _createPeerConnection(
            id,
            'publish',
            userScreen,
          );

          await _createDataChannel(_streamId, _peerConnections[_streamId]!);
          await _createOfferAntMedia(id, _peerConnections[id]!, 'publish');
          if (_type == AntMediaType.Publish || _type == AntMediaType.Peer || _type == AntMediaType.Conference || _type == AntMediaType.Default) {
            _startgettingRoomInfo(_streamId, _roomId);
          }
        }
        break;
      case 'takeConfiguration':
        {
          var id = mapData['streamId'];
          var type = mapData['type'];
          var sdp = mapData['sdp'];
          sdp = sdp?.replaceAll("a=extmap:13 urn:3gpp:video-orientation\r\n", "");
          var isTypeOffer = (type == 'offer');
          if (isTypeOffer) if (isTypeOffer) {
            this.onStateChange(HelperState.CallStateNew);
            _peerConnections[id] = await _createPeerConnection(
              id,
              'play',
              userScreen,
            );
            _createDataChannel(id, _peerConnections[id]!);
          }
          await _peerConnections[id]!.setRemoteDescription(new RTCSessionDescription(sdp, type));
          for (int i = 0; i < _remoteCandidates.length; i++) {
            await _peerConnections[id]!.addCandidate(_remoteCandidates[i]);
          }
          _remoteCandidates = [];
          if (isTypeOffer) await _createAnswerAntMedia(id, _peerConnections[id]!, 'play');
        }
        break;
      case 'stop':
        {
          closePeerConnection(_streamId);
        }
        break;

      case 'takeCandidate':
        {
          var id = mapData['streamId'];
          RTCIceCandidate candidate = new RTCIceCandidate(mapData['candidate'], mapData['id'], mapData['label']);
          if (_peerConnections[id] != null) {
            await _peerConnections[id]!.addCandidate(candidate);
          } else {
            _remoteCandidates.add(candidate);
          }
        }
        break;

      case 'error':
        {
          print(mapData['definition']);
          onStateChange(HelperState.ConnectionError);
        }
        break;

      case 'notification':
        {
          if (mapData['definition'] == 'play_finished' || mapData['definition'] == 'publish_finished') {
            closePeerConnection(_streamId);
          } else if (_type == AntMediaType.Publish || _type == AntMediaType.Peer || _type == AntMediaType.Conference || _type == AntMediaType.Default) {
            if (mapData['definition'] == 'joinedTheRoom') {
              await startStreamingAntMedia(_streamId, _roomId);
            }
          }

          if (mapData['definition'] == 'publish_started' || mapData['definition'] == 'play_started') {
            getStreamInfo(_streamId);
          }
        }
        break;
      case 'streamInformation':
        {
          this.callbacks(command, mapData);
          print(command + '' + mapData);
        }
        break;
      case 'roomInformation':
        {
          if (_type == AntMediaType.Publish || _type == AntMediaType.Peer || _type == AntMediaType.Conference || _type == AntMediaType.Default) {
            if (isStartedConferencing) {
              _startgettingRoomInfo(_streamId, _roomId);
            }
          }

          if (_type == AntMediaType.Conference) {
            if (_currentStreams != mapData['streams']) {
              var streams = mapData['streams'];
              this.onupdateConferencePerson(streams);
            }
          }
          this.callbacks(command, mapData);
        }
        break;
      case 'pong':
        {
          print(command);
        }
        break;
      case 'trackList':
        {
          print(command + ' ' + mapData);
        }
        break;
      case 'connectWithNewId':
        {
          if (_type == AntMediaType.Play || _type == AntMediaType.Peer || _type == AntMediaType.Conference) {
            join(_streamId);
          }
        }
        break;
      case 'peerMessageCommand':
        {
          print(command + ' ' + mapData);
        }
        break;
    }
  }

  connect(
    AntMediaType type,
  ) async {
    _type = type;
    var url = '$_host';
    _socket = SimpleWebSocket(url);

    if (this._type == AntMediaType.DataChannelOnly) DataChannelOnly = true;

    MediaStream? stream = await createStream(
      '',
      userScreen,
    );
    if (stream == null) {
      closeStreams();
      return;
    } else if (stream.getTracks().isEmpty) {
      closeStreams();
      return;
    } else {
      setStream(stream);
    }

    _socket?.onOpen = () {
      print('onOpen');
      this.onStateChange(HelperState.ConnectionOpen);

      if (_type == AntMediaType.Publish || _type == AntMediaType.DataChannelOnly) {
        startStreamingAntMedia(_streamId, _roomId);
      }
      if (_type == AntMediaType.Play) {
        _startPlayingAntMedia(_streamId, _roomId);
      }
      if (_type == AntMediaType.Peer) {
        join(_streamId);
      }
      if (_type == AntMediaType.Play || _type == AntMediaType.Conference) {
        joinroom(_streamId);
      }
      _ping = Timer.periodic(Duration(seconds: 5), (Timer timer) {
        var ping_msg = new Map();
        ping_msg['command'] = 'ping';
        _sendAntMedia(ping_msg);
      });
    };

    _socket?.onMessage = (message) {
      print('Received data: ' + message);
      JsonDecoder decoder = new JsonDecoder();
      this.onMessage(
        decoder.convert(message),
      );
    };

    _socket?.onClose = (int code, String reason) {
      print('Closed by server [$code => $reason]!');
      _ping?.cancel();
      this.onStateChange(HelperState.ConnectionClosed);
    };

    await _socket?.connect();
  }

  Future<void> _getSources() async {
    try {
      var sources = await desktopCapturer.getSources(
        types: [SourceType.Screen],
      );
      for (var element in sources) {
        print('name: ${element.name}, id: ${element.id}, type: ${element.type}');
      }

      return;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> getStreamListners() async {
    Future.delayed(const Duration(milliseconds: 100), () async {
      await _getSources();
    });
    desktopCapturer.onAdded.stream.listen((source) {});
    desktopCapturer.onRemoved.stream.listen((source) {});
  }

  Future<MediaStream?> createStream(
    media,
    userScreen,
  ) async {
    try {
      bool isWindows = Platform.isWindows;
      bool audioSupported = false;
      if (isWindows) {
        await getStreamListners();
        audioSupported = true;
      } else {
        final record = AudioRecorder();
        bool isRecordPermission = await record.hasPermission();

        if (isRecordPermission) {
          const opusEncoder = AudioEncoder.opus;
          const aacEncoder = AudioEncoder.aacLc;
          final isOpusSupported = await record.isEncoderSupported(
            opusEncoder,
          );
          if (!isOpusSupported) {
            final isAacEncoder = await record.isEncoderSupported(
              aacEncoder,
            );
            audioSupported = isAacEncoder;
          } else {
            audioSupported = true;
          }
        }
      }

      final Map<String, dynamic> audioConstraints = {
        'audio': true,
        'video': false,
      };
      final Map<String, dynamic> videoConstraints = {
        'audio': false,
        'video': true,
      };

      final Map<String, dynamic> mediaConstraints = {
        'video': {
          {
            'deviceId': {'exact': '0'},
            'mandatory': {
              {'videoMimeType': 'video/webm;codecs=vp8'},
            }
          }
        },
      };

      if (Platform.isAndroid) {
        await Helper.requestCapturePermission();
      }

      MediaStream videoStream = isWindows ? await navigator.mediaDevices.getDisplayMedia(mediaConstraints) : await navigator.mediaDevices.getDisplayMedia(videoConstraints);

      print(
        'STREAM STATUS AT CREATE STREAM $videoStream ${videoStream.getTracks().length}',
      );
      if (audioSupported) {
        MediaStream audioStream = await navigator.mediaDevices.getUserMedia(audioConstraints);

        List<MediaStreamTrack> mediaStreamTracks = audioStream.getAudioTracks();
        if (mediaStreamTracks.isNotEmpty) {
          videoStream.addTrack(mediaStreamTracks.first);
        }
      }

      this.onLocalStream(videoStream);
      return videoStream;
    } catch (e) {
      return null;
    }
  }

  setStream(MediaStream? media) {
    _localStream = media;
  }

  _createPeerConnection(
    id,
    media,
    user_Screen,
  ) async {
    if (_type == AntMediaType.Publish || _type == AntMediaType.Peer || _type == AntMediaType.Conference || _type == AntMediaType.Default) {
      if (media != 'data' && _localStream == null)
        _localStream = await createStream(
          media,
          user_Screen,
        );
      _remoteStreams.add(_localStream!);
    }

    RTCPeerConnection pc = await createPeerConnection(_config);

    if (_type == AntMediaType.Publish || _type == AntMediaType.Peer || _type == AntMediaType.Default || _type == AntMediaType.Conference && _type != AntMediaType.DataChannelOnly) {
      if (media != 'data' && _localStream != null) pc.addStream(_localStream!);
    }

    pc.onIceCandidate = (candidate) {
      var request = new Map();
      request['command'] = 'takeCandidate';
      request['streamId'] = id;
      request['label'] = candidate.sdpMLineIndex;
      request['id'] = candidate.sdpMid;
      request['candidate'] = candidate.candidate;
      _sendAntMedia(request);
    };

    pc.onIceConnectionState = (state) {};

    pc.onAddStream = (stream) {
      this.onAddRemoteStream(stream);
      _remoteStreams.add(stream);
    };

    pc.onRemoveStream = (stream) {
      this.onRemoveRemoteStream(stream);
      _remoteStreams.removeWhere((it) {
        return (it.id == stream.id);
      });
    };

    pc.onDataChannel = (channel) {
      _addDataChannel(id, channel);
    };

    if (_type == AntMediaType.Publish || _type == AntMediaType.Peer || _type == AntMediaType.Conference && _type != AntMediaType.DataChannelOnly) {
      pc.addStream(_localStream!);
    }

    return pc;
  }

  _addDataChannel(id, RTCDataChannel channel) {
    channel.onDataChannelState = (e) {};
    channel.onMessage = (RTCDataChannelMessage data) {
      this.onDataChannelMessage(channel, data, true);
    };
    _dataChannel = channel;

    this.onDataChannel(channel);
  }

  _createDataChannel(id, RTCPeerConnection pc, {label = 'fileTransfer'}) async {
    RTCDataChannelInit dataChannelDict = new RTCDataChannelInit();
    RTCDataChannel channel = await pc.createDataChannel(label, dataChannelDict);
    _addDataChannel(id, channel);
  }

  _createOfferAntMedia(String id, RTCPeerConnection pc, String media) async {
    try {
      RTCSessionDescription s = await pc.createOffer(DataChannelOnly ? _dc_constraints : _constraints);
      pc.setLocalDescription(s);
      var request = new Map();
      request['command'] = 'takeConfiguration';
      request['streamId'] = id;
      request['type'] = s.type;
      request['sdp'] = s.sdp;
      _sendAntMedia(request);
    } catch (e) {
      print(e.toString());
    }
  }

  _createAnswerAntMedia(String id, RTCPeerConnection pc, media) async {
    try {
      RTCSessionDescription s = await pc.createAnswer(DataChannelOnly ? _dc_constraints : _constraints);
      pc.setLocalDescription(s);

      var request = new Map();
      request['command'] = 'takeConfiguration';
      request['streamId'] = id;
      request['type'] = s.type;
      request['sdp'] = s.sdp;
      _sendAntMedia(request);
    } catch (e) {
      print(e.toString());
    }
  }

  _sendAntMedia(request) {
    _socket?.send(_encoder.convert(request));
  }

  closePeerConnection(streamId) {
    var id = streamId;
    print('bye: ' + id);
    if (_mute) muteMic(false);
    if (_localStream != null) {
      _localStream?.dispose();
      _localStream = null;
    }
    var pc = _peerConnections[id];
    if (pc != null) {
      pc.close();
      _peerConnections.remove(id);
    }
    var dc = _dataChannel;
    if (dc != null) {
      dc.close();
    }
    this.onStateChange(HelperState.CallStateBye);
  }

  closeStreams() {
    if (_mute) muteMic(false);
    if (_localStream != null) {
      _localStream?.dispose();
      _localStream = null;
    }
    var dc = _dataChannel;
    if (dc != null) {
      dc.close();
    }
    this.onStateChange(HelperState.CallStateBye);
  }

  startStreamingAntMedia(streamId, token) {
    var request = new Map();
    request['command'] = 'publish';
    request['streamId'] = streamId;
    request['token'] = token;
    request['video'] = !DataChannelOnly;
    request['audio'] = !DataChannelOnly;
    _sendAntMedia(request);
  }

  forceStreamQuality(streamId, resolution) {
    var request = new Map();
    request['command'] = 'forceStreamQuality';
    request['streamId'] = streamId;
    request['streamHeight'] = resolution;
    print("requesting new stream resolution $resolution");
    _sendAntMedia(request);
  }

  join(streamId) {
    var request = new Map();
    request['command'] = 'join';
    request['streamId'] = streamId;
    request['multiPeer'] = false;
    request['mode'] = 'play or both';
    _sendAntMedia(request);
  }

  joinroom(streamId) {
    var request = new Map();
    request['command'] = 'joinRoom';
    request['streamId'] = streamId;
    request['room'] = _roomId;
    _sendAntMedia(request);
  }

  _startPlayingAntMedia(streamId, token) {
    var request = new Map();
    request['command'] = 'play';
    request['streamId'] = streamId;
    request['token'] = token;
    _sendAntMedia(request);
  }

  Future<void> sendMessage(RTCDataChannelMessage message) async {
    if (_dataChannel != null) {
      await _dataChannel?.send(message);
      onDataChannelMessage(_dataChannel!, message, false);
    }
  }

  getStreamInfo(streamId) {
    var request = Map();
    request['command'] = 'getStreamInfo';
    request['streamId'] = streamId;
    _sendAntMedia(request);
  }

  _startgettingRoomInfo(
    streamId,
    roomId,
  ) {
    isStartedConferencing = true;
    var request = new Map();
    request['command'] = 'getRoomInfo';
    request['streamId'] = streamId;
    request['room'] = roomId;
    _sendAntMedia(request);
  }

  List<String> arrStreams = <String>[];

  bool isStartedConferencing = false;
}
