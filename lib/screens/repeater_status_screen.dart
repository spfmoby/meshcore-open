import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../services/repeater_command_service.dart';

class RepeaterStatusScreen extends StatefulWidget {
  final Contact repeater;
  final String password;

  const RepeaterStatusScreen({
    super.key,
    required this.repeater,
    required this.password,
  });

  @override
  State<RepeaterStatusScreen> createState() => _RepeaterStatusScreenState();
}

class _RepeaterStatusScreenState extends State<RepeaterStatusScreen> {
  bool _isLoading = false;
  StreamSubscription<Uint8List>? _frameSubscription;
  RepeaterCommandService? _commandService;
  Timer? _statusTimeout;
  DateTime? _statusRequestedAt;
  int? _batteryMv;
  int? _uptimeSecs;
  int? _queueLen;
  int? _debugFlags;
  int? _lastRssi;
  double? _lastSnr;
  int? _noiseFloor;
  int? _txAirSecs;
  int? _rxAirSecs;
  int? _packetsSent;
  int? _packetsRecv;
  int? _floodTx;
  int? _directTx;
  int? _floodRx;
  int? _directRx;
  int? _dupFlood;
  int? _dupDirect;

  @override
  void initState() {
    super.initState();
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    _commandService = RepeaterCommandService(connector);
    _setupMessageListener();
    _loadStatus();
  }

  @override
  void dispose() {
    _frameSubscription?.cancel();
    _commandService?.dispose();
    _statusTimeout?.cancel();
    super.dispose();
  }

  void _setupMessageListener() {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);

