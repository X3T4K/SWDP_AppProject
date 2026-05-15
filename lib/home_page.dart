import 'dart:async';
import 'package:flutter/material.dart';
import 'package:smart_wearables_app/connection/stream.dart';
import 'package:smart_wearables_app/connection/my_ble_manager.dart';
import 'package:smart_wearables_app/connection/messages.dart';
import 'package:smart_wearables_app/connection/connection_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});
  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription? _dataSubscription;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _setupStreamListener();
  }

  void _setupStreamListener() {
    final stream = MyBleManager().stream;
    if (stream != null) {
      _dataSubscription?.cancel();
      _dataSubscription = stream.controller.stream.listen((data) {
        _parsePacket(data);
      });
    }
  }

  void _parsePacket(List<int> packet) {
    // I dati IMU non verranno usati in produzione come richiesto.
    // In futuro qui gestiremo i dati di luce, suono e stress.
    try {
      // final data = SensorData.fromBytes(packet);
      // Logica futura qui
    } catch (e) {
      debugPrint('Errore nel parsing del pacchetto: $e');
    }
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      const LucePage(),
      const SuonoPage(),
      const StressMelatoninaPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.bluetooth),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ConnectionPage(title: "Connect Device"),
              ),
            );
            // Al ritorno dalla pagina di connessione, aggiorniamo il listener se lo stream è stato creato
            _setupStreamListener();
          },
          tooltip: 'Connetti Bluetooth',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: _sendAck,
            tooltip: 'Inizia Trasferimento',
          ),
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.wb_sunny_outlined),
            activeIcon: Icon(Icons.wb_sunny),
            label: 'Luce',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.volume_up_outlined),
            activeIcon: Icon(Icons.volume_up),
            label: 'Suono',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.spa_outlined),
            activeIcon: Icon(Icons.spa),
            label: 'Stress',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: _onItemTapped,
      ),
    );
  }

  void _sendAck() {
    final ack = AckMessage();
    MyBleManager().sendMessage(ack);
  }
}

class LucePage extends StatelessWidget {
  const LucePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wb_sunny, size: 80, color: Color(0xFF005BFF)),
          SizedBox(height: 20),
          Text(
            'Luce',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'Monitoraggio dell\'esposizione luminosa.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class SuonoPage extends StatelessWidget {
  const SuonoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.volume_up, size: 80, color: Color(0xFF06F3FF)),
          SizedBox(height: 20),
          Text(
            'Suono',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'Analisi dei livelli sonori ambientali.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class StressMelatoninaPage extends StatelessWidget {
  const StressMelatoninaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.spa, size: 80, color: Color(0xFF005BFF)),
          SizedBox(height: 20),
          Text(
            'Stress e Melatonina',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'Valutazione dello stress e dei livelli di melatonina.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
