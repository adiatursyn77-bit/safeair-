import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import 'qr_scanner_screen.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _deviceIdController = TextEditingController();
  final _secretController = TextEditingController();
  final _nameController = TextEditingController();
  final _firestoreService = FirestoreService();

  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _deviceIdController.dispose();
    _secretController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _scanQrCode() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );

    if (result == null || !mounted) return;

    try {
      final data = jsonDecode(result) as Map<String, dynamic>;
      final deviceId = data['deviceId'] as String?;
      final secret = data['secret'] as String?;
      final name = data['name'] as String?;

      if (deviceId == null || secret == null) {
        throw const FormatException('Нет deviceId или secret в QR-коде');
      }

      setState(() {
        _deviceIdController.text = deviceId;
        _secretController.text = secret;
        if (name != null && name.isNotEmpty) {
          _nameController.text = name;
        }
        _errorText = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('addDevice.qrRecognized'.tr())),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('addDevice.qrParseError'.tr())),
        );
      }
    }
  }

  Future<void> _handleAdd() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      await _firestoreService.addDevice(
        deviceId: _deviceIdController.text.trim(),
        secret: _secretController.text,
        name: _nameController.text.trim(),
        currentUid: uid,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _errorText = 'addDevice.addFailed'.tr(args: ['$e']);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('addDevice.title'.tr())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _scanQrCode,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: Text('addDevice.scanButton'.tr()),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                        child: Divider(
                            color:
                                Theme.of(context).colorScheme.outlineVariant)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'addDevice.orManual'.tr(),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline),
                      ),
                    ),
                    Expanded(
                        child: Divider(
                            color:
                                Theme.of(context).colorScheme.outlineVariant)),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _deviceIdController,
                  decoration: InputDecoration(
                    labelText: 'addDevice.deviceIdLabel'.tr(),
                    hintText: 'addDevice.deviceIdHint'.tr(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'addDevice.deviceIdRequired'.tr();
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _secretController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'addDevice.secretLabel'.tr(),
                  ),
                  validator: (value) {
                    if (value == null || value.length < 8) {
                      return 'addDevice.secretError'.tr();
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'addDevice.nameLabel'.tr(),
                    hintText: 'addDevice.nameHint'.tr(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'addDevice.nameRequired'.tr();
                    }
                    return null;
                  },
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorText!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isLoading ? null : _handleAdd,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('addDevice.addButton'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
