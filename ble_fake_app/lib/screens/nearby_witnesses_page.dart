import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class WitnessDevice {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double distMeters;

  WitnessDevice({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.distMeters,
  });

  factory WitnessDevice.fromJson(Map<String, dynamic> json) => WitnessDevice(
        id: json['id'] as String,
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        distMeters: (json['dist'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'dist': distMeters,
      };
}

class NearbyWitnessesPage extends StatelessWidget {
  final LatLng eventLocation;     // Punto B
  final List<WitnessDevice> witnesses;
  final LatLng? fromLocation;     // Punto A
  final List<LatLng> routePoints; // Polyline A→B

  const NearbyWitnessesPage({
    super.key,
    required this.eventLocation,
    required this.witnesses,
    this.fromLocation,
    this.routePoints = const <LatLng>[],
  });

  static Route<void> fromPayload(String? payload) {
    Map<String, dynamic> data = {};
    if (payload != null && payload.isNotEmpty) {
      data = jsonDecode(payload) as Map<String, dynamic>;
    }

    final double toLat = (data['eventLat'] as num).toDouble();
    final double toLng = (data['eventLng'] as num).toDouble();
    final LatLng toPoint = LatLng(toLat, toLng);

    LatLng? fromPoint;
    if (data.containsKey('fromLat') && data.containsKey('fromLng')) {
      fromPoint = LatLng(
        (data['fromLat'] as num).toDouble(),
        (data['fromLng'] as num).toDouble(),
      );
    }

    final List<dynamic> raw = (data['witnesses'] as List<dynamic>? ?? <dynamic>[]);
    final List<WitnessDevice> items =
        raw.map((e) => WitnessDevice.fromJson(e as Map<String, dynamic>)).toList()
          ..sort((a, b) => a.distMeters.compareTo(b.distMeters));

    final List<LatLng> route = [];
    if (data['route'] is List) {
      for (final dynamic p in (data['route'] as List)) {
        if (p is Map) {
          final double lat = (p['lat'] as num).toDouble();
          final double lng = (p['lng'] as num).toDouble();
          route.add(LatLng(lat, lng));
        }
      }
    } else if (fromPoint != null) {
      const int steps = 10;
      for (int i = 0; i <= steps; i++) {
        final double lat = fromPoint.latitude + (toPoint.latitude - fromPoint.latitude) * (i / steps);
        final double lng = fromPoint.longitude + (toPoint.longitude - fromPoint.longitude) * (i / steps);
        route.add(LatLng(lat, lng));
      }
    }

    return MaterialPageRoute<void>(
      builder: (_) => NearbyWitnessesPage(
        eventLocation: toPoint,
        fromLocation: fromPoint,
        routePoints: route,
        witnesses: items,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Marker> markers = <Marker>[
      if (fromLocation != null)
        Marker(
          point: fromLocation!,
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
      Marker(
        point: eventLocation,
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
      ...witnesses.map((w) => Marker(
            point: LatLng(w.lat, w.lng),
            width: 60,
            height: 60,
            child: Column(
              children: [
                const Icon(Icons.phone_android, color: Colors.green),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
                  ),
                  child: Text(w.name, style: const TextStyle(fontSize: 11)),
                ),
              ],
            ),
          )),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Dispositivos cercanos')),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: fromLocation ?? eventLocation,
                initialZoom: 16,
                minZoom: 3,
                maxZoom: 30,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                ),
                if (routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(points: routePoints, color: Colors.deepPurple, strokeWidth: 4),
                    ],
                  ),
                MarkerLayer(markers: markers),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: ListView.separated(
              itemCount: witnesses.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final WitnessDevice w = witnesses[index];
                final bool isNearest = index == 0;
                return ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text(w.name)),
                      if (isNearest)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Chip(
                            label: Text('Más cercano'),
                            visualDensity: VisualDensity(vertical: -4, horizontal: -4),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text('ID: ${w.id}\nDistancia aprox: ${w.distMeters.toStringAsFixed(1)} m'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.map),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}