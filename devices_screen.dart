import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/duration_format.dart';
import 'add_device_screen.dart';
import 'device_detail_screen.dart';
import 'settings_screen.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    // См. пояснение в device_detail_screen.dart — без этого таймера
    // статус "офлайн" и lastSeen не обновятся сами по себе без новых
    // данных из Firestore.
    _tickTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  Color _statusColor(BuildContext context, DeviceDisplayStatus status) {
    switch (status) {
      case DeviceDisplayStatus.alarm:
        return Colors.red;
      case DeviceDisplayStatus.ok:
        return Theme.of(context).colorScheme.primary;
      case DeviceDisplayStatus.offline:
        return Theme.of(context).colorScheme.outline;
    }
  }

  String _statusLabel(DeviceDisplayStatus status) {
    switch (status) {
      case DeviceDisplayStatus.alarm:
        return 'devices.statusAlarm'.tr();
      case DeviceDisplayStatus.ok:
        return 'devices.statusOk'.tr();
      case DeviceDisplayStatus.offline:
        return 'devices.statusOffline'.tr();
    }
  }

  IconData _statusIcon(DeviceDisplayStatus status) {
    switch (status) {
      case DeviceDisplayStatus.alarm:
        return Icons.warning_rounded;
      case DeviceDisplayStatus.ok:
        return Icons.check_circle_rounded;
      case DeviceDisplayStatus.offline:
        return Icons.cloud_off_rounded;
    }
  }

  String _lastSeenLabel(BuildContext context, Device device) {
    final lang = context.locale.languageCode;
    if (device.lastSeenAt == null) return 'lastSeen.never'.tr();

    final diff = DateTime.now().difference(device.lastSeenAt!);

    if (diff.inSeconds < 10) return 'lastSeen.justNow'.tr();
    if (diff.inSeconds < 60) {
      final p = relativeTimeParts(lang, diff, 'seconds');
      return 'lastSeen.secondsAgo'.tr(args: ['${p.value}', p.unit]);
    }
    if (diff.inMinutes < 60) {
      final p = relativeTimeParts(lang, diff, 'minutes');
      return 'lastSeen.minutesAgo'.tr(args: ['${p.value}', p.unit]);
    }
    if (diff.inHours < 24) {
      final p = relativeTimeParts(lang, diff, 'hours');
      return 'lastSeen.hoursAgo'.tr(args: ['${p.value}', p.unit]);
    }
    final p = relativeTimeParts(lang, diff, 'days');
    return 'lastSeen.daysAgo'.tr(args: ['${p.value}', p.unit]);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final firestoreService = FirestoreService();
    final authService = AuthService();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('devices.title'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => authService.signOut(),
          ),
        ],
      ),
      body: uid == null
          ? const SizedBox.shrink()
          : StreamBuilder<List<Device>>(
              stream: firestoreService.streamDevicesForUser(uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child:
                        Text('devices.error'.tr(args: ['${snapshot.error}'])),
                  );
                }

                final devices = snapshot.data ?? [];
                if (devices.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.sensors_rounded,
                            size: 56,
                            color: colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'devices.emptyTitle'.tr(),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'devices.emptyHint'.tr(),
                            style: TextStyle(color: colorScheme.outline),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final status = device.displayStatus;
                    final statusColor = _statusColor(context, status);

                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  DeviceDetailScreen(device: device),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.local_fire_department_rounded,
                                  color: statusColor,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      device.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          _statusIcon(status),
                                          size: 16,
                                          color: statusColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _statusLabel(status),
                                          style: TextStyle(
                                            color: statusColor,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _lastSeenLabel(context, device),
                                      style: TextStyle(
                                        color: colorScheme.outline,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: colorScheme.outline,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddDeviceScreen()),
          );
        },
        icon: const Icon(Icons.add_rounded),
        label: Text('devices.addDeviceButton'.tr()),
      ),
    );
  }
}
