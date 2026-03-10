import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:logging/logging.dart' as dartlog;
import 'package:provider/provider.dart';

import '../inclinometer_data.dart';

class ProbeScreen extends StatefulWidget {
  const ProbeScreen({super.key});

  @override
  State<ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<ProbeScreen> {
  static const String _targetAdapterName = 'BlueDriver';
  static const List<String> _blueDriverNameHints = [
    'BLUEDRIVER',
    'BLUE DRIVER',
  ];
  static const List<String> _quickCommands = [
    '010C', // RPM
    '010D', // Vehicle speed
    '0105', // Coolant temp
    '0111', // Throttle position
    '03', // Stored DTCs
    '04', // Clear DTCs
  ];
  static const List<String> _blueDriverInitSequence = [
    'ATZ',
    'ATE0',
    'ATL0',
    'ATS0',
    'ATH0',
    'ATSP0',
  ];

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final dartlog.Logger _logger = dartlog.Logger('Probe');
  final TextEditingController _commandController = TextEditingController(
    text: '010C',
  );

  late InclinometerData _dataModel;
  final Map<String, DiscoveredDevice> _seenDevices = {};

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;

  bool _scanning = false;
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  String? _connectedDeviceId;
  QualifiedCharacteristic? _txCharacteristic;
  bool _txRequiresResponse = false;
  QualifiedCharacteristic? _rxCharacteristic;
  int _mtu = 23; // Default BLE MTU prior to negotiation.
  bool _showLikelyBlueDriverOnly = false;
  bool _busyWriting = false;

  @override
  void initState() {
    super.initState();
    _dataModel = context.read<InclinometerData>();
  }

  @override
  void dispose() {
    _commandController.dispose();
    unawaited(_stopScan());
    unawaited(_disconnect());
    super.dispose();
  }

  bool _isLikelyBlueDriverName(String name) {
    final upper = name.toUpperCase();
    return _blueDriverNameHints.any(upper.contains);
  }

  Future<void> _startScan() async {
    await _stopScan();
    setState(() {
      _seenDevices.clear();
      _scanning = true;
    });
    _dataModel.addLogEntry(
      _showLikelyBlueDriverOnly
          ? 'Scanning for likely $_targetAdapterName BLE adapters…'
          : 'Scanning for nearby BLE OBD adapters…',
    );

    _scanSub = _ble
        .scanForDevices(withServices: const [], scanMode: ScanMode.lowLatency)
        .listen(
          (device) {
            final name = device.name.trim();
            if (name.isEmpty) return;
            final likelyBlueDriver = _isLikelyBlueDriverName(name);
            if (_showLikelyBlueDriverOnly && !likelyBlueDriver) return;

            final isNew = !_seenDevices.containsKey(device.id);
            _seenDevices[device.id] = device;

            if (isNew) {
              _dataModel.addLogEntry(
                'Found $name (${device.id}) RSSI ${device.rssi}${likelyBlueDriver ? ' [$_targetAdapterName candidate]' : ''}',
              );
            }
            if (mounted) {
              setState(() {});
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            _logger.severe('Scan failed', error, stackTrace);
            _dataModel.addLogEntry('Scan error: $error');
            _stopScan();
          },
        );
  }

  Future<void> _stopScan() async {
    final wasScanning = _scanning;
    await _scanSub?.cancel();
    _scanSub = null;
    if (_scanning && mounted) {
      setState(() {
        _scanning = false;
      });
    } else {
      _scanning = false;
    }
    if (wasScanning) {
      _dataModel.addLogEntry('Scan stopped');
    }
  }

  Future<void> _connect(DiscoveredDevice device) async {
    await _stopScan();
    await _disconnect();

    final deviceName = device.name.trim();
    final likelyBlueDriver = _isLikelyBlueDriverName(deviceName);
    _dataModel.addLogEntry(
      'Connecting to $deviceName (${device.id})${likelyBlueDriver ? ' [$_targetAdapterName candidate]' : ''}…',
    );
    setState(() {
      _connectionState = DeviceConnectionState.connecting;
      _connectedDeviceId = device.id;
    });

    _connectionSub = _ble
        .connectToDevice(
          id: device.id,
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
          (update) {
            _logger.info('Connection update: $update');
            if (!mounted) return;
            setState(() {
              _connectionState = update.connectionState;
            });
            switch (update.connectionState) {
              case DeviceConnectionState.connected:
                _onConnected(device.id);
                break;
              case DeviceConnectionState.disconnected:
                if (_connectedDeviceId != null) {
                  _dataModel.addLogEntry('Disconnected from ${device.name}');
                }
                _connectedDeviceId = null;
                _txCharacteristic = null;
                _rxCharacteristic = null;
                _txRequiresResponse = false;
                break;
              default:
                break;
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            _logger.severe('Connection failed', error, stackTrace);
            _dataModel.addLogEntry('Connection error: $error');
            if (!mounted) return;
            setState(() {
              _connectionState = DeviceConnectionState.disconnected;
              _connectedDeviceId = null;
            });
          },
        );
  }

  Future<void> _onConnected(String deviceId) async {
    _dataModel.addLogEntry('Connected — discovering services…');

    try {
      // Request a larger MTU when possible to reduce fragmentation.
      final mtu = await _ble.requestMtu(deviceId: deviceId, mtu: 185);
      _mtu = mtu;
      _dataModel.addLogEntry('Negotiated MTU: $mtu');
    } catch (error) {
      _logger.warning('MTU negotiation failed: $error');
    }

    try {
      await _ble.discoverAllServices(deviceId);
      final services = await _ble.getDiscoveredServices(deviceId);
      _resolveCharacteristics(deviceId, services);

      for (final service in services) {
        final characteristicIds = service.characteristics
            .map((c) => c.id.toString())
            .join(', ');
        _dataModel.addLogEntry(
          'Service ${service.id}: chars [$characteristicIds]',
        );
      }

      if (_rxCharacteristic != null) {
        _subscribeToNotifications();
      } else {
        _dataModel.addLogEntry(
          'Warning: No notify characteristic found — live updates disabled',
        );
      }

      if (_txCharacteristic != null) {
        _dataModel.addLogEntry('Ready to send OBD-II commands.');
        _dataModel.addLogEntry(
          _txRequiresResponse
              ? 'TX mode: write with response'
              : 'TX mode: write without response',
        );
      } else {
        _dataModel.addLogEntry(
          'Warning: No writable characteristic found — cannot send commands',
        );
      }

      final connectedName = _seenDevices[deviceId]?.name.trim();
      if (connectedName != null && _isLikelyBlueDriverName(connectedName)) {
        _dataModel.addLogEntry(
          'Tip: run INIT to prepare $_targetAdapterName for clean PID replies.',
        );
      }
    } catch (error, stackTrace) {
      _logger.severe('Service discovery failed', error, stackTrace);
      _dataModel.addLogEntry('Service discovery error: $error');
    }
  }

  void _resolveCharacteristics(String deviceId, List<Service> services) {
    QualifiedCharacteristic? tx;
    bool txRequiresResponse = false;
    QualifiedCharacteristic? rx;

    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (tx == null) {
          if (characteristic.isWritableWithoutResponse) {
            tx = QualifiedCharacteristic(
              deviceId: deviceId,
              serviceId: service.id,
              characteristicId: characteristic.id,
            );
            txRequiresResponse = false;
          } else if (characteristic.isWritableWithResponse) {
            tx = QualifiedCharacteristic(
              deviceId: deviceId,
              serviceId: service.id,
              characteristicId: characteristic.id,
            );
            txRequiresResponse = true;
          }
        }
        if (rx == null &&
            (characteristic.isNotifiable || characteristic.isIndicatable)) {
          rx = QualifiedCharacteristic(
            deviceId: deviceId,
            serviceId: service.id,
            characteristicId: characteristic.id,
          );
        }
      }
    }

    setState(() {
      _txCharacteristic = tx;
      _txRequiresResponse = txRequiresResponse;
      _rxCharacteristic = rx;
    });
  }

  Future<void> _subscribeToNotifications() async {
    await _notifySub?.cancel();
    final characteristic = _rxCharacteristic;
    if (characteristic == null) {
      return;
    }

    _notifySub = _ble
        .subscribeToCharacteristic(characteristic)
        .listen(
          (event) {
            final asciiPayload = ascii.decode(event, allowInvalid: true).trim();
            final hexPayload = event
                .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
                .join(' ');
            _dataModel.addLogEntry(' ⇒ $asciiPayload ($hexPayload)');
          },
          onError: (Object error, StackTrace stackTrace) {
            _logger.severe('Notification stream error', error, stackTrace);
            _dataModel.addLogEntry('Notification stream error: $error');
          },
        );
  }

  Future<void> _disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;

    if (!mounted) {
      return;
    }

    setState(() {
      _connectionState = DeviceConnectionState.disconnected;
      _connectedDeviceId = null;
      _txCharacteristic = null;
      _rxCharacteristic = null;
      _txRequiresResponse = false;
      _busyWriting = false;
    });
  }

