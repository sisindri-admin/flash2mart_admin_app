import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../constants/app_colors.dart';
import '../utils/parse_utils.dart';

class OrderLocationSnapshot {
  final LatLng storeLatLng;
  final LatLng customerLatLng;
  final LatLng partnerLatLng;
  final bool hasLivePartnerGps;
  final String partnerName;
  final String partnerPhone;
  final String vehicleNumber;
  final DateTime? lastUpdate;
  final double distanceKm;
  final int etaMinutes;

  const OrderLocationSnapshot({
    required this.storeLatLng,
    required this.customerLatLng,
    required this.partnerLatLng,
    required this.hasLivePartnerGps,
    required this.partnerName,
    required this.partnerPhone,
    required this.vehicleNumber,
    required this.lastUpdate,
    required this.distanceKm,
    required this.etaMinutes,
  });

  static LatLng? extractGeoPoint(dynamic val) {
    if (val is GeoPoint) {
      if (val.latitude != 0 && val.longitude != 0) {
        return LatLng(val.latitude, val.longitude);
      }
    } else if (val is Map) {
      final lat = ParseUtils.toDouble(val['latitude'] ?? val['lat']);
      final lng = ParseUtils.toDouble(val['longitude'] ?? val['lng']);
      if (lat != 0 && lng != 0) {
        return LatLng(lat, lng);
      }
    }
    return null;
  }

  static LatLng? extractFromFields(
    Map<String, dynamic> map,
    List<String> latKeys,
    List<String> lngKeys,
  ) {
    double lat = 0;
    double lng = 0;
    for (final k in latKeys) {
      if (map[k] != null) {
        lat = ParseUtils.toDouble(map[k]);
        if (lat != 0) break;
      }
    }
    for (final k in lngKeys) {
      if (map[k] != null) {
        lng = ParseUtils.toDouble(map[k]);
        if (lng != 0) break;
      }
    }
    if (lat != 0 && lng != 0) return LatLng(lat, lng);
    return null;
  }

