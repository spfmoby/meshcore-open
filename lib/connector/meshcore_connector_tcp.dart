import 'dart:typed_data';

import '../services/app_debug_log_service.dart';
import '../services/tcp_transport_service.dart';

class MeshCoreTcpManager {
  final TcpTransportService _service = TcpTransportService();
  AppDebugLogService? _debugLog;

  String? get activeEndpoint => _service.activeEndpoint;
  bool get isConnected => _service.isConnected;
  Stream<Uint8List> get frameStream => _service.frameStream;

  void setDebugLogService(AppDebugLogService? service) {
    _debugLog = service;
    _service.setDebugLogService(service);
  }

  Future<void> connect({required String host, required int port}) async {
    _debugLog?.info('TcpManager.connect endpoint=$host:$port', tag: 'TCP');
    await _service.connect(host: host, port: port);
  }

  Future<void> disconnect() async {
    _debugLog?.info('TcpManager.disconnect', tag: 'TCP');
    await _service.disconnect();
  }

  Future<void> write(Uint8List data) => _service.write(data);

  void dispose() {
    _service.dispose();
  }
}
