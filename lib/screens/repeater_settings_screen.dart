import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../services/repeater_command_service.dart';

class RepeaterSettingsScreen extends StatefulWidget {
  final Contact repeater;
  final String password;

  const RepeaterSettingsScreen({
    super.key,
    required this.repeater,
    required this.password,
  });

  @override
  State<RepeaterSettingsScreen> createState() => _RepeaterSettingsScreenState();
}

class _RepeaterSettingsScreenState extends State<RepeaterSettingsScreen> {
  bool _isLoading = false;
  bool _hasChanges = false;
  bool _refreshingBasic = false;
  bool _refreshingRadio = false;
  bool _refreshingLocation = false;
  bool _refreshingFeatures = false;
  bool _refreshingAdvertisement = false;
  StreamSubscription<Uint8List>? _frameSubscription;
  RepeaterCommandService? _commandService;
  final Map<String, String> _fetchedSettings = {};

  // Basic settings
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _guestPasswordController = TextEditingController();

  // Radio settings
  final TextEditingController _freqController = TextEditingController();
  final TextEditingController _txPowerController = TextEditingController();
  int _bandwidth = 125000;
  int _spreadingFactor = 9;
  int _codingRate = 7;

  // Location settings
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lonController = TextEditingController();

  // Feature toggles
  bool _repeatEnabled = true;
  bool _allowReadOnly = false;
  bool _privacyMode = false;

  // Advertisement settings
  int _advertInterval = 120; // minutes/2
  int _floodAdvertInterval = 12; // hours
  int _privAdvertInterval = 60; // minutes

  final List<int> _bandwidthOptions = [
    7800,
    10400,
    15600,
    20800,
    31250,
    41700,
    62500,
    125000,
    250000,
    500000,
  ];
  final List<int> _spreadingFactorOptions = [5, 6, 7, 8, 9, 10, 11, 12];
  final List<int> _codingRateOptions = [5, 6, 7, 8];

  @override
  void initState() {
    super.initState();
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    _commandService = RepeaterCommandService(connector);
    _setupMessageListener();
    _loadSettings();
  }