  static double haversineKm(LatLng a, LatLng b) {
    const double r = 6371.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  factory OrderLocationSnapshot.fromOrderData(
    Map<String, dynamic> data, {
    Map<String, dynamic>? partnerDoc,
  }) {
    final storeLoc = extractGeoPoint(data['storeLocation']) ??
        extractGeoPoint(data['merchantLocation']) ??
        extractFromFields(data, ['storeLat', 'merchantLat'], ['storeLng', 'merchantLng']) ??
        const LatLng(14.4485, 79.9890);

    final customerLoc = extractGeoPoint(data['customerLocation']) ??
        extractGeoPoint(data['deliveryLocation']) ??
        extractFromFields(
          data,
          ['customerLat', 'customerLatitude', 'latitude', 'lat'],
          ['customerLng', 'customerLongitude', 'longitude', 'lng'],
        ) ??
        const LatLng(14.4328, 79.9772);

    LatLng? livePartner = extractGeoPoint(data['deliveryPartnerLocation']) ??
        extractGeoPoint(data['driverLocation']) ??
        extractGeoPoint(data['partnerLocation']) ??
        extractGeoPoint(data['riderLocation']) ??
        extractFromFields(
          data,
          ['deliveryPartnerLat', 'partnerLat', 'driverLat', 'riderLat'],
          ['deliveryPartnerLng', 'partnerLng', 'driverLng', 'riderLng'],
        );

    if (livePartner == null && partnerDoc != null) {
      livePartner = extractGeoPoint(partnerDoc['currentLocation']) ??
          extractGeoPoint(partnerDoc['location']) ??
          extractFromFields(partnerDoc, ['latitude', 'lat'], ['longitude', 'lng']);
    }

    final status = (data['orderStatus'] ?? data['status'] ?? data['currentStatus'] ?? '').toString().toLowerCase();
    final bool hasLive = livePartner != null;
    final LatLng partnerLoc;
    if (livePartner != null) {
      partnerLoc = livePartner;
    } else if (status.contains('delivered') || status.contains('completed')) {
      partnerLoc = customerLoc;
    } else if (status.contains('out') || status.contains('picked') || status.contains('way')) {
      partnerLoc = LatLng(
        (storeLoc.latitude + customerLoc.latitude) / 2.0,
        (storeLoc.longitude + customerLoc.longitude) / 2.0,
      );
    } else {
      partnerLoc = LatLng(storeLoc.latitude + 0.008, storeLoc.longitude - 0.006);
    }

    final String pName = (partnerDoc?['name'] ??
            partnerDoc?['fullName'] ??
            data['deliveryPartnerName'] ??
            data['driverName'] ??
            '')
        .toString()
        .trim();
    final String pPhone = (partnerDoc?['phone'] ??
            data['deliveryPartnerPhone'] ??
            data['driverPhone'] ??
            '')
        .toString()
        .trim();
    final String vNo = (partnerDoc?['vehicleNumber'] ?? data['vehicleNumber'] ?? '').toString().trim();

    DateTime? lastUpd;
    final dynamic ts = data['lastLocationUpdate'] ?? partnerDoc?['lastLocationUpdate'] ?? data['updatedAt'];
    if (ts is Timestamp) lastUpd = ts.toDate();
    if (ts is String) lastUpd = DateTime.tryParse(ts);

    final double remainingKm = haversineKm(partnerLoc, customerLoc) * 1.35;
    final int eta = (remainingKm / 22.0 * 60).round().clamp(2, 60);

    return OrderLocationSnapshot(
      storeLatLng: storeLoc,
      customerLatLng: customerLoc,
      partnerLatLng: partnerLoc,
      hasLivePartnerGps: hasLive,
      partnerName: pName,
      partnerPhone: pPhone,
      vehicleNumber: vNo,
      lastUpdate: lastUpd,
      distanceKm: remainingKm,
      etaMinutes: eta,
    );
  }
}

class AdminLiveOrderMap extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> initialData;

  const AdminLiveOrderMap({
    super.key,
    required this.docId,
    required this.initialData,
  });

  @override
  State<AdminLiveOrderMap> createState() => _AdminLiveOrderMapState();
}

class _AdminLiveOrderMapState extends State<AdminLiveOrderMap> {
  final MapController _mapController = MapController();
  bool _autoFollow = true;

  String _freshnessText(DateTime? lastUpdate, bool hasLive) {
    if (!hasLive) return 'Estimated Route (No Rider GPS yet)';
    if (lastUpdate == null) return 'Live Rider GPS Active';
    final secs = DateTime.now().difference(lastUpdate).inSeconds.abs();
    if (secs < 20) return 'Live GPS • Updated just now';
    if (secs < 60) return 'Live GPS • ${secs}s ago';
    final mins = (secs / 60).floor();
    if (mins < 60) return 'Live GPS • ${mins}m ago';
    return 'GPS • ${(mins / 60).floor()}h ago';
  }