  Future<void> _sendCommandText(String commandText) async {
    final characteristic = _txCharacteristic;
    if (characteristic == null) {
      _dataModel.addLogEntry(
        'Cannot send command: TX characteristic unavailable',
      );
      return;
    }

    final normalizedCommand = commandText.trim().toUpperCase();
    if (normalizedCommand.isEmpty) {
      _dataModel.addLogEntry('Enter an OBD-II command before sending.');
      return;
    }

    final payload = ascii.encode('$normalizedCommand\r');
    _dataModel.addLogEntry('⇒ $normalizedCommand');

    try {
      if (_txRequiresResponse) {
        await _ble.writeCharacteristicWithResponse(
          characteristic,
          value: payload,
        );
      } else {
        await _ble.writeCharacteristicWithoutResponse(
          characteristic,
          value: payload,
        );
      }
    } catch (error, stackTrace) {
      _logger.severe('Write failed', error, stackTrace);
      _dataModel.addLogEntry('Write error: $error');
    }
  }

  Future<void> _sendCommand() async {
    await _sendCommandText(_commandController.text);
  }

  Future<void> _runBlueDriverInitSequence() async {
    if (_connectionState != DeviceConnectionState.connected) {
      _dataModel.addLogEntry(
        'Connect to $_targetAdapterName before running INIT.',
      );
      return;
    }
    if (_busyWriting) {
      return;
    }

    setState(() {
      _busyWriting = true;
    });
    _dataModel.addLogEntry(
      'Running $_targetAdapterName init sequence (${_blueDriverInitSequence.length} commands)…',
    );

    try {
      for (final command in _blueDriverInitSequence) {
        await _sendCommandText(command);
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
      _dataModel.addLogEntry('$_targetAdapterName init sequence completed.');
    } finally {
      if (mounted) {
        setState(() {
          _busyWriting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BlueDriver Probe'),
        actions: [
          IconButton(
            icon: Icon(_scanning ? Icons.stop : Icons.bluetooth_searching),
            tooltip: _scanning ? 'Stop scan' : 'Start scan',
            onPressed: _scanning ? _stopScan : _startScan,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear log',
            onPressed: () => _dataModel.clearActivityLog(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildConnectionPanel(),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                children: [
                  Expanded(flex: 3, child: _buildDeviceList()),
                  const SizedBox(width: 12),
                  Expanded(flex: 4, child: _buildActivityLog()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionPanel() {
    final connected = _connectionState == DeviceConnectionState.connected;
    final device = _connectedDeviceId != null
        ? _seenDevices[_connectedDeviceId!]
        : null;
    final connectedName = device?.name.trim() ?? '';
    final likelyBlueDriver = _isLikelyBlueDriverName(connectedName);

    return Card(
      color: Colors.black.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connection ($_targetAdapterName / BLE OBD)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text(_describeConnectionState(_connectionState))),
                if (device != null)
                  Chip(
                    avatar: const Icon(Icons.bluetooth, size: 16),
                    label: Text(device.name),
                  ),
                if (connected && likelyBlueDriver)
                  const Chip(
                    avatar: Icon(Icons.verified, size: 16),
                    label: Text('BlueDriver likely'),
                  ),
                Chip(label: Text('MTU $_mtu bytes')),
                if (connected)
                  ElevatedButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Disconnect'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    enabled: connected && !_busyWriting,
                    decoration: const InputDecoration(
                      labelText: 'OBD-II command (e.g. 010C, ATZ)',
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendCommand(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: connected && !_busyWriting ? _sendCommand : null,
                  child: const Text('SEND'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: connected && !_busyWriting
                      ? _runBlueDriverInitSequence
                      : null,
                  child: const Text('INIT'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickCommands
                  .map(
                    (command) => OutlinedButton(
                      onPressed: connected && !_busyWriting
                          ? () {
                              _commandController.text = command;
                              unawaited(_sendCommandText(command));
                            }
                          : null,
                      child: Text(command),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList() {
    final devices = _seenDevices.values.toList()
      ..sort((a, b) {
        final aLikely = _isLikelyBlueDriverName(a.name.trim());
        final bLikely = _isLikelyBlueDriverName(b.name.trim());
        if (aLikely != bLikely) {
          return bLikely ? 1 : -1;
        }
        return b.rssi.compareTo(a.rssi);
      });

    return Card(
      color: Colors.black.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Nearby BLE OBD adapters'),
                const Spacer(),
                FilterChip(
                  label: const Text('BlueDriver only'),
                  selected: _showLikelyBlueDriverOnly,
                  onSelected: (selected) {
                    setState(() {
                      _showLikelyBlueDriverOnly = selected;
                    });
                    if (_scanning) {
                      unawaited(_startScan());
                    }
                  },
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: _startScan,
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: devices.isEmpty
                  ? const Center(
                      child: Text('No BLE OBD adapters detected yet.'),
                    )
                  : ListView.separated(
                      itemCount: devices.length,
                      separatorBuilder: (context, _) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        final likelyBlueDriver = _isLikelyBlueDriverName(
                          device.name.trim(),
                        );
                        final isConnected =
                            device.id == _connectedDeviceId &&
                            _connectionState == DeviceConnectionState.connected;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            likelyBlueDriver ? Icons.verified : Icons.bluetooth,
                            size: 18,
                          ),
                          title: Text(device.name),
                          subtitle: Text(device.id),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${device.rssi} dBm'),
                              const SizedBox(height: 4),
                              ElevatedButton(
                                onPressed: isConnected
                                    ? null
                                    : () => _connect(device),
                                child: Text(
                                  isConnected ? 'CONNECTED' : 'CONNECT',
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityLog() {
    return Card(
      color: Colors.black.withValues(alpha: 0.2),
      child: Consumer<InclinometerData>(
        builder: (context, data, _) {
          final entries = data.activityLog.reversed.toList();
          if (entries.isEmpty) {
            return const Center(child: Text('Activity log is empty.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            separatorBuilder: (context, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                dense: true,
                title: Text(entry.message),
                subtitle: Text(entry.timestamp.toIso8601String()),
              );
            },
          );
        },
      ),
    );
  }

  String _describeConnectionState(DeviceConnectionState state) {
    switch (state) {
      case DeviceConnectionState.connecting:
        return 'Connecting';
      case DeviceConnectionState.connected:
        return 'Connected';
      case DeviceConnectionState.disconnecting:
        return 'Disconnecting';
      case DeviceConnectionState.disconnected:
        return 'Disconnected';
    }
  }
}
