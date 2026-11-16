import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://crbvlihqgtdpnmnledws.supabase.co',
    anonKey: 'sb_publishable_Uj2y4RhzaWtPFO7ixmF1YQ_xLkzv_dO',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng currentLocation = LatLng(12.9716, 77.5946);
  List<LatLng> routePoints = [];
  List<Marker> trafficMarkers = [];
  String mapStyle = 'standard';
  final Map<String, Map<String, dynamic>> mapStyles = {
    'standard': {
      'label': 'Standard',
      'url': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      'subdomains': null,
    },
    'satellite': {
      'label': 'Satellite',
      'url':
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      'subdomains': null,
    },
    'night': {
      'label': 'Night',
      'url': 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
      'subdomains': ['a', 'b', 'c', 'd'],
    },
  };

  final MapController mapController = MapController();
  bool isNavigating = false;
  int selectedTabIndex = 0;
  StreamSubscription<Position>? _positionSub;
  // Live navigation state
  double remainingDistanceKm = 0;
  double remainingTimeMin = 0;

  // Simulation for emulator/testing
  bool isSimulating = false;
  Timer? _simTimer;
  int _simIndex = 0;
  // Turn-by-turn steps
  List<Map<String, dynamic>> navSteps = [];
  int currentStepIndex = 0;

  String trafficWarning = "";
  bool useCurrentLocation = true;
  String selectedTransport = "driving-car";
  String routeProfile = "driving-car";
  bool isLoading = true;
  bool reportingMode = false;
  String? reportingType;
  LatLng? sourceLocation;
  LatLng? destinationLocation;

  double distanceKm = 0;
  double durationMin = 0;

  TextEditingController sourceController = TextEditingController();
  TextEditingController destController = TextEditingController();

  List sourceSuggestions = [];
  List destSuggestions = [];

  final supabase = Supabase.instance.client;

  final String routeApiKey =
      "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjBmOTJkMjYwMmMxMjQxMDhhY2VlMTdiZmI2OTFiNjk3IiwiaCI6Im11cm11cjY0In0=";

  @override
  void initState() {
    super.initState();
    getLocation();
    listenMarkers();
  }

  // 📍 Get location
  Future<void> getLocation() async {
    LocationPermission permission = await Geolocator.requestPermission();
    Position pos = await Geolocator.getCurrentPosition();

    setState(() {
      currentLocation = LatLng(pos.latitude, pos.longitude);
      isLoading = false;
    });
  }

  // 🔥 REALTIME MARKERS
  void listenMarkers() {
    supabase.from('traffic').stream(primaryKey: ['id']).listen((data) {
      setState(() {
        trafficMarkers = data.map((e) {
          IconData icon;
          Color color;

          if (e['type'] == "accident") {
            icon = Icons.car_crash;
            color = Colors.red;
          } else if (e['type'] == "jam") {
            icon = Icons.traffic;
            color = Colors.orange;
          } else {
            icon = Icons.block;
            color = Colors.black;
          }

          return Marker(
            point: LatLng(e['lat'], e['lng']),
            width: 50,
            height: 50,
            child: Icon(icon, color: color, size: 30),
          );
        }).toList();
      });
    });
  }

  // 🚦 Add marker
  Future<void> reportIncident(LatLng point) async {
    if (reportingType == null || reportingType!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an incident type first.')),
      );
      return;
    }

    final type = reportingType!;
    final newMarker = Marker(
      point: point,
      width: 50,
      height: 50,
      child: Icon(
        type == 'accident'
            ? Icons.car_crash
            : type == 'jam'
            ? Icons.traffic
            : Icons.block,
        color: type == 'accident'
            ? Colors.red
            : type == 'jam'
            ? Colors.orange
            : Colors.black,
        size: 30,
      ),
    );

    setState(() {
      reportingMode = false;
      reportingType = null;
      trafficMarkers = [...trafficMarkers, newMarker];
    });

    try {
      final response = await supabase.from('traffic').insert({
        'lat': point.latitude,
        'lng': point.longitude,
        'type': type,
      });

      if (response.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report failed: ${response.error!.message}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reported $type at selected location.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Report failed: $e')));
    }
  }

  // 🚦 Report UI
  void openReportMenu() {
    if (!isNavigating) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start navigation first to report an incident.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.car_crash, color: Colors.red),
            title: const Text("Accident"),
            onTap: () {
              setState(() {
                reportingMode = true;
                reportingType = "accident";
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tap on the map to report an accident.'),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.traffic, color: Colors.orange),
            title: const Text("Traffic Jam"),
            onTap: () {
              setState(() {
                reportingMode = true;
                reportingType = "jam";
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tap on the map to report a traffic jam.'),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.black),
            title: const Text("Road Block"),
            onTap: () {
              setState(() {
                reportingMode = true;
                reportingType = "block";
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tap on the map to report a road block.'),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text("Cancel"),
            onTap: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // 🔍 Suggestions
  Future<List> fetchSuggestions(String query) async {
    if (query.isEmpty) return [];

    // Build a small viewbox around the user's current location to bias results
    final lat = currentLocation.latitude;
    final lon = currentLocation.longitude;
    // ~0.5 degree box (~50km) - adjust if you want tighter/looser bias
    const delta = 0.5;
    final minLon = lon - delta;
    final minLat = lat - delta;
    final maxLon = lon + delta;
    final maxLat = lat + delta;

    // First, try India-limited results so local places appear first
    final indiaUrl =
        "https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}"
        "&format=json&limit=10&addressdetails=1&accept-language=en&countrycodes=in"
        "&lat=$lat&lon=$lon&viewbox=$minLon,$minLat,$maxLon,$maxLat";

    final resIndia = await http.get(
      Uri.parse(indiaUrl),
      headers: {"User-Agent": "ss_maps"},
    );

    final List<dynamic> indiaData = json.decode(resIndia.body) as List<dynamic>;
    final results = <dynamic>[];
    results.addAll(indiaData);

    // If fewer than desired, supplement with global results
    if (results.length < 10) {
      final remaining = 10 - results.length;
      final globalUrl =
          "https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}"
          "&format=json&limit=$remaining&addressdetails=1&accept-language=en"
          "&lat=$lat&lon=$lon&viewbox=$minLon,$minLat,$maxLon,$maxLat";

      final resGlobal = await http.get(
        Uri.parse(globalUrl),
        headers: {"User-Agent": "ss_maps"},
      );

      final List<dynamic> globalData =
          json.decode(resGlobal.body) as List<dynamic>;
      final existing = results.map((e) => e['display_name']).toSet();

      for (var e in globalData) {
        if (!existing.contains(e['display_name'])) results.add(e);
      }
    }

    return results;
  }

  String _shortLocationLabel(String displayName) {
    final parts = displayName
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.length <= 3) {
      return parts.join(', ');
    }

    return parts.take(3).join(', ');
  }

  Future<LatLng?> getCoordinates(String place) async {
    final url =
        "https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(place)}"
        "&format=json&limit=1&addressdetails=1&accept-language=en";

    final res = await http.get(
      Uri.parse(url),
      headers: {"User-Agent": "ss_maps"},
    );

    final data = json.decode(res.body);
    if (data.isEmpty) return null;

    return LatLng(double.parse(data[0]['lat']), double.parse(data[0]['lon']));
  }

  void checkTrafficOnRoute(List<LatLng> route) {
    final distance = Distance();

    trafficWarning = "";

    for (var marker in trafficMarkers) {
      for (var point in route) {
        final meters = distance.as(LengthUnit.Meter, point, marker.point);

        if (meters < 100) {
          setState(() {
            trafficWarning = "⚠ Traffic Incident Found On Your Route";
          });
          return;
        }
      }
    }
  }

  void selectTransport(String transport) {
    setState(() {
      selectedTransport = transport;
      routeProfile = transport;
    });
  }

  double _computeRemainingMeters(List<LatLng> route, LatLng current) {
    if (route.isEmpty) return 0;
    final distance = Distance();
    // find nearest point on route
    int nearestIdx = 0;
    double minDist = double.infinity;
    for (var i = 0; i < route.length; i++) {
      final d = distance.as(LengthUnit.Meter, current, route[i]);
      if (d < minDist) {
        minDist = d;
        nearestIdx = i;
      }
    }

    double total = distance.as(LengthUnit.Meter, current, route[nearestIdx]);
    for (var i = nearestIdx; i < route.length - 1; i++) {
      total += distance.as(LengthUnit.Meter, route[i], route[i + 1]);
    }
    return total;
  }

  void startNavigation() {
    if (routePoints.isEmpty || destinationLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please calculate a route first.')),
      );
      return;
    }

    setState(() {
      isNavigating = true;
      currentStepIndex = 0;
    });

    // Move map to user's current location initially
    mapController.move(currentLocation, 15);

    // Reset live remaining values
    remainingDistanceKm =
        _computeRemainingMeters(routePoints, currentLocation) / 1000;
    // estimate time using simple speed assumptions (km/h)
    double speedKmph = selectedTransport == 'driving-car'
        ? 40
        : selectedTransport == 'cycling-road'
        ? 15
        : 5;
    remainingTimeMin = (remainingDistanceKm / speedKmph) * 60;

    if (isSimulating) {
      // start simulation along routePoints
      _simIndex = 0;
      _simTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_simIndex >= routePoints.length) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Simulation complete — arrived.')),
          );
          stopNavigation();
          return;
        }

        final simulated = routePoints[_simIndex];
        setState(() {
          currentLocation = simulated;
        });
        try {
          mapController.move(simulated, mapController.zoom);
        } catch (_) {}

        remainingDistanceKm =
            _computeRemainingMeters(routePoints, simulated) / 1000;
        remainingTimeMin = (remainingDistanceKm / speedKmph) * 60;

        // close to destination?
        if (destinationLocation != null) {
          final meters = Distance().as(
            LengthUnit.Meter,
            simulated,
            destinationLocation!,
          );
          if (meters < 50) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You have arrived at your destination.'),
              ),
            );
            stopNavigation();
          }
        }

        // advance to next step if close to the end of current step
        if (navSteps.isNotEmpty && currentStepIndex < navSteps.length) {
          try {
            final step = navSteps[currentStepIndex];
            final lastCoord = (step['coords'] as List<LatLng>).last;
            final stepMeters = Distance().as(
              LengthUnit.Meter,
              simulated,
              lastCoord,
            );
            if (stepMeters < 20) {
              setState(() {
                if (currentStepIndex < navSteps.length - 1) currentStepIndex++;
              });
            }
          } catch (_) {}
        }

        _simIndex++;
      });
    } else {
      // Listen to device location updates to follow along the route
      _positionSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(distanceFilter: 5),
          ).listen((pos) {
            final newLoc = LatLng(pos.latitude, pos.longitude);
            setState(() {
              currentLocation = newLoc;
            });

            // center map on user while navigating
            try {
              mapController.move(newLoc, mapController.zoom);
            } catch (_) {}

            // update remaining distance/time
            remainingDistanceKm =
                _computeRemainingMeters(routePoints, newLoc) / 1000;
            double speed = selectedTransport == 'driving-car'
                ? 40
                : selectedTransport == 'cycling-road'
                ? 15
                : 5;
            remainingTimeMin = (remainingDistanceKm / speed) * 60;

            // if close to destination, stop navigation
            if (destinationLocation != null) {
              final meters = Distance().as(
                LengthUnit.Meter,
                newLoc,
                destinationLocation!,
              );
              if (meters < 50) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('You have arrived at your destination.'),
                  ),
                );
                stopNavigation();
              }
            }
            // advance to next step if close to the end of current step
            if (navSteps.isNotEmpty && currentStepIndex < navSteps.length) {
              try {
                final step = navSteps[currentStepIndex];
                final lastCoord = (step['coords'] as List<LatLng>).last;
                final stepMeters = Distance().as(
                  LengthUnit.Meter,
                  newLoc,
                  lastCoord,
                );
                if (stepMeters < 20) {
                  setState(() {
                    if (currentStepIndex < navSteps.length - 1)
                      currentStepIndex++;
                  });
                }
              } catch (_) {}
            }
          });
    }
  }

  void stopNavigation() {
    _positionSub?.cancel();
    _positionSub = null;
    _simTimer?.cancel();
    _simTimer = null;
    setState(() {
      isNavigating = false;
      reportingMode = false;
      reportingType = null;
      remainingDistanceKm = 0;
      remainingTimeMin = 0;
    });
  }

  void showStepsSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Turn-by-turn Directions')),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: navSteps.length,
                  itemBuilder: (c, i) {
                    final step = navSteps[i];
                    final instr = step['instruction'] ?? '';
                    final sd = (step['distance'] ?? 0) / 1000;
                    final st = (step['duration'] ?? 0) / 60;
                    return ListTile(
                      leading: Icon(_iconForInstruction(instr)),
                      title: Text(instr),
                      subtitle: Text(
                        '${sd.toStringAsFixed(2)} km · ${st.toStringAsFixed(0)} min',
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          currentStepIndex = i;
                        });
                        try {
                          final coords = step['coords'] as List<LatLng>;
                          if (coords.isNotEmpty)
                            mapController.move(
                              coords.first,
                              mapController.zoom,
                            );
                        } catch (_) {}
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _iconForInstruction(String instr) {
    final s = instr.toLowerCase();
    if (s.contains('roundabout')) return Icons.circle;
    if (s.contains('left')) return Icons.turn_left;
    if (s.contains('right')) return Icons.turn_right;
    if (s.contains('straight') || s.contains('continue'))
      return Icons.arrow_upward;
    if (s.contains('uturn') || s.contains('u-turn')) return Icons.u_turn_left;
    return Icons.directions;
  }

  String _formatDistance(double km) {
    if (km >= 1) {
      return '${km.toStringAsFixed(1)} km';
    }
    return '${(km * 1000).toStringAsFixed(0)} m';
  }

  String _formatDuration(double minutes) {
    final int hrs = minutes ~/ 60;
    final int mins = (minutes % 60).round();
    if (hrs > 0) {
      return '${hrs}h ${mins}m';
    }
    return '${mins} min';
  }

  Widget _buildNavigationHud() {
    final step = navSteps.isNotEmpty && currentStepIndex < navSteps.length
        ? navSteps[currentStepIndex]
        : null;
    final instruction = step != null
        ? step['instruction'] as String? ?? 'Follow the route'
        : 'Follow the route';
    final stepDistance = step != null ? (step['distance'] ?? 0) / 1000 : 0.0;
    final stepDuration = step != null ? (step['duration'] ?? 0) / 60 : 0.0;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 14,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Navigation mode',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_formatDistance(remainingDistanceKm)} · ${_formatDuration(remainingTimeMin)}',
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: stopNavigation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Stop'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusChip(
                  icon: selectedTransport == 'driving-car'
                      ? Icons.directions_car
                      : selectedTransport == 'cycling-road'
                          ? Icons.pedal_bike
                          : Icons.directions_walk,
                  label: selectedTransport == 'driving-car'
                      ? 'Driving'
                      : selectedTransport == 'cycling-road'
                          ? 'Cycling'
                          : 'Walking',
                ),
                _buildStatusChip(
                  icon: Icons.access_time,
                  label: _formatDuration(remainingTimeMin),
                ),
                _buildStatusChip(
                  icon: trafficWarning.isEmpty ? Icons.traffic : Icons.warning,
                  label: trafficWarning.isEmpty ? 'Traffic clear' : 'Traffic alert',
                  color: trafficWarning.isEmpty ? Colors.green : Colors.orange,
                ),
                if (isSimulating)
                  _buildStatusChip(
                    icon: Icons.speed,
                    label: 'Simulation',
                    color: Colors.blue,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _iconForInstruction(instruction),
                    size: 28,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        instruction,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        step != null
                            ? '${currentStepIndex + 1}/${navSteps.length} · ${_formatDistance(stepDistance)} · ${_formatDuration(stepDuration)}'
                            : 'Route in progress',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String label,
    Color color = Colors.black54,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationControls() {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 14,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current step',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  navSteps.isNotEmpty && currentStepIndex < navSteps.length
                      ? 'Step ${currentStepIndex + 1} of ${navSteps.length}'
                      : 'Step 1 of 1',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: showStepsSheet,
              icon: const Icon(Icons.list, size: 18),
              label: const Text('Steps'),
            ),
          ],
        ),
      ),
    );
  }

  // 🛣️ Route
  Future<void> getRoute() async {
    LatLng? source;

    if (useCurrentLocation) {
      source = currentLocation;
    } else {
      source = await getCoordinates(sourceController.text);
    }

    final dest = await getCoordinates(destController.text);

    if (source == null || dest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter valid locations")),
      );
      return;
    }

    setState(() {
      sourceLocation = source;
      destinationLocation = dest;
    });

    final url =
        "https://api.openrouteservice.org/v2/directions/$routeProfile"
        "?api_key=$routeApiKey"
        "&start=${source.longitude},${source.latitude}"
        "&end=${dest.longitude},${dest.latitude}"
        "&preference=fastest"
        "&format=json";

    final res = await http.get(Uri.parse(url));

    final data = json.decode(res.body);
    final features = data['features'] as List<dynamic>? ?? [];

    if (features.isEmpty) {
      return;
    }

    final feature = features.first;
    final coords = feature['geometry']['coordinates'] as List<dynamic>;
    final route = coords.map<LatLng>((e) => LatLng(e[1], e[0])).toList();
    final summary = feature['properties']['summary'];
    final distance = summary['distance'] / 1000;
    final time = summary['duration'] / 60;

    final stepsList = <Map<String, dynamic>>[];
    try {
      final segments = feature['properties']['segments'] as List<dynamic>? ?? [];
      for (var seg in segments) {
        final ssteps = seg['steps'] as List<dynamic>? ?? [];
        for (var st in ssteps) {
          final instr = st['instruction'] ?? (st['name'] ?? '');
          final sd = st['distance'] ?? 0;
          final stime = st['duration'] ?? 0;
          List<LatLng> coordsForStep = [];
          if (st['way_points'] != null) {
            final wp = st['way_points'] as List<dynamic>;
            int startIdx = wp.isNotEmpty ? (wp[0] as int) : 0;
            int endIdx = wp.length > 1 ? (wp[1] as int) : startIdx;
            if (startIdx < 0) startIdx = 0;
            if (endIdx >= route.length) endIdx = route.length - 1;
            if (startIdx <= endIdx) {
              coordsForStep = route.sublist(startIdx, endIdx + 1);
            }
          }

          stepsList.add({
            'instruction': instr,
            'distance': sd,
            'duration': stime,
            'coords': coordsForStep,
          });
        }
      }
    } catch (_) {}

    setState(() {
      routePoints = route;
      distanceKm = distance;
      durationMin = time;
      navSteps = stepsList;
      currentStepIndex = 0;
    });

    checkTrafficOnRoute(routePoints);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("SS Maps 🚦")),
      floatingActionButton: isNavigating
          ? FloatingActionButton(
              onPressed: openReportMenu,
              child: const Icon(Icons.report),
            )
          : null,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Material(
                    color: Theme.of(context).colorScheme.primary,
                    child: TabBar(
                      onTap: (index) {
                        setState(() {
                          selectedTabIndex = index;
                        });
                      },
                      tabs: const [
                        Tab(icon: Icon(Icons.map), text: 'Map'),
                        Tab(icon: Icon(Icons.settings), text: 'Settings'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        Stack(
                          children: [
                            FlutterMap(
                              mapController: mapController,
                              options: MapOptions(
                                initialCenter: currentLocation,
                                initialZoom: 13,
                                onTap: (tapPos, point) {
                                  if (reportingMode) {
                                    reportIncident(point);
                                  }
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: mapStyles[mapStyle]!['url'] as String,
                                  subdomains:
                                      (mapStyles[mapStyle]!['subdomains'] as List<String>?) ??
                                          [],
                                  userAgentPackageName: 'ss_maps',
                                ),
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: routePoints,
                                      color: Colors.blue,
                                      strokeWidth: 5,
                                    ),
                                  ],
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: currentLocation,
                                      width: 80,
                                      height: 80,
                                      child: const Icon(
                                        Icons.location_pin,
                                        color: Colors.red,
                                        size: 40,
                                      ),
                                    ),
                                    if (sourceLocation != null)
                                      Marker(
                                        point: sourceLocation!,
                                        width: 60,
                                        height: 60,
                                        child: const Icon(
                                          Icons.location_on,
                                          color: Colors.green,
                                          size: 40,
                                        ),
                                      ),
                                    if (destinationLocation != null)
                                      Marker(
                                        point: destinationLocation!,
                                        width: 60,
                                        height: 60,
                                        child: const Icon(
                                          Icons.flag,
                                          color: Colors.blue,
                                          size: 40,
                                        ),
                                      ),
                                    ...trafficMarkers,
                                  ],
                                ),
                              ],
                            ),
                            if (reportingMode)
                              Positioned(
                                top: 15,
                                left: 15,
                                right: 15,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.yellow.shade700,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.12),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.report, color: Colors.black),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Tap on the map to report a $reportingType.',
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (isNavigating) ...[
                              Positioned(
                                top: 15,
                                left: 15,
                                child: GestureDetector(
                                  onTap: stopNavigation,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.95),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.12),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.arrow_back, size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          'Back',
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 80,
                                left: 16,
                                right: 16,
                                child: _buildNavigationHud(),
                              ),
                              Positioned(
                                bottom: 16,
                                left: 16,
                                right: 16,
                                child: _buildNavigationControls(),
                              ),
                            ],
                            if (!isNavigating)
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  constraints: const BoxConstraints(maxHeight: 420),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(20),
                                      topRight: Radius.circular(20),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.12),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                  child: SingleChildScrollView(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          CheckboxListTile(
                                            title: const Text("Use My Current Location"),
                                            value: useCurrentLocation,
                                            onChanged: (value) {
                                              setState(() {
                                                useCurrentLocation = value ?? false;
                                              });
                                            },
                                          ),
                                          const SizedBox(height: 12),
                                          if (!useCurrentLocation) ...[
                                            TextField(
                                              controller: sourceController,
                                              decoration: InputDecoration(
                                                labelText: "Enter Source",
                                                border: const OutlineInputBorder(),
                                                suffixIcon: sourceController.text.isNotEmpty
                                                    ? IconButton(
                                                        icon: const Icon(Icons.clear),
                                                        onPressed: () {
                                                          sourceController.clear();
                                                          setState(() {
                                                            sourceSuggestions = [];
                                                            sourceLocation = null;
                                                          });
                                                        },
                                                      )
                                                    : null,
                                              ),
                                              onChanged: (v) async {
                                                final r = await fetchSuggestions(v);
                                                setState(() {
                                                  sourceSuggestions = r;
                                                });
                                              },
                                            ),
                                            ...sourceSuggestions.map(
                                              (e) => ListTile(
                                                title: Text(_shortLocationLabel(e['display_name'])),
                                                onTap: () {
                                                  sourceController.text = _shortLocationLabel(
                                                    e['display_name'],
                                                  );
                                                  setState(() {
                                                    sourceSuggestions = [];
                                                  });
                                                },
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                          ],
                                          TextField(
                                            controller: destController,
                                            decoration: InputDecoration(
                                              labelText: "Enter Destination",
                                              border: const OutlineInputBorder(),
                                              suffixIcon: destController.text.isNotEmpty
                                                  ? IconButton(
                                                      icon: const Icon(Icons.clear),
                                                      onPressed: () {
                                                        destController.clear();
                                                        setState(() {
                                                          destSuggestions = [];
                                                          destinationLocation = null;
                                                        });
                                                      },
                                                    )
                                                  : null,
                                            ),
                                            onChanged: (v) async {
                                              final r = await fetchSuggestions(v);
                                              setState(() => destSuggestions = r);
                                            },
                                          ),
                                          ...destSuggestions.map(
                                            (e) => ListTile(
                                              title: Text(_shortLocationLabel(e['display_name'])),
                                              onTap: () {
                                                destController.text = _shortLocationLabel(
                                                  e['display_name'],
                                                );
                                                setState(() => destSuggestions = []);
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'Mode of Travel',
                                            style: TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                                            children: [
                                              ChoiceChip(
                                                label: const Text("🚗 Car"),
                                                selected: selectedTransport == "driving-car",
                                                onSelected: (v) {
                                                  selectTransport("driving-car");
                                                },
                                              ),
                                              ChoiceChip(
                                                label: const Text("🏍 Bike"),
                                                selected: selectedTransport == "cycling-road",
                                                onSelected: (v) {
                                                  selectTransport("cycling-road");
                                                },
                                              ),
                                              ChoiceChip(
                                                label: const Text("🚶 Walk"),
                                                selected: selectedTransport == "foot-walking",
                                                onSelected: (v) {
                                                  selectTransport("foot-walking");
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          ElevatedButton(
                                            onPressed: getRoute,
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(vertical: 14),
                                              child: Text("Find Route"),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          ElevatedButton(
                                            onPressed: routePoints.isEmpty
                                                ? null
                                                : isNavigating
                                                    ? stopNavigation
                                                    : startNavigation,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: routePoints.isEmpty
                                                  ? Colors.grey
                                                  : null,
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 14),
                                              child: Text(
                                                isNavigating ? 'STOP NAVIGATION' : 'START NAVIGATION',
                                              ),
                                            ),
                                          ),
                                          if (distanceKm > 0) ...[
                                            const SizedBox(height: 16),
                                            Card(
                                            elevation: 4,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(18),
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          const Text(
                                                            'Route Summary',
                                                            style: TextStyle(
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: 16,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 6),
                                                          Text(
                                                            '${distanceKm.toStringAsFixed(1)} km · ${durationMin.toStringAsFixed(0)} min',
                                                            style: const TextStyle(
                                                              fontSize: 14,
                                                              color: Colors.black87,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 6,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: trafficWarning.isEmpty
                                                              ? Colors.green.shade50
                                                              : Colors.orange.shade50,
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              trafficWarning.isEmpty ? Icons.check_circle : Icons.warning,
                                                              color: trafficWarning.isEmpty ? Colors.green : Colors.orange,
                                                              size: 18,
                                                            ),
                                                            const SizedBox(width: 6),
                                                            Text(
                                                              trafficWarning.isEmpty
                                                                  ? 'Clear route'
                                                                  : 'Traffic alert',
                                                              style: TextStyle(
                                                                color: trafficWarning.isEmpty ? Colors.green.shade800 : Colors.orange.shade800,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 14),
                                                  Text(
                                                    trafficWarning.isEmpty
                                                        ? 'Best route based on current traffic and incidents.'
                                                        : trafficWarning,
                                                    style: TextStyle(
                                                      color: Colors.grey.shade700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Map Style',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  children: mapStyles.keys.map((style) {
                                    final styleData = mapStyles[style]!;
                                    return ChoiceChip(
                                      label: Text(styleData['label'] as String),
                                      selected: mapStyle == style,
                                      onSelected: (_) {
                                        setState(() {
                                          mapStyle = style;
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  'Simulation',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Expanded(child: Text('Enable route simulation')),
                                    Switch(
                                      value: isSimulating,
                                      onChanged: (v) {
                                        setState(() {
                                          isSimulating = v;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  'Share Route',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: shareRoute,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 14),
                                    child: Text('Share Route'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void shareRoute() async {
    if (destinationLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please calculate a route before sharing.'),
        ),
      );
      return;
    }

    final origin = useCurrentLocation
        ? '${currentLocation.latitude},${currentLocation.longitude}'
        : sourceLocation != null
            ? '${sourceLocation!.latitude},${sourceLocation!.longitude}'
            : sourceController.text.isNotEmpty
                ? sourceController.text
                : null;

    if (origin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set a route origin before sharing.'),
        ),
      );
      return;
    }

    final destination = destController.text.isNotEmpty
        ? destController.text
        : '${destinationLocation!.latitude},${destinationLocation!.longitude}';

    final url =
        'https://www.google.com/maps/dir/?api=1&origin=${Uri.encodeComponent(origin)}&destination=${Uri.encodeComponent(destination)}&travelmode=${Uri.encodeComponent(selectedTransport == 'foot-walking' ? 'walking' : selectedTransport == 'cycling-road' ? 'bicycling' : 'driving')}';

    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open sharing link.')),
        );
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open sharing link.')),
      );
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _simTimer?.cancel();
    super.dispose();
  }
}
