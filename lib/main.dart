import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LifeAssistantApp());
}

class NotificationService {
  final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();

  Future<bool> initialize() async {
    try {
      tz.initializeTimeZones();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      final initialized = await plugin.initialize(settings);
      final androidPlugin = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final permission = await androidPlugin?.requestNotificationsPermission();
      return initialized == true && permission != false;
    } catch (_) {
      return false;
    }
  }

  NotificationDetails get details => const NotificationDetails(
        android: AndroidNotificationDetails(
          'life_assistant_reminders',
          'Life assistant reminders',
          channelDescription: 'Hydration and checklist reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

  Future<void> scheduleChecklistAlarm(TimeOfDay time) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (!scheduled.isAfter(now)) scheduled = scheduled.add(const Duration(days: 1));
    await plugin.zonedSchedule(
      1,
      'Checklist first',
      'Review your checklist before you leave.',
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> scheduleHydrationReminders() async {
    final now = tz.TZDateTime.now(tz.local);
    for (var index = 1; index <= 12; index++) {
      await plugin.zonedSchedule(
        1000 + index,
        'Hydration reminder',
        'Have some water and update your hydration tracker.',
        now.add(Duration(minutes: index * 30)),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}

class LifeAssistantApp extends StatelessWidget {
  const LifeAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Life & Seva Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff087fbd),
          primary: const Color(0xff087fbd),
          secondary: const Color(0xffe45d16),
          surface: const Color(0xfffffbf7),
        ),
        scaffoldBackgroundColor: const Color(0xfffff8ef),
        useMaterial3: true,
        cardTheme: CardThemeData(
          color: Colors.white.withValues(alpha: 0.86),
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class Activity {
  String name;
  String category;
  int target;
  String unit;
  bool completed;

  Activity({
    required this.name,
    required this.category,
    this.target = 1,
    this.unit = 'time',
    this.completed = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name, 'category': category, 'target': target,
    'unit': unit, 'completed': completed,
  };

  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
    name: j['name'],
    category: j['category'],
    target: j['target'] ?? 1,
    unit: j['unit'] ?? 'time',
    completed: j['completed'] ?? false,
  );
}

class LedgerEntry {
  String title;
  double amount;
  String type;
  String note;

  LedgerEntry({required this.title, required this.amount, required this.type, this.note = ''});

  Map<String, dynamic> toJson() => {
        'title': title,
        'amount': amount,
        'type': type,
        'note': note,
      };

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
        title: json['title'] ?? 'Untitled',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        type: json['type'] ?? 'Expense',
        note: json['note'] ?? '',
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int waterMl = 0;
  int waterTarget = 2500;
  int selectedTab = 0;
  String locationName = 'Set your location';
  int temperature = 28;
  final NotificationService notificationService = NotificationService();
  bool notificationsEnabled = false;
  int? indoorTemperature;
  double? latitude;
  double? longitude;
  List<Map<String, dynamic>> checklist = [
    {'name': 'Wallet', 'done': false},
    {'name': 'Phone', 'done': false},
    {'name': 'Keys', 'done': false},
    {'name': 'Water bottle', 'done': false},
    {'name': 'Charger', 'done': false},
    {'name': 'ID card', 'done': false},
  ];
  List<LedgerEntry> ledger = [];
  List<Activity> activities = [
    Activity(name: 'Chant 16 rounds', category: 'Spiritual', target: 16, unit: 'rounds'),
    Activity(name: 'Book reading', category: 'Spiritual', target: 20, unit: 'minutes'),
    Activity(name: 'Physical activity', category: 'Beyond Job', target: 30, unit: 'minutes'),
    Activity(name: 'Preaching / follow-up', category: 'Preaching'),
  ];

  final suggestions = const [
    ['Chant 16 rounds', 'Spiritual'],
    ['Read Bhagavad-gita', 'Spiritual'],
    ['Read Srimad Bhagavatam', 'Spiritual'],
    ['Do 20-minute walk', 'Beyond Job'],
    ['Call a devotee', 'Preaching'],
    ['Invite someone to temple', 'Preaching'],
    ['Temple cleaning seva', 'Seva'],
    ['Prasadam distribution', 'Seva'],
    ['Plan tomorrow', 'Personal'],
    ['Review expenses', 'Personal'],
  ];

  @override
  void initState() {
    super.initState();
    loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) => checkForGithubUpdate());
  }

  Future<void> checkForGithubUpdate() async {
    try {
      const releaseApi = 'https://api.github.com/repos/pbrundha1-design/personal-life-seva-assistant/releases/latest';
      const apkName = 'app-release.apk';
      final releaseResponse = await http.get(Uri.parse(releaseApi), headers: {'Accept': 'application/vnd.github+json'});
      if (releaseResponse.statusCode != 200) return;
      final release = jsonDecode(releaseResponse.body) as Map<String, dynamic>;
      final packageInfo = await PackageInfo.fromPlatform();
      final latestVersion = int.tryParse('${release['tag_name']}'.replaceFirst('v', '').split('+').last);
      final installedVersion = int.tryParse(packageInfo.buildNumber) ?? 0;
      if (latestVersion == null || latestVersion <= installedVersion || !mounted) return;
      final assets = (release['assets'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final asset = assets.cast<Map<String, dynamic>?>().firstWhere((item) => item?['name'] == apkName, orElse: () => null);
      final downloadUrl = asset?['browser_download_url'] as String?;
      if (downloadUrl == null) return;
      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Update available'),
          content: Text('Version ${release['tag_name']} is ready to download.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Download update')),
          ],
        ),
      );
      if (shouldUpdate != true || !mounted) return;
      final download = await http.get(Uri.parse(downloadUrl));
      if (download.statusCode != 200) return;
      final directory = await getTemporaryDirectory();
      final apk = File('${directory.path}/$apkName');
      await apk.writeAsBytes(download.bodyBytes);
      await OpenFilex.open(apk.path, type: 'application/vnd.android.package-archive');
    } catch (_) {
      // GitHub updates are unavailable when there is no network or release.
    }
  }

  Future<void> loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      waterMl = p.getInt('waterMl') ?? 0;
      temperature = p.getInt('temperature') ?? 28;
      indoorTemperature = p.getInt('indoorTemperature');
      latitude = p.getDouble('latitude');
      longitude = p.getDouble('longitude');
      locationName = p.getString('locationName') ?? 'Set your location';
      waterTarget = p.getInt('waterTarget') ?? (temperature >= 32 ? 3000 : 2500);
      final raw = p.getString('activities');
      if (raw != null) {
        activities = (jsonDecode(raw) as List)
            .map((e) => Activity.fromJson(e))
            .toList();
      }
          final savedChecklist = p.getString('checklist');
          if (savedChecklist != null) {
            checklist = (jsonDecode(savedChecklist) as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
          }
          final savedLedger = p.getString('ledger');
          if (savedLedger != null) {
            ledger = (jsonDecode(savedLedger) as List)
            .map((e) => LedgerEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
          }
    });
    notificationsEnabled = await notificationService.initialize();
    if (notificationsEnabled) {
      await notificationService.scheduleHydrationReminders();
    }
    if (latitude != null && longitude != null) {
      await refreshWeather(latitude!, longitude!);
    }
  }

  Future<void> saveData() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('waterMl', waterMl);
    await p.setInt('waterTarget', waterTarget);
    await p.setInt('temperature', temperature);
        if (indoorTemperature == null) {
          await p.remove('indoorTemperature');
        } else {
          await p.setInt('indoorTemperature', indoorTemperature!);
        }
        if (latitude != null && longitude != null) {
          await p.setDouble('latitude', latitude!);
          await p.setDouble('longitude', longitude!);
        }
    await p.setString('locationName', locationName);
    await p.setString('activities',
        jsonEncode(activities.map((e) => e.toJson()).toList()));
    await p.setString('checklist', jsonEncode(checklist));
    await p.setString('ledger', jsonEncode(ledger.map((e) => e.toJson()).toList()));
  }

