import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../widgets/device_tile.dart';
import 'contacts_screen.dart';

/// Screen for scanning and connecting to MeshCore devices
class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MeshCore Open'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        top: false,
        child: Consumer<MeshCoreConnector>(
          builder: (context, connector, child) {
            return Column(
              children: [
                // Status bar
                _buildStatusBar(context, connector),

                // Device list
                Expanded(
                  child: _buildDeviceList(context, connector),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: Consumer<MeshCoreConnector>(
        builder: (context, connector, child) {
          final isScanning = connector.state == MeshCoreConnectionState.scanning;
          
          return FloatingActionButton.extended(
            onPressed: () {
              if (isScanning) {
                connector.stopScan();
              } else {
                connector.startScan();
              }
            },
            icon: isScanning 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.bluetooth_searching),
            label: Text(isScanning ? 'Stop' : 'Scan'),
          );
        },
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context, MeshCoreConnector connector) {
    String statusText;
    Color statusColor;

    switch (connector.state) {
      case MeshCoreConnectionState.scanning:
        statusText = 'Scanning for devices...';
        statusColor = Colors.blue;
        break;
      case MeshCoreConnectionState.connecting:
        statusText = 'Connecting...';
        statusColor = Colors.orange;
        break;
      case MeshCoreConnectionState.connected:
        statusText = 'Connected to ${connector.deviceDisplayName}';
        statusColor = Colors.green;
        break;
      case MeshCoreConnectionState.disconnecting:
        statusText = 'Disconnecting...';
        statusColor = Colors.orange;
        break;
      case MeshCoreConnectionState.disconnected:
        statusText = 'Not connected';
        statusColor = Colors.grey;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: statusColor.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(Icons.circle, size: 12, color: statusColor),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(color: statusColor, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(BuildContext context, MeshCoreConnector connector) {
    if (connector.scanResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              connector.state == MeshCoreConnectionState.scanning
                  ? 'Searching for MeshCore devices...'
                  : 'Tap Scan to find MeshCore devices',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: connector.scanResults.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final result = connector.scanResults[index];
        return DeviceTile(
          scanResult: result,
          onTap: () => _connectToDevice(context, connector, result),
        );
      },
    );
  }

  Future<void> _connectToDevice(
    BuildContext context,
    MeshCoreConnector connector,
    ScanResult result,
  ) async {
    try {
      final name = result.device.platformName.isNotEmpty
          ? result.device.platformName
          : result.advertisementData.advName;
      await connector.connect(result.device, displayName: name);
      
      if (context.mounted && connector.isConnected) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ContactsScreen(),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