  void _fitAll(OrderLocationSnapshot loc) {
    setState(() => _autoFollow = false);
    try {
      final bounds = LatLngBounds.fromPoints([loc.storeLatLng, loc.partnerLatLng, loc.customerLatLng]);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(42)),
      );
    } catch (_) {}
  }

  void _centerRider(OrderLocationSnapshot loc) {
    setState(() => _autoFollow = true);
    try {
      _mapController.move(loc.partnerLatLng, 15.2);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').doc(widget.docId).snapshots(),
      builder: (context, orderSnap) {
        final data = (orderSnap.hasData && orderSnap.data!.exists)
            ? (orderSnap.data!.data() as Map<String, dynamic>? ?? widget.initialData)
            : widget.initialData;
        final partnerId = (data['deliveryPartnerId'] ?? data['driverId'] ?? '').toString().trim();

        if (partnerId.isEmpty) {
          return _buildMapAndPartnerCard(OrderLocationSnapshot.fromOrderData(data));
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('delivery_partners').doc(partnerId).snapshots(),
          builder: (context, partnerSnap) {
            final partnerDoc = (partnerSnap.hasData && partnerSnap.data!.exists)
                ? partnerSnap.data!.data() as Map<String, dynamic>?
                : null;
            final loc = OrderLocationSnapshot.fromOrderData(data, partnerDoc: partnerDoc);
            return _buildMapAndPartnerCard(loc);
          },
        );
      },
    );
  }

  Widget _buildMapAndPartnerCard(OrderLocationSnapshot loc) {
    if (_autoFollow && loc.hasLivePartnerGps) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(loc.partnerLatLng, 14.5);
        } catch (_) {}
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Delivery Partner Status Card
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: loc.partnerName.isNotEmpty ? AppColors.accentGreenLight : AppColors.accentOrangeLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (loc.partnerName.isNotEmpty ? AppColors.accentGreen : AppColors.accentOrange).withAlpha(80),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: loc.partnerName.isNotEmpty ? AppColors.accentGreen : AppColors.accentOrange,
                child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.partnerName.isNotEmpty ? loc.partnerName : 'Waiting for Delivery Partner',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark),
                    ),
                    Text(
                      loc.partnerPhone.isNotEmpty
                          ? '📞 ${loc.partnerPhone}${loc.vehicleNumber.isNotEmpty ? ' • 🛵 ${loc.vehicleNumber}' : ''}'
                          : 'Rider will be assigned once store packs the order',
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${loc.etaMinutes} min', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: AppColors.primaryPurple)),
                  Text('${loc.distanceKm.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Interactive Live Map
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.borderSubtle),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: loc.partnerLatLng,
                    initialZoom: 13.8,
                    onPositionChanged: (_, hasGesture) {
                      if (hasGesture && _autoFollow) {
                        setState(() => _autoFollow = false);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.flash2mart.admin',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [loc.partnerLatLng, loc.storeLatLng],
                          strokeWidth: 3.5,
                          color: AppColors.accentOrange,
                        ),
                        Polyline(
                          points: [loc.storeLatLng, loc.customerLatLng],
                          strokeWidth: 4.0,
                          color: AppColors.primaryPurple,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        // Store Marker
                        Marker(
                          point: loc.storeLatLng,
                          width: 38,
                          height: 38,
                          child: _pinBadge(Icons.storefront_rounded, AppColors.primaryPurple),
                        ),
                        // Customer Marker
                        Marker(
                          point: loc.customerLatLng,
                          width: 38,
                          height: 38,
                          child: _pinBadge(Icons.location_on_rounded, AppColors.accentRed),
                        ),
                        // Delivery Partner Live Marker
                        Marker(
                          point: loc.partnerLatLng,
                          width: 42,
                          height: 42,
                          child: _pinBadge(Icons.delivery_dining_rounded, AppColors.accentGreen),
                        ),
                      ],
                    ),
                  ],
                ),

                // Top GPS Freshness Pill
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(235),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withAlpha(25), blurRadius: 4)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: loc.hasLivePartnerGps ? AppColors.accentGreen : AppColors.accentOrange,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _freshnessText(loc.lastUpdate, loc.hasLivePartnerGps),
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.textDark),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom-right Map Controls
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Row(
                    children: [
                      _mapBtn(Icons.fit_screen_rounded, 'Fit All', () => _fitAll(loc)),
                      const SizedBox(width: 6),
                      _mapBtn(Icons.my_location_rounded, 'Rider', () => _centerRider(loc)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _LegendDot(color: AppColors.primaryPurple, label: 'Store'),
            _LegendDot(color: AppColors.accentGreen, label: 'Delivery Partner'),
            _LegendDot(color: AppColors.accentRed, label: 'Customer'),
          ],
        ),
      ],
    );
  }

  Widget _pinBadge(IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(45), blurRadius: 5)],
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  Widget _mapBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(240),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 4)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.primaryPurple),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 9, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
      ],
    );
  }
}
