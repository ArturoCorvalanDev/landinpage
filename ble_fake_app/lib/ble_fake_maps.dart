import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// import 'package:geolocator/geolocator.dart'; // Geolocalización real (comentada a petición)
import 'clases.dart';
import 'package:latlong2/latlong.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'services/local_notifications.dart';
import 'screens/nearby_witnesses_page.dart';

class BleFakeMaps extends StatefulWidget {
  const BleFakeMaps({super.key});

  @override
  State<BleFakeMaps> createState() => _BleFakeMapsState();
}

class _BleFakeMapsState extends State<BleFakeMaps> {
  static const LatLng _vinaCenter = LatLng(-33.0245, -71.5518);

  late LatLng disappearancePoint;
  late LatLng reappearPoint;

  final Distance distance = const Distance();

  List<FakeDevice>? fakeDevices;

  Timer? _timer;
  Timer? _disappearanceTicker;
  final Random rng = Random();

  final MapController mapController = MapController();

  // StreamSubscription<Position>? positionStream; // geolocalización real (comentada)
  LatLng? userLocation;
  late StreamSubscription connectivitySub;
  bool _skipFirstConnectivityEvent = true;

  final List<LatLng> simulatedRoute = [];

  int _unreadAlerts = 0;
  final List<Map<String, dynamic>> _alerts = [];

  final List<Timer> _deviceReappearTimers = [];
  final Set<String> _scheduledReappearIds = {};

  bool isKidnapActive = false;
  List<LatLng> kidnapRoute = [];
  int kidnapStep = 0;
  Timer? _kidnapTimer;
  LatLng? kidnapStartA;
  LatLng? kidnapEndB;
  LatLng? kidnapCurrentPos;
  FakeDevice? kidnappedDeviceRef;

  @override
  void initState() {
    super.initState();

    userLocation = _vinaCenter;
    _createFakeDevices();

    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _updateFakeDevices());

    _disappearanceTicker = Timer.periodic(const Duration(minutes: 1), (_) => _disappearOneDevice());

    connectivitySub = Connectivity().onConnectivityChanged.listen((res) {
      final ConnectivityResult result = res is List ? res.first : res as ConnectivityResult;
      if (_skipFirstConnectivityEvent) {
        _skipFirstConnectivityEvent = false;
        return;
      }
      handleConnectivityChange(result);
    });

