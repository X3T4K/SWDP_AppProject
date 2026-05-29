import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:smart_wearables_app/connection/my_ble_manager.dart';
import 'package:smart_wearables_app/connection/connection_page.dart';
import 'package:smart_wearables_app/services/storage_service.dart';
import 'package:smart_wearables_app/services/data_parsing.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});
  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  StreamSubscription? _dumpSubscription;

  // Dati locali caricati da CSV
  List<Map<String, dynamic>> _spectrometerData = [];
  List<Map<String, dynamic>> _microphoneData = [];
  DateTime? _lastSpectrometerUpdate;
  DateTime? _lastMicrophoneUpdate;

  bool _isDownloadingDump = false;
  String _selectedPeriod = 'All'; // '1h', '6h', '24h', 'All'

  @override
  void initState() {
    super.initState();
    _loadLocalData();

    // Ascolta il completamento del download per aggiornare i grafici
    _dumpSubscription = MyBleManager().onDumpCompleted.listen((dumpType) {
      developer.log("Notifica dump completato ricevuta in HomePage per: $dumpType", name: 'HomePage');
      _loadLocalData();
      setState(() {
        _isDownloadingDump = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                "Dati ${dumpType == DumpType.spectrometer ? 'Spettrometro' : 'Microfono'} aggiornati!",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          backgroundColor: Colors.teal.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    });
  }

  @override
  void dispose() {
    _dumpSubscription?.cancel();
    super.dispose();
  }

  // Carica i dati salvati nei file CSV
  Future<void> _loadLocalData() async {
    final spec = await StorageService().getSpectrometerData();
    final mic = await StorageService().getMicrophoneData();
    final specTime = await StorageService().getLastUpdateTime('spectrometer_data.csv');
    final micTime = await StorageService().getLastUpdateTime('microphone_data.csv');

    setState(() {
      _spectrometerData = spec;
      _microphoneData = mic;
      _lastSpectrometerUpdate = specTime;
      _lastMicrophoneUpdate = micTime;
    });
  }

  // Avvia il download dei dati via BLE
  void _triggerDownload(DumpType type) {
    if (!MyBleManager().isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Devi essere connesso alla scheda per scaricare i dati!"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() {
      _isDownloadingDump = true;
    });
    if (type == DumpType.spectrometer) {
      MyBleManager().startSpectrometerDump();
    } else {
      MyBleManager().startMicrophoneDump();
    }
  }

  // Filtra i dati in base al periodo selezionato
  List<Map<String, dynamic>> _filterData(List<Map<String, dynamic>> rawData) {
    if (_selectedPeriod == 'All') return rawData;

    final cutoff = DateTime.now().subtract(
      _selectedPeriod == '1h' ? const Duration(hours: 1) :
      _selectedPeriod == '6h' ? const Duration(hours: 6) :
      const Duration(hours: 24)
    );

    return rawData.where((d) {
      final ts = d['timestamp'] as DateTime;
      return ts.isAfter(cutoff);
    }).toList();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = MyBleManager().isConnected;

    // Filtra i dati per i grafici
    final filteredSpecData = _filterData(_spectrometerData);
    final filteredMicData = _filterData(_microphoneData);

    final List<Widget> pages = [
      LucePage(
        data: filteredSpecData,
        lastUpdate: _lastSpectrometerUpdate,
        onDownload: () => _triggerDownload(DumpType.spectrometer),
      ),
      SuonoPage(
        data: filteredMicData,
        lastUpdate: _lastMicrophoneUpdate,
        onDownload: () => _triggerDownload(DumpType.microphone),
      ),
      StressMelatoninaPage(
        latestSpec: _spectrometerData.isNotEmpty ? _spectrometerData.last : null,
        latestMic: _microphoneData.isNotEmpty ? _microphoneData.last : null,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        elevation: 0,
        backgroundColor: const Color(0xFF005BFF),
        leading: IconButton(
          icon: Icon(
            isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            color: isConnected ? const Color(0xFF06F3FF) : Colors.white60,
            size: 28,
          ),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ConnectionPage(title: "Connetti Dispositivo"),
              ),
            );
            _loadLocalData(); // Ricarica dati al ritorno
          },
          tooltip: 'Connessione Bluetooth',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadLocalData,
            tooltip: 'Ricarica dati locali',
          ),
          if (isConnected)
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.white70),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Cancella tutti i dati?"),
                    content: const Text("Tutte le misurazioni salvate localmente verranno rimosse permanentemente."),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annulla")),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Cancella")),
                    ],
                  ),
                );
                if (confirm == true) {
                  await StorageService().clearAllData();
                  _loadLocalData();
                }
              },
              tooltip: 'Elimina tutti i dati',
            ),
        ],
      ),
      body: Column(
        children: [
          // 1. Banner di Stato Connessione (Se non connesso)
          if (!isConnected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.shade800, Colors.amber.shade700],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "Dispositivo non connesso",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white24,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.bluetooth, size: 16),
                    label: const Text("Connetti", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ConnectionPage(title: "Connetti Dispositivo"),
                        ),
                      );
                      _loadLocalData();
                    },
                  ),
                ],
              ),
            ),

          // 2. Banner di Stato Download attivo
          if (_isDownloadingDump)
            Container(
              color: Colors.teal.shade500,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    "Scaricamento dei dati in corso... Attendi completamento",
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

          // 3. Selettore Periodo di Tempo (Visibile solo se ci sono dati nelle prime due schede)
          if (_selectedIndex < 2 && (_spectrometerData.isNotEmpty || _microphoneData.isNotEmpty))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Periodo Grafico:",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                      ),
                      Row(
                        children: [
                          _buildPeriodButton('1h', '1 Ora'),
                          const SizedBox(width: 4),
                          _buildPeriodButton('6h', '6 Ore'),
                          const SizedBox(width: 4),
                          _buildPeriodButton('24h', '24 Ore'),
                          const SizedBox(width: 4),
                          _buildPeriodButton('All', 'Tutti'),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),

          // 4. Pagina principale
          Expanded(child: pages[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              spreadRadius: 2,
            )
          ],
        ),
        child: BottomNavigationBar(
          elevation: 0,
          backgroundColor: Colors.white,
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.wb_sunny_outlined),
              activeIcon: Icon(Icons.wb_sunny, color: Color(0xFF005BFF)),
              label: 'Luce',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.volume_up_outlined),
              activeIcon: Icon(Icons.volume_up, color: Color(0xFF005BFF)),
              label: 'Suono',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.spa_outlined),
              activeIcon: Icon(Icons.spa, color: Color(0xFF005BFF)),
              label: 'Salute & Sonno',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: const Color(0xFF005BFF),
          unselectedItemColor: Colors.black54,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          onTap: _onItemTapped,
        ),
      ),
    );
  }

  Widget _buildPeriodButton(String periodCode, String label) {
    final isSelected = _selectedPeriod == periodCode;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedPeriod = periodCode;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF005BFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black54,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// ==========================================
// PAGINA LUCE (SPETTROMETRO)
// ==========================================
class LucePage extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final DateTime? lastUpdate;
  final VoidCallback onDownload;

  const LucePage({
    super.key,
    required this.data,
    required this.lastUpdate,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final isDataEmpty = data.isEmpty;
    final isOld = lastUpdate != null &&
        DateTime.now().difference(lastUpdate!).inHours >= 2;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avviso Aggiornamento Dati
          _buildFreshnessWarning(isDataEmpty, isOld),

          if (isDataEmpty)
            _buildEmptyStateCard("Nessun dato luce rilevato", "Scarica i dati spettrometro dal dispositivo wearable per visualizzare l'esposizione luminosa.")
          else ...[
            // Ultimo valore misurato
            _buildLatestValueSection(),
            const SizedBox(height: 16),

            // Grafico SfCartesianChart
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Andamento Esposizione Luce",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 300,
                      child: SfCartesianChart(
                        legend: const Legend(isVisible: true, position: LegendPosition.bottom),
                        tooltipBehavior: TooltipBehavior(enable: true),
                        primaryXAxis: DateTimeAxis(
                          dateFormat: null,
                          intervalType: DateTimeIntervalType.auto,
                          majorGridLines: const MajorGridLines(width: 0),
                        ),
                        primaryYAxis: const NumericAxis(
                          title: AxisTitle(text: 'Intensità (lux)'),
                          majorGridLines: MajorGridLines(width: 1, color: Color(0xFFF1F1F1)),
                        ),
                        series: <CartesianSeries>[
                          // Linea Luce Artificiale (Rosso)
                          SplineAreaSeries<Map<String, dynamic>, DateTime>(
                            name: 'Luce Art.',
                            dataSource: data,
                            xValueMapper: (d, _) => d['timestamp'] as DateTime,
                            yValueMapper: (d, _) => d['luceArtificiale'] as num,
                            color: Colors.amber.withOpacity(0.1),
                            borderColor: Colors.amber.shade800,
                            borderWidth: 2.5,
                            splineType: SplineType.cardinal,
                          ),
                          // Linea Luce Blu (Azzurro)
                          SplineAreaSeries<Map<String, dynamic>, DateTime>(
                            name: 'Luce Blu',
                            dataSource: data,
                            xValueMapper: (d, _) => d['timestamp'] as DateTime,
                            yValueMapper: (d, _) => d['blue'] as num,
                            color: Colors.blue.withOpacity(0.1),
                            borderColor: Colors.blue.shade700,
                            borderWidth: 2.5,
                            splineType: SplineType.cardinal,
                          ),
                          // Linea Deep Blue (Indaco)
                          SplineAreaSeries<Map<String, dynamic>, DateTime>(
                            name: 'Deep Blue',
                            dataSource: data,
                            xValueMapper: (d, _) => d['timestamp'] as DateTime,
                            yValueMapper: (d, _) => d['deepBlue'] as num,
                            color: Colors.indigo.withOpacity(0.1),
                            borderColor: Colors.indigo.shade800,
                            borderWidth: 2.5,
                            splineType: SplineType.cardinal,
                          ),
                          // Linea Luce Totale (Verde)
                          SplineSeries<Map<String, dynamic>, DateTime>(
                            name: 'Luce Totale',
                            dataSource: data,
                            xValueMapper: (d, _) => d['timestamp'] as DateTime,
                            yValueMapper: (d, _) => d['clear'] as num,
                            color: Colors.green.shade600,
                            width: 3,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFreshnessWarning(bool isEmpty, bool isOld) {
    if (!isEmpty && !isOld) return const SizedBox.shrink();

    String warningText = isEmpty
        ? "Non ci sono dati salvati nella memoria del telefono."
        : "I dati salvati potrebbero essere vecchi (più di 2 ore).";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50.withOpacity(0.9),
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.amber.shade800, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  warningText,
                  style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005BFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.download, size: 18),
              label: const Text("Scarica Nuovi Dati dispositivo"),
              onPressed: onDownload,
            ),
          )
        ],
      ),
    );
  }

  Widget _buildLatestValueSection() {
    final latest = data.last;
    final clear = latest['clear'] as int;
    final blue = latest['blue'] as int;
    final artif = latest['luceArtificiale'] as int;

    return Row(
      children: [
        Expanded(
          child: _buildDataSummaryCard("Luce Totale", "$clear lx", Icons.wb_sunny, Colors.orange),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildDataSummaryCard("Luce Blu", "$blue lx", Icons.blur_on, Colors.blue),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildDataSummaryCard("Luce Art.", "$artif lx", Icons.lightbulb, Colors.amber),
        ),
      ],
    );
  }

  Widget _buildDataSummaryCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStateCard(String title, String desc) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            Icon(Icons.wb_sunny_outlined, size: 64, color: Colors.blue.shade200),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// PAGINA SUONO (MICROFONO)
// ==========================================
class SuonoPage extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final DateTime? lastUpdate;
  final VoidCallback onDownload;

  const SuonoPage({
    super.key,
    required this.data,
    required this.lastUpdate,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final isDataEmpty = data.isEmpty;
    final isOld = lastUpdate != null &&
        DateTime.now().difference(lastUpdate!).inHours >= 2;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avviso Aggiornamento Dati
          _buildFreshnessWarning(isDataEmpty, isOld),

          if (isDataEmpty)
            _buildEmptyStateCard("Nessun dato audio rilevato", "Scarica i dati del microfono dal dispositivo wearable per analizzare i livelli di rumore ambientale.")
          else ...[
            // Ultimo valore misurato
            _buildLatestValueSection(),
            const SizedBox(height: 16),

            // Grafico SfCartesianChart
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Andamento Livello di Rumore (dB)",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 300,
                      child: SfCartesianChart(
                        tooltipBehavior: TooltipBehavior(enable: true),
                        primaryXAxis: DateTimeAxis(
                          majorGridLines: const MajorGridLines(width: 0),
                        ),
                        primaryYAxis: const NumericAxis(
                          title: AxisTitle(text: 'Volume (dB)'),
                          majorGridLines: MajorGridLines(width: 1, color: Color(0xFFF1F1F1)),
                        ),
                        series: <CartesianSeries>[
                          // Area con gradiente per i decibel
                          SplineAreaSeries<Map<String, dynamic>, DateTime>(
                            name: 'Volume Medio',
                            dataSource: data,
                            xValueMapper: (d, _) => d['timestamp'] as DateTime,
                            yValueMapper: (d, _) => d['db'] as num,
                            color: Colors.teal.shade400.withOpacity(0.2),
                            borderColor: Colors.teal.shade700,
                            borderWidth: 3,
                            splineType: SplineType.cardinal,
                          ),
                          // Punti per i Picchi Rilevati
                          ScatterSeries<Map<String, dynamic>, DateTime>(
                            name: 'Picco Rilevato',
                            dataSource: data.where((d) => d['peak'] == 1).toList(),
                            xValueMapper: (d, _) => d['timestamp'] as DateTime,
                            yValueMapper: (d, _) => d['db'] as num,
                            color: Colors.redAccent,
                            markerSettings: const MarkerSettings(
                              height: 10,
                              width: 10,
                              shape: DataMarkerType.circle,
                            ),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFreshnessWarning(bool isEmpty, bool isOld) {
    if (!isEmpty && !isOld) return const SizedBox.shrink();

    String warningText = isEmpty
        ? "Non ci sono dati salvati nella memoria del telefono."
        : "I dati salvati potrebbero essere vecchi (più di 2 ore).";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50.withOpacity(0.9),
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.amber.shade800, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  warningText,
                  style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005BFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.download, size: 18),
              label: const Text("Scarica Nuovi Dati dispositivo"),
              onPressed: onDownload,
            ),
          )
        ],
      ),
    );
  }

  Widget _buildLatestValueSection() {
    final latest = data.last;
    final db = latest['db'] as int;
    final hasPeak = latest['peak'] == 1;

    String rating = "Tranquillo";
    Color ratingColor = Colors.green;
    if (db > 75) {
      rating = "Molto Rumoroso";
      ratingColor = Colors.red;
    } else if (db > 55) {
      rating = "Rumoroso";
      ratingColor = Colors.orange;
    }

    return Row(
      children: [
        Expanded(
          child: Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.volume_up, color: Colors.teal.shade800, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Volume Medio", style: TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 4),
                      Text("$db dB", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                      Text(rating, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ratingColor)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: hasPeak ? Colors.red.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      hasPeak ? Icons.warning : Icons.gpp_good,
                      color: hasPeak ? Colors.red.shade800 : Colors.green.shade800,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Picco Rilevato", style: TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 4),
                      Text(
                        hasPeak ? "SÌ (Anomalo)" : "NO (Normale)",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: hasPeak ? Colors.red.shade800 : Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyStateCard(String title, String desc) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            Icon(Icons.volume_off, size: 64, color: Colors.teal.shade200),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// PAGINA SALUTE & SONNO (STRESS & MELATONINA)
// ==========================================
class StressMelatoninaPage extends StatelessWidget {
  final Map<String, dynamic>? latestSpec;
  final Map<String, dynamic>? latestMic;

  const StressMelatoninaPage({
    super.key,
    required this.latestSpec,
    required this.latestMic,
  });

  @override
  Widget build(BuildContext context) {
    if (latestSpec == null && latestMic == null) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.spa_outlined, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 20),
            const Text(
              "Dati insufficienti",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            const Text(
              "Scarica sia i dati della luce che quelli del suono per calcolare gli indici di Stress e Melatonina.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.black45),
            ),
          ],
        ),
      );
    }

    // 1. Calcolo Melatonina (0-100%)
    // Più c'è luce blu o artificiale, meno si produce melatonina (soppressione)
    int blueVal = latestSpec != null ? latestSpec!['blue'] as int : 0;
    int artifVal = latestSpec != null ? latestSpec!['luceArtificiale'] as int : 0;
    double melatoninPercent = 100 - (blueVal * 0.08 + artifVal * 0.03);
    melatoninPercent = melatoninPercent.clamp(0, 100);

    // 2. Calcolo Stress Ambientale (0-100%)
    // Più rumore (dB) e luce artificiale sono alti, più c'è stress
    int dbVal = latestMic != null ? latestMic!['db'] as int : 30;
    double stressPercent = (dbVal * 0.75 + artifVal * 0.05);
    stressPercent = stressPercent.clamp(0, 100);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              // Card Melatonina
              Expanded(
                child: _buildHealthGaugeCard(
                  title: "Melatonina",
                  value: "${melatoninPercent.toInt()}%",
                  subtitle: melatoninPercent > 70 ? "Ottima (Favorisce il Sonno)" : "Inibita (Luce Blu Elevata)",
                  color: Colors.indigo.shade700,
                  icon: Icons.nightlight_round,
                  progressValue: melatoninPercent / 100,
                ),
              ),
              const SizedBox(width: 12),
              // Card Stress
              Expanded(
                child: _buildHealthGaugeCard(
                  title: "Stress Ambientale",
                  value: "${stressPercent.toInt()}%",
                  subtitle: stressPercent < 45 ? "Basso (Ottimale)" : "Alto (Rischio Affaticamento)",
                  color: stressPercent < 45 ? Colors.green.shade600 : Colors.red.shade700,
                  icon: Icons.psychology,
                  progressValue: stressPercent / 100,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Consigli Personalizzati per la Salute
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Consigli Salute Personalizzati",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
          const SizedBox(height: 12),

          // Consiglio 1: Sonno e Melatonina
          _buildInsightCard(
            title: "Ottimizzazione del Sonno",
            desc: melatoninPercent > 70
                ? "L'esposizione alla luce blu è ottimale. Se stai pianificando di andare a dormire, il tuo corpo è nella condizione biologica corretta per rilassarsi naturalmente."
                : "Rilevata un'alta presenza di luce blu o artificiale. Questo può inibire la secrezione naturale di melatonina. Spegni gli schermi o allontanati da fonti di luce forte almeno un'ora prima del sonno.",
            icon: Icons.bedtime,
            color: melatoninPercent > 70 ? Colors.indigo.shade50 : Colors.amber.shade50,
            iconColor: melatoninPercent > 70 ? Colors.indigo : Colors.amber.shade800,
          ),
          const SizedBox(height: 12),

          // Consiglio 2: Livello di Rumore
          _buildInsightCard(
            title: "Benessere Ambientale",
            desc: stressPercent < 45
                ? "L'ambiente circostante ha un livello di stimoli sonori e luminosi perfetto per il riposo mentale e l'attività ad alta concentrazione."
                : "Il tuo attuale ambiente presenta elevati stimoli sonori o di illuminazione che possono innalzare i livelli di cortisolo. Fai una pausa di 10 minuti in una stanza più silenziosa per decongestionare la mente.",
            icon: Icons.spa,
            color: stressPercent < 45 ? Colors.green.shade50 : Colors.red.shade50,
            iconColor: stressPercent < 45 ? Colors.green.shade800 : Colors.red.shade800,
          ),
        ],
      ),
    );
  }

  Widget _buildHealthGaugeCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
    required double progressValue,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            // Cerchio di Progresso
            SizedBox(
              width: 90,
              height: 90,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: progressValue,
                    strokeWidth: 8,
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                  Center(
                    child: Text(
                      value,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightCard({
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
    required Color iconColor,
  }) {
    return Card(
      elevation: 0,
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    desc,
                    style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade800, height: 1.4),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
