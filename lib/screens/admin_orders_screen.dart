import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../constants/app_colors.dart';
import '../utils/parse_utils.dart';
import '../widgets/admin_live_order_map.dart';
import '../widgets/admin_partner_assign_sheet.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showFleetMap = false;

  static const List<String> _statusSteps = [
    'Placed',
    'Accepted',
    'Packing',
    'Out for Delivery',
    'Delivered',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _extractStatus(Map<String, dynamic> data) {
    return (data['orderStatus'] ?? data['status'] ?? data['currentStatus'] ?? 'Placed')
        .toString()
        .trim();
  }

  String _normalizeBucket(String rawStatus) {
    final s = rawStatus.toLowerCase();
    if (s == 'delivered' || s == 'completed') return 'delivered';
    if (s == 'cancelled' || s == 'rejected') return 'cancelled';
    if (s.contains('out') || s.contains('picked') || s.contains('way') || s.contains('dispatched')) {
      return 'out_for_delivery';
    }
    if (s == 'accepted' || s == 'confirmed' || s == 'packing' || s == 'packed' || s == 'ready' || s == 'preparing') {
      return 'preparing';
    }
    return 'placed';
  }

  Color _statusColor(String bucket) {
    switch (bucket) {
      case 'delivered':
        return AppColors.accentGreen;
      case 'cancelled':
        return AppColors.accentRed;
      case 'out_for_delivery':
        return AppColors.accentBlue;
      case 'preparing':
        return AppColors.primaryPurple;
      default:
        return AppColors.accentOrange;
    }
  }

  Color _statusBgColor(String bucket) {
    switch (bucket) {
      case 'delivered':
        return AppColors.accentGreenLight;
      case 'cancelled':
        return AppColors.accentRedLight;
      case 'out_for_delivery':
        return AppColors.accentBlueLight;
      case 'preparing':
        return AppColors.primaryLight;
      default:
        return AppColors.accentOrangeLight;
    }
  }

  DateTime? _parseOrderDate(Map<String, dynamic> data) {
    final dynamic ts = data['createdAt'] ?? data['updatedAt'] ?? data['acceptedAt'];
    if (ts is Timestamp) return ts.toDate();
    if (ts is String) return DateTime.tryParse(ts);
    return null;
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Just now';
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    if (isToday) {
      return 'Today, $hour12:$min $amPm';
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]}, $hour12:$min $amPm';
  }

  Future<void> _updateOrderStatus(BuildContext context, String docId, String newStatus) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection('orders').doc(docId).update({
        'orderStatus': newStatus,
        'status': newStatus,
        'currentStatus': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        'trackingHistory': FieldValue.arrayUnion([
          {
            'status': newStatus,
            'title': 'Updated to $newStatus by Admin',
            'timestamp': DateTime.now().toIso8601String(),
            'updatedBy': 'Admin',
          }
        ]),
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('Order #$docId updated to $newStatus'),
          backgroundColor: AppColors.accentGreen,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to update order: $e'),
          backgroundColor: AppColors.accentRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(
          _showFleetMap ? 'Live Fleet Radar Map' : 'Live Orders Tracking',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0.5,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => setState(() => _showFleetMap = !_showFleetMap),
              icon: Icon(
                _showFleetMap ? Icons.list_alt_rounded : Icons.map_rounded,
                size: 19,
                color: AppColors.primaryPurple,
              ),
              label: Text(
                _showFleetMap ? 'List View' : 'Live Map',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primaryPurple),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('orders').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
          }

          final allDocs = List<QueryDocumentSnapshot>.from(snapshot.hasData ? snapshot.data!.docs : []);
          allDocs.sort((a, b) {
            final da = _parseOrderDate(a.data() as Map<String, dynamic>) ?? DateTime.fromMillisecondsSinceEpoch(0);
            final db = _parseOrderDate(b.data() as Map<String, dynamic>) ?? DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da);
          });

          if (_showFleetMap) {
            return _buildFleetRadarMap(allDocs);
          }

          int placedCount = 0;
          int preparingCount = 0;
          int deliveryCount = 0;
          int deliveredCount = 0;
          int cancelledCount = 0;

          for (final doc in allDocs) {
            final bucket = _normalizeBucket(_extractStatus(doc.data() as Map<String, dynamic>));
            switch (bucket) {
              case 'placed':
                placedCount++;
                break;
              case 'preparing':
                preparingCount++;
                break;
              case 'out_for_delivery':
                deliveryCount++;
                break;
              case 'delivered':
                deliveredCount++;
                break;
              case 'cancelled':
                cancelledCount++;
                break;
            }
          }

          return Column(
            children: [
              Container(
                color: Colors.white,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: SizedBox(
                        height: 40,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                          decoration: InputDecoration(
                            hintText: 'Search Order ID, store, phone or address...',
                            hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                            prefixIcon: const Icon(Icons.search, size: 19, color: AppColors.textMuted),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                            filled: true,
                            fillColor: const Color(0xFFF1F5F9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorColor: AppColors.primaryPurple,
                      indicatorWeight: 3,
                      labelColor: AppColors.primaryPurple,
                      unselectedLabelColor: AppColors.textMuted,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      tabs: [
                        Tab(text: 'ALL (${allDocs.length})'),
                        Tab(text: 'PLACED ($placedCount)'),
                        Tab(text: 'PREPARING ($preparingCount)'),
                        Tab(text: 'ON THE WAY ($deliveryCount)'),
                        Tab(text: 'DELIVERED ($deliveredCount)'),
                        Tab(text: 'CANCELLED ($cancelledCount)'),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOrderList(allDocs, allDocs, bucketFilter: 'all'),
                    _buildOrderList(allDocs, allDocs, bucketFilter: 'placed'),
                    _buildOrderList(allDocs, allDocs, bucketFilter: 'preparing'),
                    _buildOrderList(allDocs, allDocs, bucketFilter: 'out_for_delivery'),
                    _buildOrderList(allDocs, allDocs, bucketFilter: 'delivered'),
                    _buildOrderList(allDocs, allDocs, bucketFilter: 'cancelled'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFleetRadarMap(List<QueryDocumentSnapshot> allDocs) {
    final activeDocs = allDocs.where((doc) {
      final bucket = _normalizeBucket(_extractStatus(doc.data() as Map<String, dynamic>));
      return bucket != 'delivered' && bucket != 'cancelled';
    }).toList();

    final List<Marker> markers = [];
    for (final doc in activeDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final loc = OrderLocationSnapshot.fromOrderData(data);
      final orderId = (data['orderId'] ?? doc.id).toString();

      markers.add(
        Marker(
          point: loc.partnerLatLng,
          width: 96,
          height: 54,
          child: GestureDetector(
            onTap: () => _showOrderDetailSheet(context, doc.id, data, allDocs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.textDark,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#$orderId',
                    style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: loc.hasLivePartnerGps ? AppColors.accentGreen : AppColors.accentOrange,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        FlutterMap(
          options: const MapOptions(
            initialCenter: LatLng(14.4426, 79.9865),
            initialZoom: 13.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.flash2mart.admin',
            ),
            MarkerLayer(markers: markers),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(240),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(25), blurRadius: 8)],
            ),
            child: Row(
              children: [
                const Icon(Icons.radar_rounded, color: AppColors.accentGreen, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${activeDocs.length} Active Orders on Radar • Tap any rider pin to inspect',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textDark),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderList(
    List<QueryDocumentSnapshot> docs,
    List<QueryDocumentSnapshot> allOrderDocs, {
    required String bucketFilter,
  }) {
    final filtered = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final bucket = _normalizeBucket(_extractStatus(data));
      if (bucketFilter != 'all' && bucket != bucketFilter) return false;

      if (_searchQuery.isNotEmpty) {
        final orderId = (data['orderId'] ?? doc.id).toString().toLowerCase();
        final store = (data['storeName'] ?? '').toString().toLowerCase();
        final phone = (data['userPhone'] ?? data['customerPhone'] ?? '').toString().toLowerCase();
        final addr = (data['deliveryAddress'] ?? '').toString().toLowerCase();
        return orderId.contains(_searchQuery) ||
            store.contains(_searchQuery) ||
            phone.contains(_searchQuery) ||
            addr.contains(_searchQuery);
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_rounded, size: 48, color: AppColors.textMuted.withAlpha(120)),
            const SizedBox(height: 10),
            const Text(
              'No orders found in this stage.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final doc = filtered[index];
        final data = doc.data() as Map<String, dynamic>;
        final String orderId = (data['orderId'] ?? doc.id).toString();
        final String rawStatus = _extractStatus(data);
        final String bucket = _normalizeBucket(rawStatus);
        final Color sColor = _statusColor(bucket);
        final Color sBg = _statusBgColor(bucket);
        final DateTime? orderDate = _parseOrderDate(data);

        final String storeName = (data['storeName'] ?? 'Flash2Mart Store').toString();
        final String userPhone = (data['userPhone'] ?? data['customerPhone'] ?? 'N/A').toString();
        final String address = (data['deliveryAddress'] ?? 'Nellore, AP').toString();
        final String otp = (data['deliveryOtp'] ?? '').toString();
        final String paymentMethod = (data['paymentMethod'] ?? 'COD').toString();
        final double grandTotal = ParseUtils.toDouble(data['grandTotal'] ?? data['totalAmount'] ?? data['itemTotal']);
        final List items = (data['items'] is List) ? data['items'] as List : [];

        final String partnerId = (data['deliveryPartnerId'] ?? data['driverId'] ?? '').toString().trim();
        final String partnerName = (data['deliveryPartnerName'] ?? data['driverName'] ?? '').toString().trim();
        final bool isBatched = data['isBatchedOrder'] == true;
        final bool canAssign = bucket != 'delivered' && bucket != 'cancelled';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0.5,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: sColor.withAlpha(70), width: 1.1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _showOrderDetailSheet(context, doc.id, data, allOrderDocs),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              '#$orderId',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: AppColors.textDark),
                            ),
                            const SizedBox(width: 6),
                            if (isBatched) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.accentGreenLight,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: const Text(
                                  'BATCHED',
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.accentGreen),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                _formatDateTime(orderDate),
                                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: sBg, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          rawStatus.toUpperCase(),
                          style: TextStyle(color: sColor, fontSize: 10, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (data['arrivedDifferentLocation'] == true) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Text(
                        '⚠️ Arrived ~${data['arrivalDistanceMeters'] ?? ''}m from Customer Pin',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                      ),
                    ),
                  ],
                  Row(
                    children: [
                      const Icon(Icons.storefront_rounded, size: 15, color: AppColors.primaryPurple),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          storeName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppColors.textDark),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '₹${grandTotal.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.textDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(userPhone, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                      const SizedBox(width: 10),
                      const Icon(Icons.shopping_bag_outlined, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text('${items.length} items', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          paymentMethod,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textDark),
                        ),
                      ),
                      if (otp.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(6)),
                          child: Text(
                            'OTP: $otp',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primaryPurple),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '📍 $address',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (canAssign) ...[
                    const SizedBox(height: 9),
                    if (partnerId.isEmpty)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primaryPurple,
                                side: const BorderSide(color: AppColors.primaryPurple),
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => AdminPartnerAssignHelper.showAssignSheet(
                                context: context,
                                docId: doc.id,
                                orderData: data,
                                allOrderDocs: allOrderDocs,
                              ),
                              icon: const Icon(Icons.person_add_alt_1_rounded, size: 15),
                              label: const Text('ASSIGN PARTNER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accentGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => AdminPartnerAssignHelper.autoAssignNearestOrBatch(
                                context: context,
                                docId: doc.id,
                                orderData: data,
                                cachedOrders: allOrderDocs,
                              ),
                              icon: const Icon(Icons.bolt_rounded, size: 16),
                              label: const Text('AUTO-ASSIGN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '🛵 Rider: ${partnerName.isNotEmpty ? partnerName : partnerId}',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.accentGreen),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => AdminPartnerAssignHelper.showAssignSheet(
                              context: context,
                              docId: doc.id,
                              orderData: data,
                              allOrderDocs: allOrderDocs,
                            ),
                            child: const Text('Reassign', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showOrderDetailSheet(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
    List<QueryDocumentSnapshot> allOrderDocs,
  ) {
    final String orderId = (data['orderId'] ?? docId).toString();
    final String rawStatus = _extractStatus(data);
    final String bucket = _normalizeBucket(rawStatus);
    final String storeName = (data['storeName'] ?? 'Merchant Store').toString();
    final String userPhone = (data['userPhone'] ?? data['customerPhone'] ?? 'N/A').toString();
    final String address = (data['deliveryAddress'] ?? 'Nellore, AP').toString();
    final String otp = (data['deliveryOtp'] ?? 'N/A').toString();
    final String instructions = (data['deliveryInstructions'] ?? '').toString();
    final String paymentMethod = (data['paymentMethod'] ?? 'COD').toString();
    final String paymentStatus = (data['paymentStatus'] ?? 'Pending').toString();

    final double itemTotal = ParseUtils.toDouble(data['itemTotal']);
    final double deliveryFee = ParseUtils.toDouble(data['deliveryFee']);
    final double handlingFee = ParseUtils.toDouble(data['handlingFee']);
    final double discountAmount = ParseUtils.toDouble(data['discountAmount']);
    final double grandTotal = ParseUtils.toDouble(data['grandTotal'] ?? data['totalAmount'] ?? itemTotal);

    final List items = (data['items'] is List) ? data['items'] as List : [];
    final List history = (data['trackingHistory'] is List) ? data['trackingHistory'] as List : [];

    int activeStepIndex = 0;
    if (bucket == 'preparing') activeStepIndex = rawStatus.toLowerCase().contains('pack') ? 2 : 1;
    if (bucket == 'out_for_delivery') activeStepIndex = 3;
    if (bucket == 'delivered') activeStepIndex = 4;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.96,
          expand: false,
          builder: (_, scrollCtrl) {
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(18),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: AppColors.borderSubtle, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Order #$orderId', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: _statusBgColor(bucket), borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        rawStatus.toUpperCase(),
                        style: TextStyle(color: _statusColor(bucket), fontWeight: FontWeight.w900, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 5-Step Progress Bar
                if (bucket != 'cancelled') ...[
                  const Text('Live Order Progress', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 10),
                  Row(
                    children: List.generate(_statusSteps.length, (i) {
                      final done = i <= activeStepIndex;
                      return Expanded(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                if (i > 0)
                                  Expanded(
                                    child: Container(
                                      height: 3,
                                      color: done ? AppColors.accentGreen : AppColors.borderSubtle,
                                    ),
                                  ),
                                CircleAvatar(
                                  radius: 10,
                                  backgroundColor: done ? AppColors.accentGreen : AppColors.borderSubtle,
                                  child: Icon(
                                    done ? Icons.check : Icons.circle,
                                    size: 11,
                                    color: Colors.white,
                                  ),
                                ),
                                if (i < _statusSteps.length - 1)
                                  Expanded(
                                    child: Container(
                                      height: 3,
                                      color: i < activeStepIndex ? AppColors.accentGreen : AppColors.borderSubtle,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _statusSteps[i],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: done ? FontWeight.bold : FontWeight.normal,
                                color: done ? AppColors.textDark : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 14),
                ],

                // Live Order & Delivery Partner Map
                AdminLiveOrderMap(docId: docId, initialData: data),
                const SizedBox(height: 12),

                if (bucket != 'delivered' && bucket != 'cancelled') ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryPurple,
                            side: const BorderSide(color: AppColors.primaryPurple),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            AdminPartnerAssignHelper.showAssignSheet(
                              context: context,
                              docId: docId,
                              orderData: data,
                              allOrderDocs: allOrderDocs,
                            );
                          },
                          icon: const Icon(Icons.person_search_rounded, size: 17),
                          label: const Text('ASSIGN / REASSIGN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            AdminPartnerAssignHelper.autoAssignNearestOrBatch(
                              context: context,
                              docId: docId,
                              orderData: data,
                              cachedOrders: allOrderDocs,
                            );
                          },
                          icon: const Icon(Icons.bolt_rounded, size: 17),
                          label: const Text('SMART AUTO-ASSIGN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],

                // Store & Customer Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bgLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🏪 Store: $storeName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('📞 Customer: $userPhone', style: const TextStyle(fontSize: 12.5, color: AppColors.textDark)),
                      const SizedBox(height: 4),
                      Text('📍 Address: $address', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      const SizedBox(height: 4),
                      Text('🔐 Delivery OTP: $otp  •  💳 $paymentMethod ($paymentStatus)',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryPurple)),
                      if (instructions.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('📝 Note: $instructions', style: const TextStyle(fontSize: 11.5, color: AppColors.accentOrange)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Items Breakdown
                Text('Ordered Items (${items.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 8),
                ...items.map((item) {
                  final m = (item is Map) ? item : <String, dynamic>{};
                  final name = (m['name'] ?? m['title'] ?? 'Item').toString();
                  final qty = ParseUtils.toInt(m['qty'] ?? m['quantity'], 1);
                  final price = ParseUtils.toDouble(m['price'] ?? m['offerPrice']);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text('$qty x $name', style: const TextStyle(fontSize: 12.5))),
                        Text('₹${(price * qty).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      ],
                    ),
                  );
                }),
                const Divider(height: 18),
                _billRow('Item Total', itemTotal),
                if (deliveryFee > 0) _billRow('Delivery Fee', deliveryFee),
                if (handlingFee > 0) _billRow('Handling Fee', handlingFee),
                if (discountAmount > 0) _billRow('Discount', -discountAmount),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Grand Total', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    Text('₹${grandTotal.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.accentGreen)),
                  ],
                ),
                const SizedBox(height: 18),

                // Admin Status Controls
                const Text('Admin Status Override', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['Accepted', 'Packing', 'Out for Delivery', 'Delivered', 'Cancelled'].map((statusOption) {
                    final isCurrent = rawStatus.toLowerCase() == statusOption.toLowerCase();
                    final isCancel = statusOption == 'Cancelled';
                    return ChoiceChip(
                      label: Text(statusOption, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      selected: isCurrent,
                      selectedColor: isCancel ? AppColors.accentRedLight : AppColors.primaryLight,
                      onSelected: isCurrent
                          ? null
                          : (_) {
                              Navigator.pop(sheetCtx);
                              _updateOrderStatus(context, docId, statusOption);
                            },
                    );
                  }).toList(),
                ),

                if (history.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text('Tracking History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  ...history.reversed.map((h) {
                    final m = (h is Map) ? h : <String, dynamic>{};
                    final title = (m['title'] ?? m['status'] ?? '').toString();
                    final by = (m['updatedBy'] ?? '').toString();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        '• $title ${by.isNotEmpty ? '($by)' : ''}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                      ),
                    );
                  }),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _billRow(String label, double val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          Text('₹${val.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, color: AppColors.textDark)),
        ],
      ),
    );
  }
}