  @override
  void dispose() {
    _frameSubscription?.cancel();
    _commandService?.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _guestPasswordController.dispose();
    _freqController.dispose();
    _txPowerController.dispose();
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  void _setupMessageListener() {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);

    // Listen for incoming text messages from the repeater
    _frameSubscription = connector.receivedFrames.listen((frame) {
      if (frame.isEmpty) return;

      // Check if it's a text message response
      if (frame[0] == respCodeContactMsgRecv ||
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
  }

  bool _matchesRepeaterPrefix(Uint8List prefix) {
    final target = widget.repeater.publicKey;
    if (target.length < 6 || prefix.length < 6) return false;
    for (int i = 0; i < 6; i++) {
      if (prefix[i] != target[i]) return false;
    }
    return true;
  }

  void _updateUIFromFetchedSettings() {
    if (_fetchedSettings.isEmpty) return;

    setState(() {
      // Update name
      if (_fetchedSettings.containsKey('name')) {
        _nameController.text = _fetchedSettings['name']!;
      }

      // Update radio settings - parse "915.00,250.00,9,7" or unit-labeled variants
      if (_fetchedSettings.containsKey('radio')) {
        final radioStr = _fetchedSettings['radio']!;
        final parts = radioStr.split(',');
        final parsed = <String>[];
        for (final part in parts) {
          final trimmed = part.trim();
          if (trimmed.isNotEmpty) {
            parsed.add(trimmed);
          }
        }
        if (parsed.isNotEmpty) {
          final freqText = parsed.first
              .replaceAll('MHz', '')
              .replaceAll('mhz', '')
              .trim();
          if (freqText.isNotEmpty) {
            _freqController.text = freqText;
          }
        }
        if (parsed.length > 1) {
          final bwText = parsed[1]
              .replaceAll('kHz', '')
              .replaceAll('khz', '')
              .trim();
          final bw = double.tryParse(bwText);
          if (bw != null) {
            _bandwidth = (bw * 1000).toInt();
            if (!_bandwidthOptions.contains(_bandwidth)) {
              _bandwidthOptions.add(_bandwidth);
              _bandwidthOptions.sort();
            }
          }
        }
        if (parsed.length > 2) {
          final sfText = parsed[2].replaceAll('SF', '').replaceAll('sf', '').trim();
          _spreadingFactor = int.tryParse(sfText) ?? _spreadingFactor;
        }
        if (parsed.length > 3) {
          final crText = parsed[3].replaceAll('CR', '').replaceAll('cr', '').trim();
          _codingRate = int.tryParse(crText) ?? _codingRate;
        }
      }

      if (_fetchedSettings.containsKey('tx')) {
        _txPowerController.text = _fetchedSettings['tx']!;
      }

      if (_fetchedSettings.containsKey('lat')) {
        _latController.text = _fetchedSettings['lat']!;
      }
      if (_fetchedSettings.containsKey('lon')) {
        _lonController.text = _fetchedSettings['lon']!;
      }

      if (_fetchedSettings.containsKey('repeat')) {
        _repeatEnabled = _normalizeOnOff(_fetchedSettings['repeat']!);
      }
      if (_fetchedSettings.containsKey('allow.read.only')) {
        _allowReadOnly = _normalizeOnOff(_fetchedSettings['allow.read.only']!);
      }
      if (_fetchedSettings.containsKey('privacy')) {
        _privacyMode = _normalizeOnOff(_fetchedSettings['privacy']!);
      }

      if (_fetchedSettings.containsKey('advert.interval')) {
        _advertInterval = _parseIntWithFallback(
          _fetchedSettings['advert.interval']!,
          _advertInterval,
        );
      }
      if (_fetchedSettings.containsKey('flood.advert.interval')) {
        _floodAdvertInterval = _parseIntWithFallback(
          _fetchedSettings['flood.advert.interval']!,
          _floodAdvertInterval,
        );
      }
      if (_fetchedSettings.containsKey('priv.advert.interval')) {
        _privAdvertInterval = _parseIntWithFallback(
          _fetchedSettings['priv.advert.interval']!,
          _privAdvertInterval,
        );
      }
    });
  }

  bool _isAnySectionRefreshing() {
    return _refreshingBasic ||
        _refreshingRadio ||
        _refreshingLocation ||
        _refreshingFeatures ||
        _refreshingAdvertisement;
  }

  bool _normalizeOnOff(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'on' ||
        normalized == 'true' ||
        normalized == '1' ||
        normalized == 'enabled';
  }

  int _parseIntWithFallback(String value, int fallback) {
    final parsed = int.tryParse(value.replaceAll(RegExp(r'[^0-9-]'), ''));
    return parsed ?? fallback;
  }

  String _formatBandwidthLabel(int bandwidthHz) {
    final bandwidthKHz = bandwidthHz / 1000;
    var text = bandwidthKHz.toStringAsFixed(2);
    text = text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return '$text kHz';
  }

  void _applySettingResponse(String command, String response) {
    final value = _extractCliValue(response);
    if (value == null) return;

    final normalized = command.trim().toLowerCase();
    if (!normalized.startsWith('get ')) return;
    final key = normalized.substring(4);

    switch (key) {
      case 'name':
      case 'radio':
      case 'tx':
      case 'lat':
      case 'lon':
      case 'repeat':
      case 'allow.read.only':
      case 'privacy':
      case 'advert.interval':
      case 'flood.advert.interval':
      case 'priv.advert.interval':
        _fetchedSettings[key] = value;
        break;
    }
  }

  String? _extractCliValue(String response) {
    final lines = response.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('>')) {
        final value = trimmed.substring(1).trim();
        if (value.isNotEmpty) return value;
      }
      final colonIndex = trimmed.indexOf(':');
      if (colonIndex > 0) {
        final value = trimmed.substring(colonIndex + 1).trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  Future<void> _refreshSection({
    required String label,
    required List<String> commands,
    required ValueSetter<bool> setRefreshing,
  }) async {
    if (_commandService == null) return;

    setState(() {
      setRefreshing(true);
      _fetchedSettings.clear();
    });

    var successCount = 0;
    for (final command in commands) {
      try {
        final response = await _commandService!.sendCommand(widget.repeater, command);
        _applySettingResponse(command, response);
        successCount += 1;
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        debugPrint('Error fetching $command: $e');
      }
    }

    if (mounted) {
      if (successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label refreshed'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing $label'),
            backgroundColor: Colors.red,
          ),
        );
      }

      if (_fetchedSettings.isNotEmpty) {
        _updateUIFromFetchedSettings();
      }
      setState(() {
        setRefreshing(false);
      });
    }
  }

  Future<void> _refreshBasicSettings() async {
    await _refreshSection(
      label: 'Basic settings',
      commands: const ['get name'],
      setRefreshing: (value) => _refreshingBasic = value,
    );
  }

  Future<void> _refreshRadioSettings() async {
    await _refreshSection(
      label: 'Radio settings',
      commands: const ['get radio', 'get tx'],
      setRefreshing: (value) => _refreshingRadio = value,
    );
  }

  Future<void> _refreshLocationSettings() async {
    await _refreshSection(
      label: 'Location settings',
      commands: const ['get lat', 'get lon'],
      setRefreshing: (value) => _refreshingLocation = value,
    );
  }

  Future<void> _refreshFeatureSettings() async {
    await _refreshSection(
      label: 'Feature toggles',
      commands: const ['get repeat', 'get allow.read.only', 'get privacy'],
      setRefreshing: (value) => _refreshingFeatures = value,
    );
  }

  Future<void> _refreshAdvertisementSettings() async {
    await _refreshSection(
      label: 'Advertisement settings',
      commands: const [
        'get advert.interval',
        'get flood.advert.interval',
        'get priv.advert.interval',
      ],
      setRefreshing: (value) => _refreshingAdvertisement = value,
    );
  }

  Future<void> _loadSettings() async {
    // Just populate with current repeater data on initial load
    // User must click sync button to fetch from device
    setState(() {
      _nameController.text = widget.repeater.name;

      if (widget.repeater.hasLocation) {
        _latController.text = widget.repeater.latitude?.toString() ?? '';
        _lonController.text = widget.repeater.longitude?.toString() ?? '';
      }
    });
  }

  Future<void> _saveSettings() async {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);

    setState(() {
      _isLoading = true;
    });

    try {
      final commands = <String>[];

      // Build set commands for each setting
      if (_nameController.text.isNotEmpty) {
        commands.add('set name ${_nameController.text}');
      }

      if (_passwordController.text.isNotEmpty) {
        commands.add('password ${_passwordController.text}');
      }

      if (_guestPasswordController.text.isNotEmpty) {
        commands.add('set guest.password ${_guestPasswordController.text}');
      }

      // Radio parameters
      final freqMHz = double.tryParse(_freqController.text) ?? 915.0;
      final bwKHz = _bandwidth / 1000;
      commands.add('set radio ${freqMHz.toStringAsFixed(1)} $bwKHz $_spreadingFactor $_codingRate');

      // Location
      if (_latController.text.isNotEmpty) {
        commands.add('set lat ${_latController.text}');
      }
      if (_lonController.text.isNotEmpty) {
        commands.add('set lon ${_lonController.text}');
      }

      // Feature toggles
      commands.add('set repeat ${_repeatEnabled ? "on" : "off"}');
      commands.add('set allow.read.only ${_allowReadOnly ? "on" : "off"}');
      commands.add('set privacy ${_privacyMode ? "on" : "off"}');

      // Advertisement intervals
      commands.add('set advert.interval $_advertInterval');
      commands.add('set flood.advert.interval $_floodAdvertInterval');
      if (_privacyMode) {
        commands.add('set priv.advert.interval $_privAdvertInterval');
      }

      // Send all commands
      for (final command in commands) {
        final frame = buildSendCliCommandFrame(widget.repeater.publicKey, command);
        await connector.sendFrame(frame);
        await Future.delayed(const Duration(milliseconds: 200)); // Delay between commands
      }

      setState(() {
        _isLoading = false;
        _hasChanges = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _markChanged() {
    if (!_hasChanges) {
      setState(() {
        _hasChanges = true;
      });
    }
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required bool isRefreshing,
    required VoidCallback onRefresh,
  }) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).primaryColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        IconButton(
          icon: isRefreshing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          onPressed: isRefreshing ? null : onRefresh,
          tooltip: 'Refresh $title',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Repeater Settings'),
            Text(
              widget.repeater.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          if (_hasChanges)
            TextButton.icon(
              onPressed: _isLoading ? null : _saveSettings,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _isLoading && _nameController.text.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildBasicSettingsCard(),
                  const SizedBox(height: 16),
                  _buildRadioSettingsCard(),
                  const SizedBox(height: 16),
                  _buildLocationSettingsCard(),
                  const SizedBox(height: 16),
                  _buildFeatureTogglesCard(),
                  const SizedBox(height: 16),
                  _buildAdvertisementSettingsCard(),
                  const SizedBox(height: 32),
                  _buildDangerZoneCard(),
                ],
              ),
      ),
    );
  }

