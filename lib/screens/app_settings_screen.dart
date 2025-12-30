import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../services/app_settings_service.dart';
import '../services/notification_service.dart';
import 'map_cache_screen.dart';

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Settings'),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Consumer2<AppSettingsService, MeshCoreConnector>(
          builder: (context, settingsService, connector, child) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildAppearanceCard(context, settingsService),
                const SizedBox(height: 16),
                _buildNotificationsCard(context, settingsService),
                const SizedBox(height: 16),
                _buildMessagingCard(context, settingsService),
                const SizedBox(height: 16),
                _buildBatteryCard(context, settingsService, connector),
                const SizedBox(height: 16),
                _buildMapSettingsCard(context, settingsService),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppearanceCard(BuildContext context, AppSettingsService settingsService) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Appearance',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme'),
            subtitle: Text(_themeModeLabel(settingsService.settings.themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showThemeModeDialog(context, settingsService),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsCard(BuildContext context, AppSettingsService settingsService) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Notifications',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Enable Notifications'),
            subtitle: const Text('Receive notifications for messages and adverts'),
            value: settingsService.settings.notificationsEnabled,
            onChanged: (value) async {
              if (value) {
                // Request permission when enabling
                final granted = await NotificationService().requestPermissions();
                if (!granted) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Notification permission denied'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                  return;
                }
              }

              await settingsService.setNotificationsEnabled(value);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(value
                        ? 'Notifications enabled'
                        : 'Notifications disabled'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: Icon(
              Icons.message_outlined,
              color: settingsService.settings.notificationsEnabled ? null : Colors.grey,
            ),
            title: Text(
              'Message Notifications',
              style: TextStyle(
                color: settingsService.settings.notificationsEnabled ? null : Colors.grey,
              ),
            ),
            subtitle: Text(
              'Show notification when receiving new messages',
              style: TextStyle(
                color: settingsService.settings.notificationsEnabled ? null : Colors.grey,
              ),
            ),
            value: settingsService.settings.notifyOnNewMessage,
            onChanged: settingsService.settings.notificationsEnabled
                ? (value) {
                    settingsService.setNotifyOnNewMessage(value);
                  }
                : null,
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: Icon(
              Icons.forum_outlined,
              color: settingsService.settings.notificationsEnabled ? null : Colors.grey,
            ),
            title: Text(
              'Channel Message Notifications',
              style: TextStyle(
                color: settingsService.settings.notificationsEnabled ? null : Colors.grey,
              ),
            ),
            subtitle: Text(
              'Show notification when receiving channel messages',
              style: TextStyle(
                color: settingsService.settings.notificationsEnabled ? null : Colors.grey,
              ),
            ),
            value: settingsService.settings.notifyOnNewChannelMessage,
            onChanged: settingsService.settings.notificationsEnabled
                ? (value) {
                    settingsService.setNotifyOnNewChannelMessage(value);
                  }
                : null,
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: Icon(
              Icons.cell_tower,
              color: settingsService.settings.notificationsEnabled ? null : Colors.grey,
            ),
            title: Text(
              'Advertisement Notifications',
              style: TextStyle(
                color: settingsService.settings.notificationsEnabled ? null : Colors.grey,
              ),
            ),
            subtitle: Text(
              'Show notification when new nodes are discovered',
              style: TextStyle(
                color: settingsService.settings.notificationsEnabled ? null : Colors.grey,
              ),
            ),
            value: settingsService.settings.notifyOnNewAdvert,
            onChanged: settingsService.settings.notificationsEnabled
                ? (value) {
                    settingsService.setNotifyOnNewAdvert(value);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildMessagingCard(BuildContext context, AppSettingsService settingsService) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Messaging',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.refresh_outlined),
            title: const Text('Clear Path on Max Retry'),
            subtitle: const Text('Reset contact path after 5 failed send attempts'),
            value: settingsService.settings.clearPathOnMaxRetry,
            onChanged: (value) {
              settingsService.setClearPathOnMaxRetry(value);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(value
                      ? 'Paths will be cleared after 5 failed retries'
                      : 'Paths will not be auto-cleared'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.alt_route),
            title: const Text('Auto Route Rotation'),
            subtitle: const Text('Cycle between best paths and flood mode'),
            value: settingsService.settings.autoRouteRotationEnabled,
            onChanged: (value) {
              settingsService.setAutoRouteRotationEnabled(value);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(value
                      ? 'Auto route rotation enabled'
                      : 'Auto route rotation disabled'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMapSettingsCard(BuildContext context, AppSettingsService settingsService) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Map Display',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.router_outlined),
            title: const Text('Show Repeaters'),
            subtitle: const Text('Display repeater nodes on the map'),
            value: settingsService.settings.mapShowRepeaters,
            onChanged: (value) {
              settingsService.setMapShowRepeaters(value);
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.chat_outlined),
            title: const Text('Show Chat Nodes'),
            subtitle: const Text('Display chat nodes on the map'),
            value: settingsService.settings.mapShowChatNodes,
            onChanged: (value) {
              settingsService.setMapShowChatNodes(value);
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.people_outline),
            title: const Text('Show Other Nodes'),
            subtitle: const Text('Display other node types on the map'),
            value: settingsService.settings.mapShowOtherNodes,
            onChanged: (value) {
              settingsService.setMapShowOtherNodes(value);
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Time Filter'),
            subtitle: Text(
              settingsService.settings.mapTimeFilterHours == 0
                  ? 'Show all nodes'
                  : 'Show nodes from last ${settingsService.settings.mapTimeFilterHours.toInt()} hours',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showTimeFilterDialog(context, settingsService),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Offline Map Cache'),
            subtitle: Text(
              settingsService.settings.mapCacheBounds == null
                  ? 'No area selected'
                  : 'Area selected (zoom ${settingsService.settings.mapCacheMinZoom}'
                      '-${settingsService.settings.mapCacheMaxZoom})',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MapCacheScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryCard(
    BuildContext context,
    AppSettingsService settingsService,
    MeshCoreConnector connector,
  ) {
    final deviceId = connector.deviceId;
    final isConnected = connector.isConnected && deviceId != null;
    final selection =
        isConnected ? settingsService.batteryChemistryForDevice(deviceId) : 'nmc';

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Battery',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.battery_full),
            title: const Text('Battery Chemistry'),
            subtitle: Text(
              isConnected
                  ? 'Set per device (${connector.deviceDisplayName})'
                  : 'Connect to a device to choose',
            ),
            trailing: DropdownButton<String>(
              value: selection,
              onChanged: isConnected
                  ? (value) {
                      if (value != null) {
                        settingsService.setBatteryChemistryForDevice(deviceId, value);
                      }
                    }
                  : null,
              items: const [
                DropdownMenuItem(
                  value: 'nmc',
                  child: Text('18650 NMC (3.0-4.2V)'),
                ),
                DropdownMenuItem(
                  value: 'lifepo4',
                  child: Text('LiFePO4 (2.6-3.65V)'),
                ),
                DropdownMenuItem(
                  value: 'lipo',
                  child: Text('LiPo (3.0-4.2V)'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showThemeModeDialog(BuildContext context, AppSettingsService settingsService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('System default'),
              value: 'system',
              groupValue: settingsService.settings.themeMode,
              onChanged: (value) {
                if (value != null) {
                  settingsService.setThemeMode(value);
                  Navigator.pop(context);
                }
              },
            ),
            RadioListTile<String>(
              title: const Text('Light'),
              value: 'light',
              groupValue: settingsService.settings.themeMode,
              onChanged: (value) {
                if (value != null) {
                  settingsService.setThemeMode(value);
                  Navigator.pop(context);
                }
              },
            ),
            RadioListTile<String>(
              title: const Text('Dark'),
              value: 'dark',
              groupValue: settingsService.settings.themeMode,
              onChanged: (value) {
                if (value != null) {
                  settingsService.setThemeMode(value);
                  Navigator.pop(context);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _themeModeLabel(String value) {
    switch (value) {
      case 'light':
        return 'Light';
      case 'dark':
        return 'Dark';
      default:
        return 'System default';
    }
  }

  void _showTimeFilterDialog(BuildContext context, AppSettingsService settingsService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Map Time Filter'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Show nodes discovered within:'),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('All time'),
              leading: Radio<double>(
                value: 0,
                groupValue: settingsService.settings.mapTimeFilterHours,
                onChanged: (value) {
                  if (value != null) {
                    settingsService.setMapTimeFilterHours(value);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            ListTile(
              title: const Text('Last hour'),
              leading: Radio<double>(
                value: 1,
                groupValue: settingsService.settings.mapTimeFilterHours,
                onChanged: (value) {
                  if (value != null) {
                    settingsService.setMapTimeFilterHours(value);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            ListTile(
              title: const Text('Last 6 hours'),
              leading: Radio<double>(
                value: 6,
                groupValue: settingsService.settings.mapTimeFilterHours,
                onChanged: (value) {
                  if (value != null) {
                    settingsService.setMapTimeFilterHours(value);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            ListTile(
              title: const Text('Last 24 hours'),
              leading: Radio<double>(
                value: 24,
                groupValue: settingsService.settings.mapTimeFilterHours,
                onChanged: (value) {
                  if (value != null) {
                    settingsService.setMapTimeFilterHours(value);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            ListTile(
              title: const Text('Last week'),
              leading: Radio<double>(
                value: 168,
                groupValue: settingsService.settings.mapTimeFilterHours,
                onChanged: (value) {
                  if (value != null) {
                    settingsService.setMapTimeFilterHours(value);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
