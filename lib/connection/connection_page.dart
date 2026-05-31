import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smart_wearables_app/connection/my_ble_manager.dart';
import 'package:smart_wearables_app/services/notification_service.dart';

// --- 1. Widget Definition ---
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key, required this.title});
  final String title;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

// --- 2. Widget's State Definition ---
class _ConnectionPageState extends State<ConnectionPage> {
  // A filter to only show BLE devices having "BLE_SW" as name
  final String bleDeviceNameFilter = "BLE_SW_Team_B8";

  final flutterReactiveBle = FlutterReactiveBle();

  late StreamSubscription<DiscoveredDevice> scanStream;
  List<DiscoveredDevice> foundBleDevices = []; // All found devices
  List<DiscoveredDevice> foundBleDevicesFiltered = []; // Only the ones matching the filter

  bool permGranted = false;
  bool scanning = false;

  void refreshScreen() {
    setState(() {});
  }

  // --- Permission Handling ---

  // Shows a dialog if permissions are not granted
  Future<void> _showNoPermissionDialog() async => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Permissions Missing'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('You have not granted the required permissions.'),
                Text(
                    'Location and Bluetooth permissions are mandatory for BLE to work.'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Acknowledge'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      );

  // Asks the user for all required permissions
  void _askPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
      Permission.bluetoothConnect
    ].request();

    // Check if ALL permissions were granted
    if (statuses[Permission.bluetoothScan] == PermissionStatus.granted &&
        statuses[Permission.bluetoothConnect] == PermissionStatus.granted &&
        statuses[Permission.locationWhenInUse] == PermissionStatus.granted) {

      // Richiedi permessi per le notifiche (Android 13+)
      await NotificationService().requestPermissions();

      permGranted = true;
      if (!scanning) {
        _startScan();
      }
    } else {
      permGranted = false;
    }
  }

  // --- Scan Logic ---

  // Stops the BLE scan
  void _stopScan() async {
    await scanStream.cancel();
    scanning = false;
    refreshScreen();
  }

  // Starts the BLE scan
  void _startScan() async {
    if (scanning) {
      _stopScan();
    }

    if (permGranted) {
      foundBleDevices = [];
      foundBleDevicesFiltered = [];
      scanning = true;
      refreshScreen();

      scanStream = flutterReactiveBle
          .scanForDevices(withServices: [])
          .listen((device) {
        if (foundBleDevices.every((element) => element.id != device.id)) {
          foundBleDevices.add(device);
          if (device.name.contains(bleDeviceNameFilter)) {
            foundBleDevicesFiltered.add(device);
          }
          refreshScreen();
        }
      }, onError: (Object error) {
        debugPrint("ERROR during scan: $error \n");
        refreshScreen();
      });

      Future.delayed(
        const Duration(seconds: 10),
        () {
          if (scanning) {
            _stopScan();
          }
        },
      );
    } else {
      await _showNoPermissionDialog();
    }
  }

  // --- Connection Logic ---

  void _startConnection(int index) {
    if (scanning) {
      _stopScan();
    }
    // Avvia la connessione tramite il Singleton centralizzato
    MyBleManager().connect(foundBleDevicesFiltered[index].id);
  }

  void _onConnectionChanged() {
    if (MyBleManager().isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Connessione stabilita con successo!"),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context); // Ritorna alla HomePage
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _askPermissions();
    
    // Registra un listener sul singleton per tornare alla home alla connessione avvenuta
    MyBleManager().isConnectedNotifier.addListener(_onConnectionChanged);
  }

  @override
  void dispose() {
    MyBleManager().isConnectedNotifier.removeListener(_onConnectionChanged);
    if (scanning) {
      scanStream.cancel();
    }
    super.dispose();
  }

  // --- UI Building ---
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MyBleManager().isConnectingNotifier,
      builder: (context, isConnecting, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: MyBleManager().isConnectedNotifier,
          builder: (context, isConnected, child) {
            return Stack(
              children: [
                Scaffold(
                  appBar: AppBar(
                    backgroundColor: Theme.of(context).colorScheme.inversePrimary,
                    title: Text(widget.title),
                  ),
                  body: RefreshIndicator(
                    onRefresh: () async {
                      _startScan();
                    },
                    child: foundBleDevicesFiltered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  scanning
                                      ? "Ricerca in corso per '$bleDeviceNameFilter'..."
                                      : "Scansione terminata. Trascina per aggiornare.",
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: foundBleDevicesFiltered.length,
                            itemBuilder: (context, index) {
                              final device = foundBleDevicesFiltered[index];
                              final isThisDeviceConnected = isConnected &&
                                  MyBleManager().connectedDeviceId == device.id;
                              
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  dense: true,
                                  onTap: () {
                                    if (!isConnecting) {
                                      if (isThisDeviceConnected) {
                                        MyBleManager().disconnect();
                                      } else {
                                        _startConnection(index);
                                      }
                                    }
                                  },
                                  subtitle: Text(
                                    device.id,
                                    style: const TextStyle(fontFamily: 'monospace'),
                                  ),
                                  title: Text(
                                    device.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  trailing: isThisDeviceConnected
                                      ? const Icon(Icons.check_circle, color: Colors.green, size: 24)
                                      : const Icon(Icons.chevron_right, color: Colors.black38),
                                ),
                              );
                            },
                          ),
                  ),
                ),

                // --- Loading Overlay ---
                if (isConnecting)
                  const Opacity(
                    opacity: 0.4,
                    child: ModalBarrier(dismissible: false, color: Colors.black),
                  ),
                if (isConnecting)
                  const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text(
                              "Connessione in corso...",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}