  Widget _buildBasicSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.settings,
              title: 'Basic Settings',
              isRefreshing: _refreshingBasic,
              onRefresh: _refreshBasicSettings,
            ),
            const Divider(),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Repeater Name',
                helperText: 'Display name for this repeater',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _markChanged(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Admin Password',
                helperText: 'Full access password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              onChanged: (_) => _markChanged(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _guestPasswordController,
              decoration: const InputDecoration(
                labelText: 'Guest Password',
                helperText: 'Read-only access password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              onChanged: (_) => _markChanged(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.radio,
              title: 'Radio Settings',
              isRefreshing: _refreshingRadio,
              onRefresh: _refreshRadioSettings,
            ),
            const Divider(),
            TextField(
              controller: _freqController,
              decoration: const InputDecoration(
                labelText: 'Frequency (MHz)',
                helperText: '300-2500 MHz',
                border: OutlineInputBorder(),
                suffixText: 'MHz',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _markChanged(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _txPowerController,
              decoration: const InputDecoration(
                labelText: 'TX Power',
                helperText: '1-30 dBm',
                border: OutlineInputBorder(),
                suffixText: 'dBm',
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => _markChanged(),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _bandwidth,
              decoration: const InputDecoration(
                labelText: 'Bandwidth',
                border: OutlineInputBorder(),
              ),
              items: _bandwidthOptions.map((bw) {
                return DropdownMenuItem(
                  value: bw,
                  child: Text(_formatBandwidthLabel(bw)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _bandwidth = value;
                  });
                  _markChanged();
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _spreadingFactor,
              decoration: const InputDecoration(
                labelText: 'Spreading Factor',
                border: OutlineInputBorder(),
              ),
              items: _spreadingFactorOptions.map((sf) {
                return DropdownMenuItem(
                  value: sf,
                  child: Text('SF$sf'),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _spreadingFactor = value;
                  });
                  _markChanged();
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _codingRate,
              decoration: const InputDecoration(
                labelText: 'Coding Rate',
                border: OutlineInputBorder(),
              ),
              items: _codingRateOptions.map((cr) {
                return DropdownMenuItem(
                  value: cr,
                  child: Text('4/$cr'),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _codingRate = value;
                  });
                  _markChanged();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.location_on,
              title: 'Location Settings',
              isRefreshing: _refreshingLocation,
              onRefresh: _refreshLocationSettings,
            ),
            const Divider(),
            TextField(
              controller: _latController,
              decoration: const InputDecoration(
                labelText: 'Latitude',
                helperText: 'Decimal degrees (e.g., 37.7749)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              onChanged: (_) => _markChanged(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _lonController,
              decoration: const InputDecoration(
                labelText: 'Longitude',
                helperText: 'Decimal degrees (e.g., -122.4194)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              onChanged: (_) => _markChanged(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureTogglesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.toggle_on,
              title: 'Features',
              isRefreshing: _refreshingFeatures,
              onRefresh: _refreshFeatureSettings,
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Packet Forwarding'),
              subtitle: const Text('Enable repeater to forward packets'),
              value: _repeatEnabled,
              onChanged: (value) {
                setState(() {
                  _repeatEnabled = value;
                });
                _markChanged();
              },
            ),
            SwitchListTile(
              title: const Text('Guest Access'),
              subtitle: const Text('Allow read-only guest access'),
              value: _allowReadOnly,
              onChanged: (value) {
                setState(() {
                  _allowReadOnly = value;
                });
                _markChanged();
              },
            ),
            SwitchListTile(
              title: const Text('Privacy Mode'),
              subtitle: const Text('Hide name/location in advertisements'),
              value: _privacyMode,
              onChanged: (value) {
                setState(() {
                  _privacyMode = value;
                });
                _markChanged();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvertisementSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.broadcast_on_personal,
              title: 'Advertisement Settings',
              isRefreshing: _refreshingAdvertisement,
              onRefresh: _refreshAdvertisementSettings,
            ),
            const Divider(),
            ListTile(
              title: const Text('Local Advertisement Interval'),
              subtitle: Text('$_advertInterval minutes'),
              trailing: Text('${_advertInterval}m'),
            ),
            Slider(
              value: _advertInterval.toDouble(),
              min: 60,
              max: 240,
              divisions: 18,
              label: '${_advertInterval}m',
              onChanged: (value) {
                setState(() {
                  _advertInterval = value.toInt();
                });
                _markChanged();
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Flood Advertisement Interval'),
              subtitle: Text('$_floodAdvertInterval hours'),
              trailing: Text('${_floodAdvertInterval}h'),
            ),
            Slider(
              value: _floodAdvertInterval.toDouble(),
              min: 3,
              max: 48,
              divisions: 45,
              label: '${_floodAdvertInterval}h',
              onChanged: (value) {
                setState(() {
                  _floodAdvertInterval = value.toInt();
                });
                _markChanged();
              },
            ),
            if (_privacyMode) ...[
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Encrypted Advertisement Interval'),
                subtitle: Text('$_privAdvertInterval minutes'),
                trailing: Text('${_privAdvertInterval}m'),
              ),
              Slider(
                value: _privAdvertInterval.toDouble(),
                min: 30,
                max: 240,
                divisions: 21,
                label: '${_privAdvertInterval}m',
                onChanged: (value) {
                  setState(() {
                    _privAdvertInterval = value.toInt();
                  });
                  _markChanged();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDangerZoneCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Text(
                  'Danger Zone',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.refresh, color: colorScheme.onErrorContainer),
              title: Text('Reboot Repeater', style: TextStyle(color: colorScheme.onErrorContainer)),
              subtitle: Text(
                'Restart the repeater device',
                style: TextStyle(color: colorScheme.onErrorContainer.withValues(alpha: 0.8)),
              ),
              onTap: () => _confirmAction(
                'Reboot Repeater',
                'Are you sure you want to reboot this repeater?',
                () => _sendDangerCommand('reboot'),
              ),
            ),
            ListTile(
              leading: Icon(Icons.vpn_key, color: colorScheme.onErrorContainer),
              title: Text('Regenerate Identity Key', style: TextStyle(color: colorScheme.onErrorContainer)),
              subtitle: Text(
                'Generate new public/private key pair',
                style: TextStyle(color: colorScheme.onErrorContainer.withValues(alpha: 0.8)),
              ),
              onTap: () => _confirmAction(
                'Regenerate Identity',
                'This will generate a new identity for the repeater. Continue?',
                () => _sendDangerCommand('regen key'),
              ),
            ),
            ListTile(
              leading: Icon(Icons.delete_forever, color: colorScheme.onErrorContainer),
              title: Text('Erase File System', style: TextStyle(color: colorScheme.onErrorContainer)),
              subtitle: Text(
                'Format the repeater file system',
                style: TextStyle(color: colorScheme.onErrorContainer.withValues(alpha: 0.8)),
              ),
              onTap: () => _confirmAction(
                'Erase File System',
                'WARNING: This will erase all data on the repeater. This cannot be undone!',
                () => _sendDangerCommand('erase'),
                isDestructive: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendDangerCommand(String command) async {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);

    if (command == 'erase') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erase is only available over serial console.')),
        );
      }
      return;
    }

    try {
      final frame = buildSendCliCommandFrame(widget.repeater.publicKey, command);
      await connector.sendFrame(frame);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Command sent: $command')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending command: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _confirmAction(
    String title,
    String message,
    VoidCallback onConfirm, {
    bool isDestructive = false,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            style: isDestructive
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}
