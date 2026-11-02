import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const YogaApp());
}

class YogaApp extends StatelessWidget {
  const YogaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yoga & Meditation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

// ==========================================
// 🗄️ DATA MODEL (ஸ்கேன் செய்த தரவை சேமிக்க)
// ==========================================
class WorkoutLog {
  final String date;
  final String time;
  final String type; // 'Pranayama' அல்லது 'Meditation'
  final int duration;
  final int calories;
  final int avgHr;
  final int maxHr;
  final int minHr;

  WorkoutLog({
    required this.date,
    required this.time,
    required this.type,
    required this.duration,
    required this.calories,
    required this.avgHr,
    required this.maxHr,
    required this.minHr,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'time': time,
        'type': type,
        'duration': duration,
        'calories': calories,
        'avgHr': avgHr,
        'maxHr': maxHr,
        'minHr': minHr,
      };

  factory WorkoutLog.fromJson(Map<String, dynamic> json) => WorkoutLog(
        date: json['date'] ?? '',
        time: json['time'] ?? '',
        type: json['type'] ?? 'Pranayama',
        duration: json['duration'] ?? 0,
        calories: json['calories'] ?? 0,
        avgHr: json['avgHr'] ?? 0,
        maxHr: json['maxHr'] ?? 0,
        minHr: json['minHr'] ?? 0,
      );
}

// ==========================================
// MAIN SCREEN (Home & Share Intent)
// ==========================================
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late StreamSubscription _intentDataStreamSubscription;
  
  int currentDay = 1;
  bool isSessionActive = false;
  bool isYoga = false;
  Timer? _timer;
  int _elapsedSeconds = 0;
  final int _yogaTickLimitSeconds = 20 * 60; // 20 Minutes
  
  final AudioPlayer _audioPlayer = AudioPlayer();
  final String _logsKey = 'workout_logs';

  @override
  void initState() {
    super.initState();
    _loadProgress();
    _initShareIntent();
  }