    // Listen for incoming text messages from the repeater
    _frameSubscription = connector.receivedFrames.listen((frame) {
      if (frame.isEmpty) return;

      // Check if it's a text message response
      if (frame[0] == pushCodeStatusResponse) {
        _handleStatusResponse(frame);
      } else if (frame[0] == respCodeContactMsgRecv ||
          frame[0] == respCodeContactMsgRecvV3) {
        _handleTextMessageResponse(frame);
      }
    });
  }

  void _handleTextMessageResponse(Uint8List frame) {
    final parsed = parseContactMessageText(frame);
    if (parsed == null) return;
    if (!_matchesRepeaterPrefix(parsed.senderPrefix)) return;

    // Notify command service of response (for retry handling)
    _commandService?.handleResponse(widget.repeater, parsed.text);

    // Parse status responses
    _parseStatusResponse(parsed.text);
  }

  void _handleStatusResponse(Uint8List frame) {
    if (frame.length < 8) return;
    final prefix = frame.sublist(2, 8);
    if (!_matchesRepeaterPrefix(prefix)) return;

    const payloadOffset = 8;
    const statsSize = 52;
    if (frame.length < payloadOffset + statsSize) return;

    final data = ByteData.sublistView(frame, payloadOffset, payloadOffset + statsSize);
    int offset = 0;

    final batteryMv = data.getUint16(offset, Endian.little);
    offset += 2;
    final queueLen = data.getUint16(offset, Endian.little);
    offset += 2;
    final noiseFloor = data.getInt16(offset, Endian.little);
    offset += 2;
    final lastRssi = data.getInt16(offset, Endian.little);
    offset += 2;
    final packetsRecv = data.getUint32(offset, Endian.little);
    offset += 4;
    final packetsSent = data.getUint32(offset, Endian.little);
    offset += 4;
    final txAirSecs = data.getUint32(offset, Endian.little);
    offset += 4;
    final uptimeSecs = data.getUint32(offset, Endian.little);
    offset += 4;
    final floodTx = data.getUint32(offset, Endian.little);
    offset += 4;
    final directTx = data.getUint32(offset, Endian.little);
    offset += 4;
    final floodRx = data.getUint32(offset, Endian.little);
    offset += 4;
    final directRx = data.getUint32(offset, Endian.little);
    offset += 4;
    final errEvents = data.getUint16(offset, Endian.little);
    offset += 2;
    final lastSnrRaw = data.getInt16(offset, Endian.little);
    offset += 2;
    final directDups = data.getUint16(offset, Endian.little);
    offset += 2;
    final floodDups = data.getUint16(offset, Endian.little);
    offset += 2;
    final rxAirSecs = data.getUint32(offset, Endian.little);

    _statusTimeout?.cancel();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _batteryMv = batteryMv;
      _queueLen = queueLen;
      _noiseFloor = noiseFloor;
      _lastRssi = lastRssi;
      _packetsRecv = packetsRecv;
      _packetsSent = packetsSent;
      _txAirSecs = txAirSecs;
      _rxAirSecs = rxAirSecs;
      _uptimeSecs = uptimeSecs;
      _floodTx = floodTx;
      _directTx = directTx;
      _floodRx = floodRx;
      _directRx = directRx;
      _debugFlags = errEvents;
      _lastSnr = lastSnrRaw / 4.0;
      _dupDirect = directDups;
      _dupFlood = floodDups;
    });
  }

  bool _matchesRepeaterPrefix(Uint8List prefix) {
    final target = widget.repeater.publicKey;
    if (target.length < 6 || prefix.length < 6) return false;
    for (int i = 0; i < 6; i++) {
      if (prefix[i] != target[i]) return false;
    }
    return true;
  }

  void _parseStatusResponse(String response) {
    final trimmed = response.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final data = jsonDecode(trimmed) as Map<String, dynamic>;
        if (data.containsKey('battery_mv')) {
          _batteryMv = _asInt(data['battery_mv']);
          _uptimeSecs = _asInt(data['uptime_secs']);
          _queueLen = _asInt(data['queue_len']);
          _debugFlags = _asInt(data['errors']);
        } else if (data.containsKey('noise_floor')) {
          _noiseFloor = _asInt(data['noise_floor']);
          _lastRssi = _asInt(data['last_rssi']);
          _lastSnr = _asDouble(data['last_snr']);
          _txAirSecs = _asInt(data['tx_air_secs']);
          _rxAirSecs = _asInt(data['rx_air_secs']);
        } else if (data.containsKey('recv') || data.containsKey('sent')) {
          _packetsRecv = _asInt(data['recv']);
          _packetsSent = _asInt(data['sent']);
          _floodTx = _asInt(data['flood_tx']);
          _directTx = _asInt(data['direct_tx']);
          _floodRx = _asInt(data['flood_rx']);
          _directRx = _asInt(data['direct_rx']);
          _dupFlood = _asInt(data['dup_flood']);
          _dupDirect = _asInt(data['dup_direct']);
        }
      } catch (_) {
        // Ignore parse failures for non-JSON responses.
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadStatus() async {
    if (_commandService == null) return;

    setState(() {
      _isLoading = true;
      _statusRequestedAt = DateTime.now();
      _batteryMv = null;
      _uptimeSecs = null;
      _queueLen = null;
      _debugFlags = null;
      _lastRssi = null;
      _lastSnr = null;
      _noiseFloor = null;
      _txAirSecs = null;
      _rxAirSecs = null;
      _packetsSent = null;
      _packetsRecv = null;
      _floodTx = null;
      _directTx = null;
      _floodRx = null;
      _directRx = null;
      _dupFlood = null;
      _dupDirect = null;
    });

    try {
      final connector = Provider.of<MeshCoreConnector>(context, listen: false);
      final frame = buildSendStatusRequestFrame(widget.repeater.publicKey);
      await connector.sendFrame(frame);

      _statusTimeout?.cancel();
      _statusTimeout = Timer(const Duration(seconds: 12), () {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status request timed out.'),
            backgroundColor: Colors.red,
          ),
        );
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Repeater Status'),
            Text(
              widget.repeater.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadStatus,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadStatus,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSystemInfoCard(),
              const SizedBox(height: 16),
              _buildRadioStatsCard(),
              const SizedBox(height: 16),
              _buildPacketStatsCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSystemInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                const Text(
                  'System Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow('Battery', _batteryText()),
            _buildInfoRow('Clock (at login)', _clockText()),
            _buildInfoRow('Uptime', _formatDuration(_uptimeSecs)),
            _buildInfoRow('Queue Length', _formatValue(_queueLen)),
            _buildInfoRow('Debug Flags', _formatValue(_debugFlags)),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.radio, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                const Text(
                  'Radio Statistics',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow('Last RSSI', _formatValue(_lastRssi, suffix: ' dB')),
            _buildInfoRow('Last SNR', _formatSnr(_lastSnr)),
            _buildInfoRow('Noise Floor', _formatValue(_noiseFloor, suffix: ' dB')),
            _buildInfoRow('TX Airtime', _formatDuration(_txAirSecs)),
            _buildInfoRow('RX Airtime', _formatDuration(_rxAirSecs)),
          ],
        ),
      ),
    );
  }

  Widget _buildPacketStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                const Text(
                  'Packet Statistics',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow('Sent', _packetTxText()),
            _buildInfoRow('Received', _packetRxText()),
            _buildInfoRow('Duplicates', _duplicateText()),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString());
  }

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  String _batteryText() {
    if (_batteryMv == null) return '—';
    final percent = _batteryPercentFromMv(_batteryMv!);
    final volts = (_batteryMv! / 1000.0).toStringAsFixed(2);
    return '$percent% / ${volts}V';
  }

  int _batteryPercentFromMv(int millivolts) {
    const minMv = 3000;
    const maxMv = 4200;
    if (millivolts <= minMv) return 0;
    if (millivolts >= maxMv) return 100;
    return (((millivolts - minMv) * 100) / (maxMv - minMv)).round();
  }

  String _clockText() {
    if (_statusRequestedAt == null) return '—';
    final dt = _statusRequestedAt!;
    final date = '${dt.day}/${dt.month}/${dt.year}';
    final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '—';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return '$days days ${hours}h ${minutes}m ${secs}s';
  }

  String _packetTxText() {
    if (_packetsSent == null) return '—';
    final flood = _formatValue(_floodTx);
    final direct = _formatValue(_directTx);
    return 'Total: $_packetsSent, Flood: $flood, Direct: $direct';
  }

  String _packetRxText() {
    if (_packetsRecv == null) return '—';
    final flood = _formatValue(_floodRx);
    final direct = _formatValue(_directRx);
    return 'Total: $_packetsRecv, Flood: $flood, Direct: $direct';
  }

  String _duplicateText() {
    if (_dupFlood != null || _dupDirect != null) {
      final flood = _formatValue(_dupFlood);
      final direct = _formatValue(_dupDirect);
      return 'Flood: $flood, Direct: $direct';
    }
    if (_packetsRecv == null || _floodRx == null || _directRx == null) return '—';
    final dupTotal = _packetsRecv! - _floodRx! - _directRx!;
    if (dupTotal < 0) return '—';
    return 'Total: $dupTotal';
  }

  String _formatValue(num? value, {String? suffix}) {
    if (value == null) return '—';
    return suffix == null ? value.toString() : '$value$suffix';
  }

  String _formatSnr(double? snr) {
    if (snr == null) return '—';
    return snr.toStringAsFixed(2);
  }
}
