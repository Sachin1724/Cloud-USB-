import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';
import 'drive_manager.dart';

class TunnelClient {
  static IOWebSocketChannel? _channel;
  static bool _isConnected = false;
  static bool _shouldReconnect = true;
  static Timer? _reconnectTimer;
  static int _reconnectAttempts = 0;

  static bool get isConnected => _isConnected;

  static Future<void> start(String token) async {
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    await _connect(token);
  }

  static Future<void> _connect(String token) async {
    if (_isConnected) return;

    final prefs = await SharedPreferences.getInstance();
    final brokerBaseUrl = prefs.getString('broker_url') ?? 'https://cloud-usb.onrender.com';
    final cloudWsUrl = brokerBaseUrl.replaceAll('http://', 'ws://').replaceAll('https://', 'wss://');
    String agentId = prefs.getString('agent_id') ?? 'desktop-node-01';
    
    // NEW: Pass the selected drive in the connection headers to ensure sync after backend restarts
    String activeDrive = (prefs.getString('selected_drive') ?? '').replaceAll('\\', '').trim();

    try {
      final wsUrl = Uri.parse(cloudWsUrl);
      final ws = await WebSocket.connect(
        wsUrl.toString(),
        headers: {
          'x-agent-id': agentId,
          'x-active-drive': activeDrive,
          'authorization': 'Bearer $token',
        },
      );
      
      _channel = IOWebSocketChannel(ws);
      _isConnected = true;
      _reconnectAttempts = 0;
      debugPrint('[DriveNet Agent] Connected. Serving Drive: $activeDrive');

      _channel!.stream.listen(
        (message) async {
          try {
            final data = jsonDecode(message) as Map<String, dynamic>;
            final requestId = data['requestId']?.toString();
            final action = data['action']?.toString();
            final payload = data['payload'] as Map<String, dynamic>? ?? {};

            if (requestId != null && action != null) {
              try {
                void wsSend(Map<String, dynamic> response) {
                  if (_isConnected) {
                    _channel?.sink.add(jsonEncode(response));
                  }
                }
                final result = await DriveManager.handleFileRequest(action, payload, wsSend, requestId);
                if (result != null) {
                  wsSend({
                    'requestId': requestId,
                    'payload': result,
                  });
                }
              } catch (err) {
                if (_isConnected) {
                  _channel?.sink.add(jsonEncode({'requestId': requestId, 'error': err.toString()}));
                }
              }
            }
          } catch (err) {
            debugPrint('[DriveNet Agent] Message parsing error: $err');
          }
        },
        onDone: () { _isConnected = false; _scheduleReconnect(token); },
        onError: (err) { _isConnected = false; _scheduleReconnect(token); },
      );
    } catch (e) {
      _isConnected = false;
      _scheduleReconnect(token);
    }
  }

  static void _scheduleReconnect(String token) {
    if (!_shouldReconnect) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final seconds = [5, 15, 30, 60][(_reconnectAttempts - 1).clamp(0, 3)];
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _connect(token);
    });
  }

  static void stop() {
    _shouldReconnect = false;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }
}
