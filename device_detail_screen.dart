import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/device.dart';
import '../models/leak_event.dart';
import '../services/firestore_service.dart';
import '../utils/duration_format.dart';
import 'device_stats_screen.dart';

class DeviceDetailScreen extends StatefulWidget {
  final Device device;

  const DeviceDetailScreen({super.key, required this.device});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  final _firestoreService = FirestoreService();
  final _dateFormat = DateFormat('dd.MM.yyyy HH:mm');
  Timer? _tickTimer;
  StreamSubscription<Device?>? _deviceSub;
  late Device _device;

  @override
  void initState() {
    super.initState();
    _device = widget.device;

    // Живое обновление платы: показания датчиков, статус, lastSeenAt.
    _deviceSub = _firestoreService.streamDevice(widget.device.id).listen(
      (d) {
        if (d != null && mounted) setState(() => _device = d);
      },
      onError: (_) {},
    );

    // Раз в 5 сек перерисовываем, чтобы "Была на связи N сек назад"
    // и переход в offline обновлялись, даже если данные не менялись.
    _tickTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _deviceSub?.cancel();
    super.dispose();
  }

  Widget _sensorTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: colorScheme.outline, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorsCard(DeviceDisplayStatus status) {
    final colorScheme = Theme.of(context).colorScheme;
    final offline = status == DeviceDisplayStatus.offline;

    String fmt(double? v, int digits, String suffix) {
      if (v == null || offline) return '—';
      return '${v.toStringAsFixed(digits)}$suffix';
    }

    final gasColor = status == DeviceDisplayStatus.alarm
        ? Colors.red
        : colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Row(
            children: [
              _sensorTile(
                icon: Icons.thermostat_rounded,
                label: 'deviceDetail.temperature'.tr(),
                value: fmt(_device.lastTemp, 1, ' °C'),
                color: Colors.orange,
              ),
              _sensorTile(
                icon: Icons.water_drop_rounded,
                label: 'deviceDetail.humidity'.tr(),
                value: fmt(_device.lastHum, 0, ' %'),
                color: Colors.blue,
              ),
              _sensorTile(
                icon: Icons.air_rounded,
                label: 'deviceDetail.gasLevel'.tr(),
                value: fmt(_device.lastGas, 0, ''),
                color: gasColor,
              ),
            ],
          ),
        ),
      ),
    );
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

  String _lastSeenLabel(BuildContext context) {
    final lang = context.locale.languageCode;
    final lastSeenAt = _device.lastSeenAt;
    if (lastSeenAt == null) return 'lastSeen.never'.tr();

    final diff = DateTime.now().difference(lastSeenAt);

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

  Future<void> _showRenameDialog() async {
    final controller = TextEditingController(text: _device.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text('deviceDetail.renameDialogTitle'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('deviceDetail.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text('deviceDetail.save'.tr()),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await _firestoreService.renameDevice(_device.id, newName);
    }
  }

  Future<void> _showDeleteConfirmation() async {
    final isLastMember = _device.memberUids.length <= 1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          isLastMember
              ? 'deviceDetail.deleteDialogTitleLast'.tr()
              : 'deviceDetail.deleteDialogTitleLeave'.tr(),
        ),
        content: Text(
          isLastMember
              ? 'deviceDetail.deleteDialogBodyLast'.tr()
              : 'deviceDetail.deleteDialogBodyLeave'
                  .tr(args: [_device.name]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('deviceDetail.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              isLastMember
                  ? 'deviceDetail.deleteActionLast'.tr()
                  : 'deviceDetail.deleteActionLeave'.tr(),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _firestoreService.leaveDevice(
          _device.id,
          uid,
          isLastMember: isLastMember,
        );
      }
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = _device.displayStatus;
    final statusColor = _statusColor(context, status);
    final lang = context.locale.languageCode;

    return Scaffold(
      appBar: AppBar(
        title: Text(_device.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DeviceStatsScreen(
                    deviceId: _device.id,
                    deviceName: _device.name,
                  ),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') _showRenameDialog();
              if (value == 'delete') _showDeleteConfirmation();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'rename',
                child: Text('deviceDetail.renameAction'.tr()),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  _device.memberUids.length <= 1
                      ? 'deviceDetail.deleteActionLast'.tr()
                      : 'deviceDetail.deleteActionLeave'.tr(),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.local_fire_department_rounded,
                        color: statusColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _statusLabel(status),
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _lastSeenLabel(context),
                            style: TextStyle(color: colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildSensorsCard(status),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                Text(
                  'deviceDetail.history'.tr(),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<LeakEvent>>(
              stream: _firestoreService.streamEvents(_device.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                        'deviceDetail.error'.tr(args: ['${snapshot.error}'])),
                  );
                }

                final events = snapshot.data ?? [];
                if (events.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 48,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'deviceDetail.noEvents'.tr(),
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final event = events[index];
                    final eventColor =
                        event.isActive ? Colors.red : colorScheme.primary;

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: eventColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                event.isActive
                                    ? Icons.warning_amber_rounded
                                    : Icons.check_circle_rounded,
                                color: eventColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _dateFormat.format(event.startedAt),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    event.isActive
                                        ? 'deviceDetail.activeAlarm'.tr()
                                        : 'deviceDetail.resolvedIn'.tr(args: [
                                            event.durationSec == null
                                                ? '—'
                                                : formatShortDuration(
                                                    lang,
                                                    event.durationSec!,
                                                  ),
                                          ]),
                                    style: TextStyle(
                                      color: colorScheme.outline,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
