import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../constants/app_colors.dart';
import 'admin_live_order_map.dart';

class PartnerCandidate {
  final String partnerId;
  final String name;
  final String phone;
  final String vehicleNumber;
  final bool isOnline;
  final LatLng? currentLatLng;
  final double distanceFromStoreKm;
  final int activeOrderCount;
  final bool hasNotPickedUpOrder;
  final bool isBatchMatch;
  final String? batchWithOrderId;
  final String? batchReason;

  const PartnerCandidate({
    required this.partnerId,
    required this.name,
    required this.phone,
    required this.vehicleNumber,
    required this.isOnline,
    required this.currentLatLng,
    required this.distanceFromStoreKm,
    required this.activeOrderCount,
    required this.hasNotPickedUpOrder,
    required this.isBatchMatch,
    this.batchWithOrderId,
    this.batchReason,
  });
}

class AdminPartnerAssignHelper {
  static double _bearingDegrees(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180.0;
    final lat2 = to.latitude * math.pi / 180.0;
    final dLon = (to.longitude - from.longitude) * math.pi / 180.0;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x) * 180.0 / math.pi;
    return (brng + 360.0) % 360.0;
  }

  static double _angleDiff(double a, double b) {
    final diff = (a - b).abs() % 360.0;
    return diff > 180.0 ? 360.0 - diff : diff;
  }

  static bool _isPrePickupStatus(String rawStatus) {
    final s = rawStatus.toLowerCase().replaceAll(' ', '_');
    return s == 'placed' ||
        s == 'pending' ||
        s == 'accepted' ||
        s == 'confirmed' ||
        s == 'preparing' ||
        s == 'packing' ||
        s == 'packing_ready' ||
        s == 'packed' ||
        s == 'ready' ||
        s == 'ready_for_pickup' ||
        s == 'reached_store';
  }

  static bool _isFinishedStatus(String rawStatus) {
    final s = rawStatus.toLowerCase();
    return s == 'delivered' || s == 'completed' || s == 'cancelled' || s == 'rejected';
  }

  static List<PartnerCandidate> evaluateCandidates({
    required Map<String, dynamic> targetOrderData,
    required List<QueryDocumentSnapshot> partnerDocs,
    required List<QueryDocumentSnapshot> allOrderDocs,
  }) {
    final targetLoc = OrderLocationSnapshot.fromOrderData(targetOrderData);
    final targetStore = targetLoc.storeLatLng;
    final targetCustomer = targetLoc.customerLatLng;
    final targetMerchantId = (targetOrderData['merchantId'] ?? '').toString().trim();

    // Group active orders by deliveryPartnerId
    final Map<String, List<QueryDocumentSnapshot>> activeByPartner = {};
    for (final oDoc in allOrderDocs) {
      final od = oDoc.data() as Map<String, dynamic>;
      final status = (od['orderStatus'] ?? od['status'] ?? od['currentStatus'] ?? '').toString();
      if (_isFinishedStatus(status)) continue;
      final pid = (od['deliveryPartnerId'] ?? od['driverId'] ?? '').toString().trim();
      if (pid.isEmpty) continue;
      activeByPartner.putIfAbsent(pid, () => []).add(oDoc);
    }

    final List<PartnerCandidate> candidates = [];

    for (final pDoc in partnerDocs) {
      final pd = pDoc.data() as Map<String, dynamic>;
      final pid = pDoc.id;
      final name = (pd['name'] ?? pd['fullName'] ?? 'Delivery Partner').toString().trim();
      final phone = (pd['phone'] ?? pd['phoneNumber'] ?? '').toString().trim();
      final vehicle = (pd['vehicleNumber'] ?? pd['bikeNumber'] ?? '').toString().trim();
      final bool isOnline = pd['isOnline'] != false &&
          (pd['status'] ?? 'active').toString().toLowerCase() != 'offline' &&
          (pd['status'] ?? 'active').toString().toLowerCase() != 'blocked';

      final LatLng? pLatLng = OrderLocationSnapshot.extractGeoPoint(pd['currentLocation']) ??
          OrderLocationSnapshot.extractGeoPoint(pd['location']) ??
          OrderLocationSnapshot.extractFromFields(pd, ['latitude', 'lat'], ['longitude', 'lng']);

      final double distFromStore = pLatLng != null
          ? OrderLocationSnapshot.haversineKm(pLatLng, targetStore) * 1.35
          : 99.0;

      final partnerOrders = activeByPartner[pid] ?? [];
      final int activeCount = partnerOrders.length;

      bool hasNotPickedUp = false;
      bool isBatchMatch = false;
      String? batchOrderId;
      String? batchReason;

      if (activeCount == 1) {
        final existingDoc = partnerOrders.first;
        final existingData = existingDoc.data() as Map<String, dynamic>;
        final existingStatus =
            (existingData['orderStatus'] ?? existingData['status'] ?? existingData['currentStatus'] ?? '').toString();
        hasNotPickedUp = _isPrePickupStatus(existingStatus);

        if (hasNotPickedUp) {
          final existingLoc = OrderLocationSnapshot.fromOrderData(existingData);
          final existingMerchantId = (existingData['merchantId'] ?? '').toString().trim();
          final bool sameOrNearbyStore = (targetMerchantId.isNotEmpty && targetMerchantId == existingMerchantId) ||
              OrderLocationSnapshot.haversineKm(targetStore, existingLoc.storeLatLng) <= 0.6;

          if (sameOrNearbyStore) {
            final double customerGapKm =
                OrderLocationSnapshot.haversineKm(existingLoc.customerLatLng, targetCustomer) * 1.35;
            final double distToCust1 = OrderLocationSnapshot.haversineKm(targetStore, existingLoc.customerLatLng);
            final double distToCust2 = OrderLocationSnapshot.haversineKm(targetStore, targetCustomer);
            final double b1 = _bearingDegrees(targetStore, existingLoc.customerLatLng);
            final double b2 = _bearingDegrees(targetStore, targetCustomer);
            final bool isSameWay = _angleDiff(b1, b2) <= 35.0 && distToCust2 <= (distToCust1 + 1.5);

            if (customerGapKm <= 2.0 || isSameWay) {
              isBatchMatch = true;
              batchOrderId = (existingData['orderId'] ?? existingDoc.id).toString();
              batchReason = customerGapKm <= 2.0
                  ? '${customerGapKm.toStringAsFixed(1)} km from #$batchOrderId customer'
                  : 'On same route as #$batchOrderId';
            }
          }
        }
      }

      candidates.add(
        PartnerCandidate(
          partnerId: pid,
          name: name,
          phone: phone,
          vehicleNumber: vehicle,
          isOnline: isOnline,
          currentLatLng: pLatLng,
          distanceFromStoreKm: distFromStore,
          activeOrderCount: activeCount,
          hasNotPickedUpOrder: hasNotPickedUp,
          isBatchMatch: isBatchMatch,
          batchWithOrderId: batchOrderId,
          batchReason: batchReason,
        ),
      );
    }

    // Sort: 1) Online Batch Match, 2) Online Free (nearest first), 3) Online 1-order pre-pickup, 4) Others
    candidates.sort((a, b) {
      int tier(PartnerCandidate c) {
        if (!c.isOnline || c.activeOrderCount >= 2) return 4;
        if (c.isBatchMatch) return 0;
        if (c.activeOrderCount == 0) return 1;
        if (c.hasNotPickedUpOrder) return 2;
        return 3;
      }

      final ta = tier(a);
      final tb = tier(b);
      if (ta != tb) return ta.compareTo(tb);
      return a.distanceFromStoreKm.compareTo(b.distanceFromStoreKm);
    });

    return candidates;
  }

  static Future<void> assignPartnerToOrder({
    required BuildContext context,
    required String docId,
    required Map<String, dynamic> orderData,
    required PartnerCandidate partner,
    required bool isAutoAssigned,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final currentStatus =
          (orderData['orderStatus'] ?? orderData['status'] ?? orderData['currentStatus'] ?? 'Placed').toString();
      final lower = currentStatus.toLowerCase();
      final nextStatus = (lower == 'placed' || lower == 'pending') ? 'Accepted' : currentStatus;

      final String historyTitle = partner.isBatchMatch
          ? 'Smart Batched with #${partner.batchWithOrderId} → ${partner.name}'
          : (isAutoAssigned ? 'Auto-Assigned nearest partner ${partner.name}' : 'Assigned to ${partner.name} by Admin');

      int newSeq = 1;
      String? existingBatchDocId;
      if (partner.activeOrderCount >= 1) {
        final activeSnap = await FirebaseFirestore.instance
            .collection('orders')
            .where('deliveryPartnerId', isEqualTo: partner.partnerId)
            .get();
        final targetLoc = OrderLocationSnapshot.fromOrderData(orderData);
        final distNew = OrderLocationSnapshot.haversineKm(targetLoc.storeLatLng, targetLoc.customerLatLng);
        for (final ed in activeSnap.docs) {
          if (ed.id == docId) continue;
          final eData = ed.data();
          final es = (eData['orderStatus'] ?? eData['status'] ?? '').toString();
          if (_isFinishedStatus(es)) continue;
          existingBatchDocId = ed.id;
          final eLoc = OrderLocationSnapshot.fromOrderData(eData);
          final distExisting = OrderLocationSnapshot.haversineKm(eLoc.storeLatLng, eLoc.customerLatLng);
          if (distNew < distExisting) {
            newSeq = 1;
            await ed.reference.update({
              'isBatchedOrder': true,
              'batchSequence': 2,
              'batchedWithOrderId': docId,
            });
          } else {
            newSeq = 2;
            await ed.reference.update({
              'isBatchedOrder': true,
              'batchSequence': 1,
              'batchedWithOrderId': docId,
            });
          }
          break;
        }
      }

      final bool isBatchedNow = partner.isBatchMatch || existingBatchDocId != null;
      final Map<String, dynamic> updatePayload = {
        'deliveryPartnerId': partner.partnerId,
        'deliveryPartnerName': partner.name,
        'deliveryPartnerPhone': partner.phone,
        if (partner.vehicleNumber.isNotEmpty) 'vehicleNumber': partner.vehicleNumber,
        if (partner.currentLatLng != null)
          'deliveryPartnerLocation': GeoPoint(
            partner.currentLatLng!.latitude,
            partner.currentLatLng!.longitude,
          ),
        'orderStatus': nextStatus,
        'status': nextStatus,
        'currentStatus': nextStatus,
        'isBatchedOrder': isBatchedNow,
        if (partner.batchWithOrderId != null || existingBatchDocId != null)
          'batchedWithOrderId': partner.batchWithOrderId ?? existingBatchDocId,
        'batchSequence': newSeq,
        'assignedBy': isAutoAssigned ? 'AdminAutoAssign' : 'Admin',
        'assignedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'trackingHistory': FieldValue.arrayUnion([
          {
            'status': nextStatus,
            'title': historyTitle,
            'timestamp': DateTime.now().toIso8601String(),
            'updatedBy': 'Admin',
          }
        ]),
      };

      await FirebaseFirestore.instance.collection('orders').doc(docId).update(updatePayload);
      await FirebaseFirestore.instance.collection('delivery_partners').doc(partner.partnerId).set({
        'activeOrderId': docId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            partner.isBatchMatch
                ? '🔥 Smart Batched #$docId to ${partner.name} (${partner.batchReason})'
                : '✅ Assigned #$docId to ${partner.name}',
          ),
          backgroundColor: AppColors.accentGreen,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Assignment failed: $e'), backgroundColor: AppColors.accentRed),
      );
    }
  }

  static Future<void> autoAssignNearestOrBatch({
    required BuildContext context,
    required String docId,
    required Map<String, dynamic> orderData,
    List<QueryDocumentSnapshot>? cachedOrders,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final partnerSnap = await FirebaseFirestore.instance.collection('delivery_partners').get();
      final orderDocs = cachedOrders ?? (await FirebaseFirestore.instance.collection('orders').get()).docs;

      if (!context.mounted) return;
      final candidates = evaluateCandidates(
        targetOrderData: orderData,
        partnerDocs: partnerSnap.docs,
        allOrderDocs: orderDocs,
      );

      final eligible = candidates.where((c) => c.isOnline && c.activeOrderCount < 2).toList();
      if (eligible.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No online available delivery partners found right now.'),
            backgroundColor: AppColors.accentOrange,
          ),
        );
        return;
      }

      // Priority 1: Batch match, Priority 2: Free nearest rider, Priority 3: Pre-pickup 1-order rider
      final best = eligible.first;
      await assignPartnerToOrder(
        context: context,
        docId: docId,
        orderData: orderData,
        partner: best,
        isAutoAssigned: true,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Auto-assign failed: $e'), backgroundColor: AppColors.accentRed),
      );
    }
  }

  static void showAssignSheet({
    required BuildContext context,
    required String docId,
    required Map<String, dynamic> orderData,
    required List<QueryDocumentSnapshot> allOrderDocs,
  }) {
    final orderId = (orderData['orderId'] ?? docId).toString();
    final storeName = (orderData['storeName'] ?? 'Store').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.5,
          maxChildSize: 0.94,
          expand: false,
          builder: (_, scrollCtrl) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('delivery_partners').snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
                }

                final partnerDocs = snap.hasData ? snap.data!.docs : <QueryDocumentSnapshot>[];
                final candidates = evaluateCandidates(
                  targetOrderData: orderData,
                  partnerDocs: partnerDocs,
                  allOrderDocs: allOrderDocs,
                );

                return Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: AppColors.borderSubtle, borderRadius: BorderRadius.circular(4)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Assign Partner • #$orderId',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                Text('Nearest to $storeName & Same-Way Batching',
                                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () {
                              Navigator.pop(sheetCtx);
                              autoAssignNearestOrBatch(
                                context: context,
                                docId: docId,
                                orderData: orderData,
                                cachedOrders: allOrderDocs,
                              );
                            },
                            icon: const Icon(Icons.bolt_rounded, size: 17),
                            label: const Text('AUTO-ASSIGN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: candidates.isEmpty
                          ? const Center(
                              child: Text('No delivery partners found in delivery_partners collection.',
                                  style: TextStyle(color: AppColors.textMuted)),
                            )
                          : ListView.builder(
                              controller: scrollCtrl,
                              padding: const EdgeInsets.all(14),
                              itemCount: candidates.length,
                              itemBuilder: (_, idx) {
                                final c = candidates[idx];
                                final bool canAssign = c.activeOrderCount < 2;
                                final String distLabel = c.distanceFromStoreKm >= 90
                                    ? 'GPS unavailable'
                                    : '${c.distanceFromStoreKm.toStringAsFixed(1)} km from store';

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  elevation: 0.4,
                                  color: c.isBatchMatch ? AppColors.accentGreenLight : Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: c.isBatchMatch
                                          ? AppColors.accentGreen
                                          : AppColors.borderSubtle,
                                      width: c.isBatchMatch ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (c.isBatchMatch) ...[
                                          Container(
                                            margin: const EdgeInsets.only(bottom: 6),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: AppColors.accentGreen,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '🔥 BEST BATCH MATCH • ${c.batchReason}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ],
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundColor: c.isOnline
                                                  ? AppColors.primaryLight
                                                  : const Color(0xFFF1F5F9),
                                              child: Icon(
                                                Icons.delivery_dining_rounded,
                                                size: 20,
                                                color: c.isOnline ? AppColors.primaryPurple : AppColors.textMuted,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(c.name,
                                                          style: const TextStyle(
                                                              fontWeight: FontWeight.bold, fontSize: 13.5)),
                                                      const SizedBox(width: 6),
                                                      Icon(
                                                        Icons.circle,
                                                        size: 8,
                                                        color: c.isOnline
                                                            ? AppColors.accentGreen
                                                            : AppColors.textMuted,
                                                      ),
                                                    ],
                                                  ),
                                                  Text(
                                                    '📍 $distLabel • ${c.activeOrderCount == 0 ? 'Free' : '${c.activeOrderCount} Active${c.hasNotPickedUpOrder ? ' (Not Picked Up)' : ''}'}',
                                                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                                  ),
                                                  if (c.phone.isNotEmpty)
                                                    Text(
                                                      '📞 ${c.phone}${c.vehicleNumber.isNotEmpty ? ' • 🛵 ${c.vehicleNumber}' : ''}',
                                                      style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: c.isBatchMatch
                                                    ? AppColors.accentGreen
                                                    : AppColors.primaryPurple,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              onPressed: !canAssign
                                                  ? null
                                                  : () {
                                                      Navigator.pop(sheetCtx);
                                                      assignPartnerToOrder(
                                                        context: context,
                                                        docId: docId,
                                                        orderData: orderData,
                                                        partner: c,
                                                        isAutoAssigned: false,
                                                      );
                                                    },
                                              child: Text(
                                                c.isBatchMatch ? 'BATCH' : 'ASSIGN',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
