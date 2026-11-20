import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_colors.dart';
import '../utils/parse_utils.dart';

class _RiderStats {
  int todayDeliveries = 0;
  int weeklyDeliveries = 0;
  int totalDeliveries = 0;
  double todayCodCash = 0;
  double totalCodCash = 0;
}

class AdminDeliveryPartnersScreen extends StatefulWidget {
  final bool showAppBar;
  const AdminDeliveryPartnersScreen({super.key, this.showAppBar = true});

  @override
  State<AdminDeliveryPartnersScreen> createState() => _AdminDeliveryPartnersScreenState();
}

class _AdminDeliveryPartnersScreenState extends State<AdminDeliveryPartnersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _updatePartnerStatus(BuildContext context, String partnerId, String status) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection('delivery_partners').doc(partnerId).set({
        'status': status,
        'isApproved': status == 'approved',
        if (status == 'approved') 'approvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      messenger.showSnackBar(
        SnackBar(
          content: Text('Delivery Partner status updated to ${status.toUpperCase()}'),
          backgroundColor: status == 'approved' ? AppColors.accentGreen : AppColors.accentRed,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.accentRed));
    }
  }

  Future<void> _settleCodCash(BuildContext context, String partnerId, String name, double pendingCod) async {
    if (pendingCod <= 0) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection('delivery_partners').doc(partnerId).set({
        'codSettledAmount': FieldValue.increment(pendingCod),
        'lastCodSettledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      messenger.showSnackBar(
        SnackBar(
          content: Text('✅ Settled ₹${pendingCod.toStringAsFixed(0)} COD cash from $name'),
          backgroundColor: AppColors.accentGreen,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Settlement error: $e'), backgroundColor: AppColors.accentRed));
    }
  }

  Map<String, _RiderStats> _computeRiderStats(List<QueryDocumentSnapshot> orderDocs) {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final sevenDaysAgo = todayMidnight.subtract(const Duration(days: 6));
    final Map<String, _RiderStats> statsMap = {};

    for (final doc in orderDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final pid = (data['deliveryPartnerId'] ?? data['driverId'] ?? '').toString().trim();
      if (pid.isEmpty) continue;

      final status = (data['orderStatus'] ?? data['status'] ?? data['currentStatus'] ?? '').toString().toLowerCase();
      if (status != 'delivered' && status != 'completed') continue;

      final stats = statsMap.putIfAbsent(pid, () => _RiderStats());
      stats.totalDeliveries++;

      final payment = (data['paymentMethod'] ?? 'COD').toString().toUpperCase();
      final bool isCod = !payment.contains('ONLINE') && !payment.contains('UPI');
      final double amt = ParseUtils.toDouble(data['grandTotal'] ?? data['totalAmount'] ?? data['itemTotal']);
      if (isCod) stats.totalCodCash += amt;

      DateTime? dt;
      final dynamic ts = data['createdAt'] ?? data['updatedAt'] ?? data['acceptedAt'];
      if (ts is Timestamp) dt = ts.toDate();

      if (dt != null) {
        if (!dt.isBefore(todayMidnight)) {
          stats.todayDeliveries++;
          if (isCod) stats.todayCodCash += amt;
        }
        if (!dt.isBefore(sevenDaysAgo)) {
          stats.weeklyDeliveries++;
        }
      }
    }
    return statsMap;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Delivery Partners & COD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textDark,
              elevation: 0.5,
            )
          : null,
      body: Column(
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
                        hintText: 'Search rider name, phone or vehicle...',
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ),
                TabBar(
                  controller: _tabController,
                  indicatorColor: AppColors.primaryPurple,
                  indicatorWeight: 3,
                  labelColor: AppColors.primaryPurple,
                  unselectedLabelColor: AppColors.textMuted,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  tabs: const [
                    Tab(text: 'PENDING'),
                    Tab(text: 'ACTIVE RIDERS'),
                    Tab(text: 'ALL RIDERS'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('delivery_partners').snapshots(),
              builder: (context, partnerSnap) {
                if (partnerSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
                }
                final allPartners = partnerSnap.hasData ? partnerSnap.data!.docs : <QueryDocumentSnapshot>[];

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('orders').snapshots(),
                  builder: (context, orderSnap) {
                    final orderDocs = orderSnap.hasData ? orderSnap.data!.docs : <QueryDocumentSnapshot>[];
                    final statsMap = _computeRiderStats(orderDocs);

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _buildList(allPartners, statsMap, filter: 'pending'),
                        _buildList(allPartners, statsMap, filter: 'approved'),
                        _buildList(allPartners, statsMap, filter: 'all'),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    List<QueryDocumentSnapshot> docs,
    Map<String, _RiderStats> statsMap, {
    required String filter,
  }) {
    final filtered = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = (data['status'] ?? 'pending').toString().toLowerCase();
      final isApp = data['isApproved'] == true || status == 'approved';

      if (filter == 'pending' && isApp) return false;
      if (filter == 'approved' && !isApp) return false;

      if (_searchQuery.isNotEmpty) {
        final name = (data['name'] ?? data['fullName'] ?? '').toString().toLowerCase();
        final phone = (data['phone'] ?? data['phoneNumber'] ?? '').toString().toLowerCase();
        final vehicle = (data['vehicleNumber'] ?? '').toString().toLowerCase();
        return name.contains(_searchQuery) || phone.contains(_searchQuery) || vehicle.contains(_searchQuery);
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delivery_dining_rounded, size: 48, color: AppColors.textMuted.withAlpha(120)),
            const SizedBox(height: 10),
            const Text('No delivery partners found.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: filtered.length,
      itemBuilder: (context, idx) {
        final doc = filtered[idx];
        final data = doc.data() as Map<String, dynamic>;
        final name = (data['name'] ?? data['fullName'] ?? 'Delivery Partner').toString();
        final phone = (data['phone'] ?? data['phoneNumber'] ?? 'No phone').toString();
        final vehicle = (data['vehicleNumber'] ?? data['bikeNumber'] ?? 'N/A').toString();
        final isOnline = data['isOnline'] == true;
        final status = (data['status'] ?? (data['isApproved'] == true ? 'approved' : 'pending')).toString().toLowerCase();
        final isApproved = status == 'approved';

        final stats = statsMap[doc.id] ?? _RiderStats();
        final settledCod = ParseUtils.toDouble(data['codSettledAmount']);
        final pendingCod = (stats.totalCodCash - settledCod).clamp(0.0, double.infinity);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0.5,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isApproved ? AppColors.accentGreen.withAlpha(70) : AppColors.accentOrange.withAlpha(80),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: isOnline ? AppColors.accentGreenLight : const Color(0xFFF1F5F9),
                      child: Icon(
                        Icons.delivery_dining_rounded,
                        color: isOnline ? AppColors.accentGreen : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isOnline ? AppColors.accentGreenLight : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isOnline ? 'ONLINE' : 'OFFLINE',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: isOnline ? AppColors.accentGreen : AppColors.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text('📞 $phone • 🛵 $vehicle',
                              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isApproved ? AppColors.accentGreenLight : AppColors.accentOrangeLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isApproved ? 'APPROVED' : 'PENDING',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: isApproved ? AppColors.accentGreen : AppColors.accentOrange,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Deliveries & COD Cash Strip
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.bgLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      _statCol('TODAY', '${stats.todayDeliveries} del', AppColors.accentGreen),
                      Container(width: 1, height: 26, color: AppColors.borderSubtle),
                      _statCol('THIS WEEK', '${stats.weeklyDeliveries} del', AppColors.accentBlue),
                      Container(width: 1, height: 26, color: AppColors.borderSubtle),
                      _statCol('PENDING COD', '₹${pendingCod.toStringAsFixed(0)}', AppColors.accentRed),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    if (!isApproved)
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _updatePartnerStatus(context, doc.id, 'approved'),
                          icon: const Icon(Icons.check_circle_outline, size: 16),
                          label: const Text('APPROVE RIDER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      )
                    else ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accentRed,
                            side: const BorderSide(color: AppColors.accentRed),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _updatePartnerStatus(context, doc.id, 'blocked'),
                          icon: const Icon(Icons.block, size: 15),
                          label: const Text('BLOCK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: pendingCod > 0 ? AppColors.primaryPurple : const Color(0xFFE2E8F0),
                            foregroundColor: pendingCod > 0 ? Colors.white : AppColors.textMuted,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: pendingCod > 0 ? () => _settleCodCash(context, doc.id, name, pendingCod) : null,
                          icon: const Icon(Icons.payments_rounded, size: 15),
                          label: const Text('SETTLE COD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statCol(String label, String val, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text(val, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }
}