    // _startTrackingUser(); // Geolocalización real (comentada)
  }

  void handleConnectivityChange(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.none:
        simulateUserDisappearance();
        break;
      case ConnectivityResult.mobile:
        break;
      case ConnectivityResult.wifi:
        simulateUserAppearance();
        break;
      default:
    }
  }

  @override
  void dispose() {
    _disappearanceTicker?.cancel();
    for (final t in _deviceReappearTimers) {
      t.cancel();
    }
    _deviceReappearTimers.clear();
    _scheduledReappearIds.clear();

    _kidnapTimer?.cancel();
    _timer?.cancel();
    // positionStream?.cancel();
    connectivitySub.cancel();
    super.dispose();
  }

  void _createFakeDevices() {
    fakeDevices = List.generate(30, (i) {
      final double bearing = rng.nextDouble() * 360;
      final double meters = 5 + rng.nextDouble() * 80;
      final LatLng d = distance.offset(userLocation!, meters, bearing);
      return FakeDevice(
        id: 'FAKE:${i + 1}',
        name: 'Device ${i + 1}',
        lat: d.latitude,
        lng: d.longitude,
        rssi: _metersToRssi(meters),
      );
    });
  }

  static int _metersToRssi(double meters) {
    if (meters < 1) return -30;
    if (meters > 120) return -100;
    final double t = (meters / 120).clamp(0.0, 1.0);
    return (-30 - 70 * t).round();
  }

  void _updateFakeDevices() {
    if (userLocation == null || fakeDevices == null || fakeDevices!.isEmpty) return;

    setState(() {
      for (final FakeDevice dev in fakeDevices!) {
        final double bearing = rng.nextDouble() * 360;
        final double step = rng.nextDouble() * 10 - 5;
        final LatLng newPos = distance.offset(LatLng(dev.lat, dev.lng), step.abs(), bearing);

        dev.lat = newPos.latitude;
        dev.lng = newPos.longitude;

        final double metersToUser = distance(LatLng(dev.lat, dev.lng), userLocation!);
        dev.rssi = _metersToRssi(metersToUser);
      }

      if (rng.nextDouble() < 0.08) {
        final int i = fakeDevices!.length + 1;
        final double bearing = rng.nextDouble() * 360;
        final double meters = 5 + rng.nextDouble() * 80;
        final LatLng d = distance.offset(userLocation!, meters, bearing);
        fakeDevices!.add(
          FakeDevice(id: 'FAKE:$i', name: 'Device $i', lat: d.latitude, lng: d.longitude, rssi: _metersToRssi(meters)),
        );
      }
    });
  }

  void _disappearOneDevice() {
    if (fakeDevices == null || fakeDevices!.isEmpty) return;

    final int indexToRemove = rng.nextInt(fakeDevices!.length);
    final FakeDevice disappearingDevice = fakeDevices![indexToRemove];

    final List<FakeDevice> witnesses = fakeDevices!
        .where((d) => d.id != disappearingDevice.id)
        .toList()
      ..sort((a, b) {
        final double da = distance(LatLng(a.lat, a.lng), LatLng(disappearingDevice.lat, disappearingDevice.lng));
        final double db = distance(LatLng(b.lat, b.lng), LatLng(disappearingDevice.lat, disappearingDevice.lng));
        return da.compareTo(db);
      });

    final List<FakeDevice> top10Witnesses = witnesses.take(10).toList();
    final String? nearestWitnessId = top10Witnesses.isNotEmpty ? top10Witnesses.first.id : null;

    _notifyDeviceDisappeared(disappearingDevice, top10Witnesses);

    setState(() {
      fakeDevices!.removeAt(indexToRemove);
    });

    _scheduleDeviceReappearanceAt30m(disappearingDevice, nearestWitnessId, delaySeconds: 60);
  }

  double _distanceToUser(FakeDevice d) => distance(LatLng(d.lat, d.lng), userLocation!);

  void _moveCameraToUser(MapController controller) {
    controller.move(userLocation!, 18);
  }

  void simulateUserDisappearance() {
    if (fakeDevices == null) return;

    const double snapshotRange = 100;
    final List<FakeDevice> snapshot = fakeDevices!.where((d) {
      final double dist = distance(LatLng(d.lat, d.lng), userLocation!);
      return dist <= snapshotRange;
    }).toList();

    disappearancePoint = userLocation!;

    final double bearing = rng.nextDouble() * 360;
    final LatLng predictedB = distance.offset(disappearancePoint, 30, bearing);

    final List<Map<String, double>> route = [];
    const int steps = 10;
    for (int i = 0; i <= steps; i++) {
      final double lat = disappearancePoint.latitude + (predictedB.latitude - disappearancePoint.latitude) * (i / steps);
      final double lng = disappearancePoint.longitude + (predictedB.longitude - disappearancePoint.longitude) * (i / steps);
      route.add({'lat': lat, 'lng': lng});
    }

    final Map<String, dynamic> payload = {
      'type': 'disappearance',
      'eventLat': predictedB.latitude,
      'eventLng': predictedB.longitude,
      'fromLat': disappearancePoint.latitude,
      'fromLng': disappearancePoint.longitude,
      'route': route,
      'witnesses': snapshot.map((d) {
        final double distM = distance(LatLng(d.lat, d.lng), disappearancePoint);
        return {'id': d.id, 'name': d.name, 'lat': d.lat, 'lng': d.lng, 'dist': distM};
      }).toList(),
    };

    LocalNotifications.instance.showNow(
      id: 1001,
      title: 'Dispositivo desaparecido',
      body: 'Punto B previsto marcado. Toque para ver ruta y testigos',
      payload: payload,
    );

    setState(() {});
  }

  void simulateUserAppearance({int reappearAfterSeconds = 1, double reappearDistanceMeters = 200}) {
    Future.delayed(Duration(seconds: reappearAfterSeconds), () {
      final double bearing = rng.nextDouble() * 360;
      final LatLng newPos = distance.offset(disappearancePoint, reappearDistanceMeters, bearing);

      reappearPoint = LatLng(newPos.latitude, newPos.longitude);
      userLocation = LatLng(newPos.latitude, newPos.longitude);

      if (fakeDevices != null) {
        final List<FakeDevice> nearbyAtReappear = fakeDevices!.where((d) {
          final double dist = distance(LatLng(d.lat, d.lng), newPos);
          return dist <= 100;
        }).toList();

        _notifyUserAppeared(nearbyAtReappear, newPos);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          mapController.move(LatLng(userLocation!.latitude, userLocation!.longitude), 18);
        } catch (_) {}
      });

      generateRoute();
    });
  }

  void generateRoute() {
    const int steps = 5;
    for (int i = 0; i <= steps; i++) {
      final double lat = disappearancePoint.latitude + (reappearPoint.latitude - disappearancePoint.latitude) * (i / steps);
      final double lng = disappearancePoint.longitude + (reappearPoint.longitude - disappearancePoint.longitude) * (i / steps);
      simulatedRoute.add(LatLng(lat, lng));
    }
    setState(() {});
  }

  void _addAlert({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
  }) {
    _alerts.insert(0, {
      'title': title,
      'body': body,
      'payload': payload,
      'ts': DateTime.now(),
    });
    _unreadAlerts++;
    setState(() {});
  }

  void _showAlertsSheet() {
    if (_alerts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sin alertas')));
      return;
    }
    setState(() {
      _unreadAlerts = 0;
    });

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return ListView.separated(
          itemCount: _alerts.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final Map<String, dynamic> a = _alerts[index];
            return ListTile(
              leading: const Icon(Icons.notifications_active),
              title: Text(a['title'] as String),
              subtitle: Text(a['body'] as String),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final Map<String, dynamic> payload = a['payload'] as Map<String, dynamic>;
                Navigator.of(context).push(NearbyWitnessesPage.fromPayload(jsonEncode(payload)));
              },
            );
          },
        );
      },
    );
  }

  void _scheduleDeviceReappearanceAt30m(
    FakeDevice disappeared,
    String? nearestWitnessId, {
    int delaySeconds = 60,
  }) {
    if (_scheduledReappearIds.contains(disappeared.id)) return;
    _scheduledReappearIds.add(disappeared.id);

    final LatLng pointA = LatLng(disappeared.lat, disappeared.lng);
    final double bearing = rng.nextDouble() * 360;
    final LatLng pointB = distance.offset(pointA, 30, bearing);

    final Timer timer = Timer(Duration(seconds: delaySeconds), () {
      final FakeDevice reappeared = FakeDevice(
        id: disappeared.id,
        name: disappeared.name,
        lat: pointB.latitude,
        lng: pointB.longitude,
        rssi: _metersToRssi(userLocation == null ? 50.0 : distance(pointB, userLocation!)),
      );

      FakeDevice? movedWitness;
      if (nearestWitnessId != null && fakeDevices != null) {
        final int idx = fakeDevices!.indexWhere((d) => d.id == nearestWitnessId);
        if (idx != -1) {
          final double witnessOffset = 5 + rng.nextDouble() * 5; // 5–10 m
          final double witnessBearing = rng.nextDouble() * 360;
          final LatLng around = distance.offset(pointB, witnessOffset, witnessBearing);
          fakeDevices![idx].lat = around.latitude;
          fakeDevices![idx].lng = around.longitude;
          fakeDevices![idx].rssi = _metersToRssi(userLocation == null ? 50.0 : distance(around, userLocation!));
          movedWitness = fakeDevices![idx];
        }
      }

      setState(() {
        fakeDevices?.add(reappeared);
      });

      _notifyDeviceReappeared(reappeared, movedWitness, pointA);

      _scheduledReappearIds.remove(disappeared.id);
    });

    _deviceReappearTimers.add(timer);
  }

  Future<void> _notifyDeviceReappeared(FakeDevice device, FakeDevice? witness, LatLng fromPoint) async {
    final LatLng toPoint = LatLng(device.lat, device.lng);

    final List<Map<String, double>> route = [];
    const int steps = 10;
    for (int i = 0; i <= steps; i++) {
      final double lat = fromPoint.latitude + (toPoint.latitude - fromPoint.latitude) * (i / steps);
      final double lng = fromPoint.longitude + (toPoint.longitude - fromPoint.longitude) * (i / steps);
      route.add({'lat': lat, 'lng': lng});
    }

    final List<Map<String, dynamic>> witnessesPayload = [];
    String bodyText = 'Reapareció: ${device.name} • Toque para ver ruta';

    if (witness != null) {
      final double distM = distance(LatLng(witness.lat, witness.lng), toPoint);
      witnessesPayload.add({
        'id': witness.id,
        'name': witness.name,
        'lat': witness.lat,
        'lng': witness.lng,
        'dist': distM,
      });
      bodyText = 'Reapareció: ${device.name} • Con ${witness.name} a ${distM.toStringAsFixed(1)} m';
    }

    final Map<String, dynamic> payload = {
      'type': 'device_reappeared',
      'deviceName': device.name,
      'deviceId': device.id,
      'eventLat': toPoint.latitude,
      'eventLng': toPoint.longitude,
      'fromLat': fromPoint.latitude,
      'fromLng': fromPoint.longitude,
      'route': route,
      'witnesses': witnessesPayload,
    };

    await LocalNotifications.instance.showNow(
      id: device.id.hashCode ^ 0x1A2B3C,
      title: 'Dispositivo reapareció',
      body: bodyText,
      payload: payload,
    );

    _addAlert(
      title: 'Dispositivo reapareció',
      body: bodyText,
      payload: payload,
    );
  }

  Future<void> _notifyDeviceDisappeared(FakeDevice desaparecido, List<FakeDevice> witnesses) async {
    final LatLng pointA = LatLng(desaparecido.lat, desaparecido.lng);

    final double bearing = rng.nextDouble() * 360;
    final LatLng pointB = distance.offset(pointA, 30, bearing);

    final List<Map<String, double>> route = [];
    const int steps = 10;
    for (int i = 0; i <= steps; i++) {
      final double lat = pointA.latitude + (pointB.latitude - pointA.latitude) * (i / steps);
      final double lng = pointA.longitude + (pointB.longitude - pointA.longitude) * (i / steps);
      route.add({'lat': lat, 'lng': lng});
    }

    String bodyText = 'Dispositivo: ${desaparecido.name} • Punto B previsto • ${witnesses.length} testigos';
    if (witnesses.isNotEmpty) {
      final FakeDevice nearest = witnesses.first;
      final double nearestDist = distance(LatLng(nearest.lat, nearest.lng), pointA);
      bodyText =
        'Desapareció: ${desaparecido.name} • Más cercano: ${nearest.name} a ${nearestDist.toStringAsFixed(1)} m • Punto B previsto';
    }

    final Map<String, dynamic> payload = {
      'type': 'device_disappeared',
      'deviceName': desaparecido.name,
      'deviceId': desaparecido.id,
      'eventLat': pointB.latitude,
      'eventLng': pointB.longitude,
      'fromLat': pointA.latitude,
      'fromLng': pointA.longitude,
      'route': route,
      'witnesses': witnesses.map((d) {
        final double distM = distance(LatLng(d.lat, d.lng), pointA);
        return {
          'id': d.id,
          'name': d.name,
          'lat': d.lat,
          'lng': d.lng,
          'dist': distM,
        };
      }).toList(),
    };

    await LocalNotifications.instance.showNow(
      id: desaparecido.id.hashCode & 0x7fffffff,
      title: 'Desapareció: ${desaparecido.name}',
      body: bodyText,
      payload: payload,
    );

    _addAlert(
      title: 'Desapareció: ${desaparecido.name}',
      body: bodyText,
      payload: payload,
    );
  }

  Future<void> _notifyUserAppeared(List<FakeDevice> nearbyAtReappear, LatLng newPos) async {
    final LatLng fromPoint = disappearancePoint;
    final LatLng toPoint = newPos;

    final List<Map<String, double>> route = [];
    const int steps = 10;
    for (int i = 0; i <= steps; i++) {
      final double lat = fromPoint.latitude + (toPoint.latitude - fromPoint.latitude) * (i / steps);
      final double lng = fromPoint.longitude + (toPoint.longitude - fromPoint.longitude) * (i / steps);
      route.add({'lat': lat, 'lng': lng});
    }

    final Map<String, dynamic> payload = {
      'type': 'appearance',
      'eventLat': toPoint.latitude,
      'eventLng': toPoint.longitude,
      'fromLat': fromPoint.latitude,
      'fromLng': fromPoint.longitude,
      'route': route,
      'witnesses': nearbyAtReappear.map((d) {
        final double distM = distance(LatLng(d.lat, d.lng), toPoint);
        return {'id': d.id, 'name': d.name, 'lat': d.lat, 'lng': d.lng, 'dist': distM};
      }).toList(),
    };

    await LocalNotifications.instance.showNow(
      id: 1002,
      title: 'Dispositivo reapareció',
      body: 'Toque para ver ruta y testigos cercanos',
      payload: payload,
    );

    _addAlert(
      title: 'Dispositivo reapareció',
      body: 'Toque para ver ruta y testigos cercanos',
      payload: payload,
    );
  }

  List<LatLng> _buildRoute(LatLng from, LatLng to, {int steps = 60}) {
    final List<LatLng> pts = [];
    for (int i = 0; i <= steps; i++) {
      final double lat = from.latitude + (to.latitude - from.latitude) * (i / steps);
      final double lng = from.longitude + (to.longitude - from.longitude) * (i / steps);
      pts.add(LatLng(lat, lng));
    }
    return pts;
  }

  void startKidnapScenario() {
    if (isKidnapActive || fakeDevices == null || fakeDevices!.isEmpty) return;

    fakeDevices!.sort((a, b) {
      final da = distance(LatLng(a.lat, a.lng), userLocation!);
      final db = distance(LatLng(b.lat, b.lng), userLocation!);
      return da.compareTo(db);
    });
    kidnappedDeviceRef = fakeDevices!.first;

    kidnapStartA = LatLng(kidnappedDeviceRef!.lat, kidnappedDeviceRef!.lng);
    final double bearing = rng.nextDouble() * 360;
    kidnapEndB = distance.offset(kidnapStartA!, 3000, bearing);

    kidnapRoute = _buildRoute(kidnapStartA!, kidnapEndB!, steps: 90);
    kidnapStep = 0;
    kidnapCurrentPos = kidnapRoute.first;
    isKidnapActive = true;

    fakeDevices!.removeWhere((d) => d.id == kidnappedDeviceRef!.id);

    final payload = {
      'type': 'kidnap_start',
      'deviceName': kidnappedDeviceRef!.name,
      'deviceId': kidnappedDeviceRef!.id,
      'fromLat': kidnapStartA!.latitude,
      'fromLng': kidnapStartA!.longitude,
      'eventLat': kidnapEndB!.latitude,
      'eventLng': kidnapEndB!.longitude,
      'route': kidnapRoute.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      'witnesses': _nearestWitnessesTo(kidnapStartA!, limit: 10),
    };
    LocalNotifications.instance.showNow(
      id: kidnappedDeviceRef!.id.hashCode ^ 0x55AA,
      title: 'Secuestro iniciado',
      body: 'Victima: ${kidnappedDeviceRef!.name} • Trazando ruta A→B',
      payload: payload,
    );
    _addAlert(title: 'Secuestro iniciado', body: 'Victima: ${kidnappedDeviceRef!.name}', payload: payload);

    _kidnapTimer?.cancel();
    _kidnapTimer = Timer.periodic(const Duration(seconds: 2), (_) => _advanceKidnapStep());
    setState(() {});
  }

  void _advanceKidnapStep() {
    if (!isKidnapActive || kidnapRoute.isEmpty) return;

    kidnapStep = (kidnapStep + 1).clamp(0, kidnapRoute.length - 1);
    kidnapCurrentPos = kidnapRoute[kidnapStep];

    if (kidnapStep % 15 == 0 && kidnapStep != kidnapRoute.length - 1) {
      final payload = {
        'type': 'kidnap_update',
        'deviceName': kidnappedDeviceRef?.name,
        'deviceId': kidnappedDeviceRef?.id,
        'fromLat': kidnapStartA?.latitude,
        'fromLng': kidnapStartA?.longitude,
        'eventLat': kidnapEndB?.latitude,
        'eventLng': kidnapEndB?.longitude,
        'route': kidnapRoute.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
        'witnesses': _nearestWitnessesTo(kidnapCurrentPos!, limit: 10),
      };
      LocalNotifications.instance.showNow(
        id: (kidnappedDeviceRef?.id.hashCode ?? 0) ^ 0x99CC,
        title: 'Secuestro: actualización',
        body: 'Posición intermedia • Ruta A→B activa',
        payload: payload,
      );
      _addAlert(title: 'Secuestro: actualización', body: 'Ruta A→B activa', payload: payload);
    }

    if (kidnapStep == kidnapRoute.length - 1) {
      _endKidnapScenario();
    }

    setState(() {});
  }

  void _endKidnapScenario() {
    _kidnapTimer?.cancel();
    _kidnapTimer = null;

    if (kidnappedDeviceRef != null && kidnapEndB != null) {
      final d = kidnappedDeviceRef!;
      final LatLng at = kidnapEndB!;
      fakeDevices?.add(FakeDevice(
        id: d.id,
        name: d.name,
        lat: at.latitude,
        lng: at.longitude,
        rssi: _metersToRssi(userLocation == null ? 50.0 : distance(at, userLocation!)),
      ));
    }

    final payload = {
      'type': 'kidnap_end',
      'deviceName': kidnappedDeviceRef?.name,
      'deviceId': kidnappedDeviceRef?.id,
      'fromLat': kidnapStartA?.latitude,
      'fromLng': kidnapStartA?.longitude,
      'eventLat': kidnapEndB?.latitude,
      'eventLng': kidnapEndB?.longitude,
      'route': kidnapRoute.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      'witnesses': _nearestWitnessesTo(kidnapEndB!, limit: 10),
    };
    LocalNotifications.instance.showNow(
      id: (kidnappedDeviceRef?.id.hashCode ?? 0) ^ 0xDEAD,
      title: 'Secuestro finalizado',
      body: 'Aparición en Punto B • Ver ruta y testigos',
      payload: payload,
    );
    _addAlert(title: 'Secuestro finalizado', body: 'Aparición en Punto B', payload: payload);

    isKidnapActive = false;
    kidnapRoute = [];
    kidnapStep = 0;
    kidnapCurrentPos = null;
    kidnapStartA = null;
    kidnapEndB = null;
    kidnappedDeviceRef = null;

    setState(() {});
  }

  List<Map<String, dynamic>> _nearestWitnessesTo(LatLng center, {int limit = 10}) {
    if (fakeDevices == null || fakeDevices!.isEmpty) return [];
    final List<FakeDevice> list = [...fakeDevices!]
      ..sort((a, b) {
        final da = distance(LatLng(a.lat, a.lng), center);
        final db = distance(LatLng(b.lat, b.lng), center);
        return da.compareTo(db);
      });
    return list.take(limit).map((d) {
      final distM = distance(LatLng(d.lat, d.lng), center);
      return {'id': d.id, 'name': d.name, 'lat': d.lat, 'lng': d.lng, 'dist': distM};
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (userLocation == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(isKidnapActive ? Icons.stop_circle_outlined : Icons.emergency),
            tooltip: isKidnapActive ? 'Detener secuestro' : 'Iniciar secuestro',
            onPressed: () {
              if (isKidnapActive) {
                _endKidnapScenario();
              } else {
                startKidnapScenario();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () => _moveCameraToUser(mapController),
            tooltip: 'Centrar en usuario',
          ),
          IconButton(
            onPressed: _showAlertsSheet,
            tooltip: 'Alertas',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none),
                if (_unreadAlerts > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Center(
                        child: Text(
                          _unreadAlerts > 9 ? '9+' : '$_unreadAlerts',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: userLocation!,
                initialZoom: 18,
                minZoom: 3,
                maxZoom: 30,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                ),

                if (isKidnapActive && kidnapRoute.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(points: kidnapRoute, color: Colors.redAccent, strokeWidth: 4),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (kidnapStartA != null)
                      Marker(
                        point: kidnapStartA!,
                        width: 70,
                        height: 70,
                        child: Column(
                          children: [
                            Container(
                              width: 28, height: 28,
                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                              alignment: Alignment.center,
                              child: const Text('A', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 4),
                            const Text('Desaparición', style: TextStyle(fontSize: 10)),
                          ],
                        ),
                      ),
                    if (kidnapEndB != null)
                      Marker(
                        point: kidnapEndB!,
                        width: 70,
                        height: 70,
                        child: Column(
                          children: [
                            Container(
                              width: 28, height: 28,
                              decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                              alignment: Alignment.center,
                              child: const Text('B', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 4),
                            const Text('Aparición', style: TextStyle(fontSize: 10)),
                          ],
                        ),
                      ),
                  ],
                ),
                if (kidnapCurrentPos != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: kidnapCurrentPos!,
                        width: 60,
                        height: 60,
                        child: const Icon(Icons.local_shipping, color: Colors.black87, size: 32),
                      ),
                    ],
                  ),

                if (fakeDevices != null)
                  MarkerLayer(
                    markers: fakeDevices!.map((d) {
                      double minDist = double.infinity;
                      for (final FakeDevice other in fakeDevices!) {
                        if (other.id == d.id) continue;
                        final double distVal = distance(LatLng(d.lat, d.lng), LatLng(other.lat, other.lng));
                        if (distVal < minDist) {
                          minDist = distVal;
                        }
                      }

                      final Color color = minDist < 5
                          ? Colors.red
                          : minDist < 20
                              ? Colors.orange
                              : Colors.green;
                      return Marker(
                        point: LatLng(d.lat, d.lng),
                        width: 60,
                        height: 60,
                        child: Column(
                          children: [
                            Icon(Icons.phone, color: color),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
                              ),
                              child: Text(d.name, style: const TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),

                if (simulatedRoute.isNotEmpty)
                  PolylineLayer(
                    polylines: [Polyline(points: simulatedRoute, color: Colors.blue, strokeWidth: 4)],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}