  Future<void> addWater(int amount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log water?'),
        content: Text('Add $amount ml to today\'s hydration total?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add water')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => waterMl += amount);
    await saveData();
  }

  Future<void> refreshWeather(double latitude, double longitude) async {
    try {
      final weatherUri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude&current=temperature_2m',
      );
      final response = await http.get(weatherUri);
      if (response.statusCode != 200) return;
      final weather = jsonDecode(response.body) as Map<String, dynamic>;
      final current = weather['current'] as Map<String, dynamic>?;
      final currentTemperature = (current?['temperature_2m'] as num?)?.round();
      if (!mounted || currentTemperature == null) return;
      setState(() {
        this.latitude = latitude;
        this.longitude = longitude;
        temperature = currentTemperature;
        waterTarget = temperature >= 32 ? 3000 : temperature >= 28 ? 2750 : 2500;
      });
      await saveData();
    } catch (_) {
      if (mounted) showMessage('Live outdoor temperature is unavailable.');
    }
  }

  Future<void> setChecklistAlarm() async {
    if (!notificationsEnabled) {
      showMessage('Allow notifications in Android settings to set an alarm.');
      return;
    }
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    await notificationService.scheduleChecklistAlarm(time);
    showMessage('Checklist alarm set for ${time.format(context)}.');
  }

  void editActivity({Activity? activity, String? suggestedName, String? suggestedCategory}) {
    final name = TextEditingController(text: activity?.name ?? suggestedName ?? '');
    final category = TextEditingController(text: activity?.category ?? suggestedCategory ?? 'Personal');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(activity == null ? 'Add activity' : 'Edit activity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Activity name')),
            TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty) {
                setState(() {
                  if (activity == null) {
                    activities.add(Activity(
                      name: name.text.trim(),
                      category: category.text.trim().isEmpty ? 'Personal' : category.text.trim(),
                    ));
                  } else {
                    activity.name = name.text.trim();
                    activity.category = category.text.trim().isEmpty ? 'Personal' : category.text.trim();
                  }
                });
                saveData();
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void showProfile() {
    final location = TextEditingController(text: locationName == 'Set your location' ? '' : locationName);
    final temp = TextEditingController(text: temperature.toString());
    final indoorTemp = TextEditingController(text: indoorTemperature?.toString() ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Care profile'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: location, decoration: const InputDecoration(labelText: 'Location')),
          TextField(controller: temp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Outdoor temperature (°C)')),
          TextField(controller: indoorTemp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Indoor temperature (°C, optional)')),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => useCurrentLocation(location, temp),
              icon: const Icon(Icons.my_location),
              label: const Text('Use current location'),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Outdoor temperature comes from live weather. Indoor temperature must be entered manually unless an external sensor is connected.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            setState(() {
              locationName = location.text.trim().isEmpty ? 'Set your location' : location.text.trim();
              temperature = int.tryParse(temp.text) ?? 28;
              indoorTemperature = int.tryParse(indoorTemp.text);
              waterTarget = temperature >= 32 ? 3000 : temperature >= 28 ? 2750 : 2500;
            });
            saveData();
            Navigator.pop(context);
          }, child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> useCurrentLocation(
    TextEditingController locationController,
    TextEditingController temperatureController,
  ) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        showMessage('Turn on location services, then try again.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        showMessage('Location permission was not granted. You can enter a location manually.');
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      locationController.text = '${position.latitude.toStringAsFixed(3)}, ${position.longitude.toStringAsFixed(3)}';
      latitude = position.latitude;
      longitude = position.longitude;
      await refreshWeather(position.latitude, position.longitude);
      temperatureController.text = temperature.toString();
      showMessage('Location and temperature updated.');
    } catch (_) {
      showMessage('Could not read location or weather. Manual entry is still available.');
    }
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }

  Widget _dateStrip() {
    final today = DateTime.now();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(5, (index) {
        final date = today.subtract(Duration(days: 2 - index));
        final isToday = index == 2;
        return Container(
          width: isToday ? 54 : 46,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isToday ? const Color(0xff087fbd) : Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isToday ? const Color(0xff087fbd) : const Color(0xffeaded2)),
            boxShadow: isToday ? [const BoxShadow(color: Color(0x33087fbd), blurRadius: 10, offset: Offset(0, 4))] : null,
          ),
          child: Column(children: [
            Text(isToday ? 'TODAY' : _weekday(date.weekday), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: isToday ? Colors.white : const Color(0xff8b817e))),
            const SizedBox(height: 4),
            Text('${date.day}', style: TextStyle(fontWeight: FontWeight.w800, color: isToday ? Colors.white : const Color(0xff272236))),
          ]),
        );
      }),
    );
  }

  String _weekday(int day) => const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][day - 1];

  Widget dashboard() {
    final completed = activities.where((a) => a.completed).length;
    final progress = waterTarget == 0 ? 0.0 : (waterMl / waterTarget).clamp(0.0, 1.0);
    final remaining = (waterTarget - waterMl).clamp(0, waterTarget);
    final spiritualDone = activities.where((a) => a.category == 'Spiritual' && a.completed).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0xfff8a21b), Color(0xff08a9d1)]),
              ),
              child: const Icon(Icons.water_drop, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sadhana & Swasthya', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text('Hare Krishna  •  ${locationName == 'Set your location' ? 'Local care' : locationName}', style: Theme.of(context).textTheme.bodySmall),
            ])),
            IconButton(onPressed: showProfile, icon: const Icon(Icons.tune), tooltip: 'Care profile'),
          ],
        ),
        const SizedBox(height: 16),
        _dateStrip(),
        const SizedBox(height: 16),

        Card(
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xffeefaff), Colors.white, Color(0xfffff4e7)]),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.water_drop, color: Color(0xff087fbd)),
                const SizedBox(width: 8),
                const Expanded(child: Text('Hydration command', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                _badge('${(progress * 100).round()}% complete', const Color(0xff087fbd)),
              ]),
              const SizedBox(height: 20),
              Center(child: Column(children: [
                Text('$waterMl', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: Color(0xff087fbd))),
                Text('/ $waterTarget ml', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff6d6871))),
              ])),
              const SizedBox(height: 14),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress, minHeight: 10, color: const Color(0xff087fbd), backgroundColor: const Color(0xffd6effd))),
              const SizedBox(height: 12),
              Row(children: [const Icon(Icons.notifications_active, size: 18, color: Color(0xff087fbd)), const SizedBox(width: 8), Expanded(child: Text(remaining == 0 ? 'Target reached. Keep following your care plan.' : 'Next drink reminder • every 30 minutes')), Text('$remaining ml left', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff087fbd)))]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: FilledButton.tonal(onPressed: () => addWater(250), child: const Text('+250 ml'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton.tonal(onPressed: () => addWater(500), child: const Text('+500 ml'))),
              ]),
            ]),
          ),
        ),

        Card(
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xffffeadb), child: Icon(Icons.self_improvement, color: Color(0xffe45d16))),
            title: const Text('Today\'s Sadhana', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('$spiritualDone spiritual activities complete  •  $completed/${activities.length} total'),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              _badge('$temperature°C outdoor', const Color(0xffe45d16)),
              if (indoorTemperature != null) Text('$indoorTemperature°C indoor', style: const TextStyle(fontSize: 11)),
            ]),
          ),
        ),

        const SizedBox(height: 8),
        Text('Today\'s Activities', style: Theme.of(context).textTheme.titleLarge),
        ...activities.map((a) => Card(
          child: CheckboxListTile(
            value: a.completed,
            title: Text(a.name),
            subtitle: Text(a.category),
            onChanged: (v) {
              setState(() => a.completed = v ?? false);
              saveData();
            },
            secondary: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  editActivity(activity: a);
                } else if (value == 'delete') {
                  setState(() => activities.remove(a));
                  saveData();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        )),

        FilledButton.icon(
          onPressed: () => editActivity(),
          icon: const Icon(Icons.add),
          label: const Text('Add Activity'),
        ),
      ],
    );
  }

  Widget suggestionsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Suggested Activities', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Choose useful activities and add them to today\'s routine.'),
        const SizedBox(height: 12),
        ...suggestions.map((s) => Card(
          child: ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: Text(s[0]),
            subtitle: Text(s[1]),
            trailing: IconButton(
              icon: const Icon(Icons.add_circle),
              onPressed: () => editActivity(
                suggestedName: s[0],
                suggestedCategory: s[1],
              ),
            ),
          ),
        )),
      ],
    );
  }

  Widget checklistPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Reusable Checklists', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Leaving home  •  ${checklist.where((item) => item['done'] == true).length}/${checklist.length} ready'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: setChecklistAlarm,
          icon: const Icon(Icons.alarm_add),
          label: const Text('Set alarm before checklist'),
        ),
        const SizedBox(height: 8),
        ...checklist.asMap().entries.map((entry) => Card(
          child: CheckboxListTile(
            value: entry.value['done'] as bool,
            title: Text(entry.value['name'] as String),
            onChanged: (value) {
              setState(() => checklist[entry.key]['done'] = value ?? false);
              saveData();
            },
            secondary: IconButton(
              tooltip: 'Delete item',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                setState(() => checklist.removeAt(entry.key));
                saveData();
              },
            ),
          ),
        )),
        FilledButton.icon(
          onPressed: () {
            final c = TextEditingController();
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Add checklist item'),
                content: TextField(controller: c, autofocus: true),
                actions: [
                  FilledButton(
                    onPressed: () {
                      if (c.text.trim().isNotEmpty) {
                        setState(() => checklist.add({'name': c.text.trim(), 'done': false}));
                        saveData();
                      }
                      Navigator.pop(context);
                    },
                    child: const Text('Add'),
                  )
                ],
              ),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('Add item'),
        ),
      ],
    );
  }

  Widget accountsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Accounts', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.account_balance_wallet),
          title: const Text('Simple personal ledger'),
          subtitle: const Text('Add people, money given, money received and expenses.'),
          trailing: Text('₹${ledger.fold<double>(0, (sum, item) => sum + (item.type == 'Income' ? item.amount : -item.amount)).toStringAsFixed(0)}'),
        )),
        ...ledger.asMap().entries.map((entry) => Card(child: ListTile(
          leading: Icon(entry.value.type == 'Income' ? Icons.arrow_downward : Icons.arrow_upward),
          title: Text(entry.value.title),
          subtitle: Text('${entry.value.type}${entry.value.note.isEmpty ? '' : ' • ${entry.value.note}'}'),
          trailing: Text('₹${entry.value.amount.toStringAsFixed(0)}'),
          onLongPress: () {
            setState(() => ledger.removeAt(entry.key));
            saveData();
          },
        ))),
        FilledButton.icon(onPressed: addLedgerEntry, icon: const Icon(Icons.add), label: const Text('Add transaction')),
      ],
    );
  }

  void addLedgerEntry() {
    final title = TextEditingController();
    final amount = TextEditingController();
    final note = TextEditingController();
    String type = 'Expense';
    showDialog(context: context, builder: (_) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('Add transaction'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
        TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount')),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
        DropdownButton<String>(value: type, items: const [DropdownMenuItem(value: 'Expense', child: Text('Expense')), DropdownMenuItem(value: 'Income', child: Text('Income'))], onChanged: (value) => setDialogState(() => type = value ?? 'Expense')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () {
        final value = double.tryParse(amount.text);
        if (title.text.trim().isNotEmpty && value != null) {
          setState(() => ledger.add(LedgerEntry(title: title.text.trim(), amount: value, type: type, note: note.text.trim())));
          saveData();
        }
        Navigator.pop(context);
      }, child: const Text('Add'))],
    )));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [dashboard(), suggestionsPage(), checklistPage(), accountsPage()];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Life & Seva Assistant'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: showProfile,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xfffff4e5), Color(0xfff4f7ff), Color(0xfffff8f1)],
          ),
        ),
        child: pages[selectedTab],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (i) => setState(() => selectedTab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'Suggest'),
          NavigationDestination(icon: Icon(Icons.checklist), label: 'Checklist'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: 'Accounts'),
        ],
      ),
    );
  }
}