  // 📥 ஷேர் மெனுவில் இருந்து வரும் போட்டோவைப் பிடிக்கும் லாஜிக்
  void _initShareIntent() {
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty && value.first.type == SharedMediaType.image) {
          _processSharedImage(value.first.path);
        }
      },
      onError: (err) {
        debugPrint("Share Intent Error: $err");
      },
    );

    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty && value.first.type == SharedMediaType.image) {
        _processSharedImage(value.first.path);
      }
      ReceiveSharingIntent.instance.reset();
    });
  }

  // 🔍 ஷேர் செய்யப்பட்ட போட்டோவை ஸ்கேன் செய்யும் ஃபங்ஷன்
  Future<void> _processSharedImage(String imagePath) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(inputImage);
      textRecognizer.close();
      
      if (mounted) Navigator.pop(context);
      _parseAndSaveData(recognizedText.text);

    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // 📊 எண்களைப் பிரித்தெடுத்து, AM/PM லாஜிக் மூலம் சேமித்தல்
  Future<void> _parseAndSaveData(String text) async {
    RegExp avgHrRegex = RegExp(r'(?:avg|average|சராசரி)[^\d\n]*(\d{2,3})', caseSensitive: false);
    RegExp maxHrRegex = RegExp(r'(?:high|max|maximum|peak|உச்ச)[^\d\n]*(\d{2,3})', caseSensitive: false);
    RegExp minHrRegex = RegExp(r'(?:min|minimum|குறைந்தபட்ச|low)[^\d\n]*(\d{2,3})', caseSensitive: false);
    RegExp caloriesRegex = RegExp(r'(\d{2,4})\s*(?:kcal|cal|கலோரி)', caseSensitive: false);
    RegExp durationRegex = RegExp(r'(\d{1,3})\s*(?:mins?|minutes|m\b|நிமிடம்)', caseSensitive: false);
    RegExp dateRegex = RegExp(r'(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{4})', caseSensitive: false);
    RegExp timeRegex = RegExp(r'(\d{1,2}:\d{2}\s*(?:AM|PM|am|pm))', caseSensitive: false);

    int avgHr = int.tryParse(avgHrRegex.firstMatch(text)?.group(1) ?? '') ?? 0;
    int maxHr = int.tryParse(maxHrRegex.firstMatch(text)?.group(1) ?? '') ?? 0;
    int minHr = int.tryParse(minHrRegex.firstMatch(text)?.group(1) ?? '') ?? 0;
    int calories = int.tryParse(caloriesRegex.firstMatch(text)?.group(1) ?? '') ?? 0;
    int duration = int.tryParse(durationRegex.firstMatch(text)?.group(1) ?? '') ?? 0;
    
    String dateStr = dateRegex.firstMatch(text)?.group(1) ?? DateFormat('dd MMM yyyy').format(DateTime.now());
    String timeStr = timeRegex.firstMatch(text)?.group(1)?.toUpperCase() ?? DateFormat('hh:mm a').format(DateTime.now());

    // 🕐 AM/PM லாஜிக்: AM = Pranayama, PM = Meditation
    String exerciseType = timeStr.contains('PM') ? 'Meditation' : 'Pranayama';

    WorkoutLog newLog = WorkoutLog(
      date: dateStr, time: timeStr, type: exerciseType,
      duration: duration, calories: calories, avgHr: avgHr, maxHr: maxHr, minHr: minHr,
    );

    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> savedLogs = prefs.getStringList(_logsKey) ?? [];
    savedLogs.add(jsonEncode(newLog.toJson()));
    await prefs.setStringList(_logsKey, savedLogs);

    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const StatsScreen()));
    }
  }

  Future<void> _loadProgress() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() => currentDay = prefs.getInt('currentDay') ?? 1);
  }

  void startYoga() {
    setState(() { isSessionActive = true; isYoga = true; _elapsedSeconds = 0; });
    WakelockPlus.enable();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _elapsedSeconds++);
      if (_elapsedSeconds <= _yogaTickLimitSeconds) {
        _audioPlayer.play(AssetSource('tick.mp3'));
      } else if (_elapsedSeconds == _yogaTickLimitSeconds + 1) {
        _audioPlayer.stop();
      }
    });
  }

  void startMeditation() {
    setState(() { isSessionActive = true; isYoga = false; _elapsedSeconds = 0; });
    WakelockPlus.enable();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) => setState(() => _elapsedSeconds++));
  }

  void stopSession() {
    _timer?.cancel();
    _audioPlayer.stop();
    WakelockPlus.disable();
    setState(() { isSessionActive = false; });
    
    int nextDay = currentDay + 1;
    SharedPreferences.getInstance().then((prefs) => prefs.setInt('currentDay', nextDay));
    setState(() => currentDay = nextDay);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text("Completed!"),
          ],
        ),
        content: Text("✅ Day ${nextDay - 1} Successfully Completed.\n\n📅 Next Day: $nextDay\n⏱ Duration: ${10 + (nextDay ~/ 30)} Mins\n⚖ Ratio: 1:${2 + (nextDay ~/ 100)}"),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Confirm"))],
      ),
    );
  }

  String get formattedTime => "${(_elapsedSeconds ~/ 3600).toString().padLeft(2, '0')}:${((_elapsedSeconds % 3600) ~/ 60).toString().padLeft(2, '0')}:${(_elapsedSeconds % 60).toString().padLeft(2, '0')}";

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    _timer?.cancel();
    _audioPlayer.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Practice"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const StatsScreen())),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("📌 Today's Target (Day $currentDay)", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                    const SizedBox(height: 10),
                    Text("Duration: ${10 + (currentDay ~/ 30)} Mins", style: const TextStyle(fontSize: 16)),
                    Text("Ratio: 1:${2 + (currentDay ~/ 100)}", style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),
            const Spacer(),
            if (isSessionActive) ...[
              Text(formattedTime, style: const TextStyle(fontSize: 60, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              const SizedBox(height: 20),
              Text(isYoga ? (_elapsedSeconds <= 1200 ? "🎵 Yoga Ticking..." : "🔇 20 Mins Completed.") : "🧘 Meditating...", style: const TextStyle(fontSize: 18, color: Colors.grey)),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity, height: 60,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  onPressed: stopSession,
                  icon: const Icon(Icons.stop),
                  label: const Text("STOP & FINISH", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity, height: 60,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                  onPressed: startYoga,
                  icon: const Icon(Icons.self_improvement),
                  label: const Text("START YOGA", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 60,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent, foregroundColor: Colors.white),
                  onPressed: startMeditation,
                  icon: const Icon(Icons.nights_stay),
                  label: const Text("START MEDITATION", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 📊 STATS SCREEN (Chart & Filters)
// ==========================================
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<WorkoutLog> allLogs = [];
  List<WorkoutLog> filteredLogs = [];

  String selectedExercise = 'All'; // 'All', 'Pranayama', 'Meditation'
  String selectedChartType = 'Bar'; // 'Bar', 'Line', 'Area'
  DateTime? fromDate;
  DateTime? toDate;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> savedLogs = prefs.getStringList('workout_logs') ?? [];
    
    setState(() {
      allLogs = savedLogs.map((e) => WorkoutLog.fromJson(jsonDecode(e))).toList();
      // தேதி வாரியாக வரிசைப்படுத்து
      allLogs.sort((a, b) {
        try {
          return DateTime.parse(a.date).compareTo(DateTime.parse(b.date));
        } catch (e) {
          return 0;
        }
      });
      _applyFilters();
    });
  }

  void _applyFilters() {
    setState(() {
      filteredLogs = allLogs.where((log) {
        bool matchesExercise = selectedExercise == 'All' || log.type == selectedExercise;
        
        bool matchesDate = true;
        try {
          DateTime logDate = DateTime.parse(log.date);
          if (fromDate != null && logDate.isBefore(fromDate!)) matchesDate = false;
          if (toDate != null && logDate.isAfter(toDate!)) matchesDate = false;
        } catch (e) {
          // தேதி பார்ஸ் ஆகலைனா ஃபில்டர் செய்ய வேண்டாம்
        }

        return matchesExercise && matchesDate;
      }).toList();
    });
  }

  Widget _buildChart() {
    if (filteredLogs.isEmpty) return const Center(child: Text("No Data Available for Selected Filters"));

    List<FlSpot> spots = [];
    double x = 0;
    for (var log in filteredLogs) {
      spots.add(FlSpot(x, log.avgHr.toDouble()));
      x += 1;
    }

    if (selectedChartType == 'Bar') {
      return BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 200,
          barTouchData: BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) {
              int idx = val.toInt();
              if (idx >= 0 && idx < filteredLogs.length) {
                String d = filteredLogs[idx].date;
                return Text(d.length > 5 ? d.substring(0, 5) : d, style: const TextStyle(fontSize: 10));
              }
              return const Text('');
            })),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barGroups: spots.asMap().entries.map((e) {
            return BarChartGroupData(x: e.key, barRods: [
              BarChartRodData(toY: e.value.y, color: Colors.blue, width: 15, borderRadius: BorderRadius.circular(2))
            ]);
          }).toList(),
        ),
      );
    } else if (selectedChartType == 'Line' || selectedChartType == 'Area') {
      return LineChart(
        LineChartData(
          gridData: const FlGridData(show: true),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) {
              int idx = val.toInt();
              if (idx >= 0 && idx < filteredLogs.length) {
                String d = filteredLogs[idx].date;
                return Text(d.length > 5 ? d.substring(0, 5) : d, style: const TextStyle(fontSize: 10));
              }
              return const Text('');
            })),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.blue,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: selectedChartType == 'Area', color: Colors.blue.withOpacity(0.3)),
            ),
          ],
        ),
      );
    }
    return const SizedBox();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Workout Analysis"), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: Column(
        children: [
          // 🔝 FILTERS SECTION
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade200,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: "Exercise", isDense: true),
                        value: selectedExercise,
                        items: ['All', 'Pranayama', 'Meditation'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (val) { setState(() => selectedExercise = val!); _applyFilters(); },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: "Chart Type", isDense: true),
                        value: selectedChartType,
                        items: ['Bar', 'Line', 'Area'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (val) { setState(() => selectedChartType = val!); },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          DateTime? picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
                          if (picked != null) { setState(() => fromDate = picked); _applyFilters(); }
                        },
                        child: Text(fromDate == null ? "From Date" : DateFormat('dd MMM yy').format(fromDate!)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          DateTime? picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
                          if (picked != null) { setState(() => toDate = picked); _applyFilters(); }
                        },
                        child: Text(toDate == null ? "To Date" : DateFormat('dd MMM yy').format(toDate!)),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.clear, color: Colors.red),
                      onPressed: () { setState(() { fromDate = null; toDate = null; selectedExercise = 'All'; }); _applyFilters(); },
                    )
                  ],
                ),
              ],
            ),
          ),
          
          // 📊 CHART SECTION
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildChart(),
            ),
          ),

          // 📋 DATA LIST
          Expanded(
            child: ListView.builder(
              itemCount: filteredLogs.length,
              itemBuilder: (context, index) {
                final log = filteredLogs[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: Icon(
                      log.type == 'Pranayama' ? Icons.wb_sunny : Icons.nights_stay, 
                      color: log.type == 'Pranayama' ? Colors.orange : Colors.indigo
                    ),
                    title: Text("${log.date} - ${log.time}"),
                    subtitle: Text("${log.type} | ${log.duration} mins | ${log.calories} kcal"),
                    trailing: Text("Avg HR: ${log.avgHr}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
