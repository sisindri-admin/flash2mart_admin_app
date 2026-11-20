import '../utils/parse_utils.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_colors.dart';

class _MerchantEarningsStats {
  double todayAmount = 0;
  int todayOrders = 0;
  double weeklyAmount = 0;
  int weeklyOrders = 0;
  double totalAmount = 0;
  int totalOrders = 0;
  int activeOrders = 0;
  double todayUpi = 0;
  double todayCod = 0;
  final Map<String, double> last7DaysAmount = {};
  final Map<String, int> last7DaysCount = {};
}

class AdminMerchantsScreen extends StatefulWidget {
  const AdminMerchantsScreen({super.key});

  @override
  State<AdminMerchantsScreen> createState() => _AdminMerchantsScreenState();
}

class _AdminMerchantsScreenState extends State<AdminMerchantsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'default'; // default, today, weekly, total

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

  Future<void> _updateMerchantStatus(BuildContext context, String merchantId, String status) async {
    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance.collection('merchants').doc(merchantId).set({
      'status': status,
      'isApproved': status == 'approved',
      if (status == 'approved') 'approvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    messenger.showSnackBar(
      SnackBar(
        content: Text('Store status updated to ${status.toUpperCase()}'),
        backgroundColor: status == 'approved' ? AppColors.accentGreen : AppColors.accentRed,
      ),
    );
  }

  Map<String, _MerchantEarningsStats> _computeEarningsByMerchant(List<QueryDocumentSnapshot> orderDocs) {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final sevenDaysAgo = todayMidnight.subtract(const Duration(days: 6));
    final Map<String, _MerchantEarningsStats> statsMap = {};

    for (final doc in orderDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final mId = (data['merchantId'] ?? '').toString().trim();
      final sName = (data['storeName'] ?? '').toString().trim().toLowerCase();
      final key = mId.isNotEmpty ? mId : sName;
      if (key.isEmpty) continue;

      final stats = statsMap.putIfAbsent(key, () => _MerchantEarningsStats());
      final status = (data['orderStatus'] ?? data['status'] ?? data['currentStatus'] ?? '').toString().toLowerCase();
      final bool isDelivered = status == 'delivered' || status == 'completed';
      final bool isCancelled = status == 'cancelled' || status == 'rejected';

      if (!isDelivered && !isCancelled) {
        stats.activeOrders++;
      }

      if (!isDelivered) continue;

      final double amount = ParseUtils.toDouble(data['grandTotal'] ?? data['totalAmount'] ?? data['itemTotal']);
      final String payment = (data['paymentMethod'] ?? 'COD').toString().toUpperCase();
      final bool isOnline = payment.contains('ONLINE') || payment.contains('UPI');

      stats.totalAmount += amount;
      stats.totalOrders++;

      DateTime? orderDate;
      final dynamic ts = data['createdAt'] ?? data['acceptedAt'] ?? data['updatedAt'];
      if (ts is Timestamp) {
        orderDate = ts.toDate();
      } else if (ts is String) {
        orderDate = DateTime.tryParse(ts);
      }

      if (orderDate != null) {
        if (!orderDate.isBefore(todayMidnight)) {
          stats.todayAmount += amount;
          stats.todayOrders++;
          if (isOnline) {
            stats.todayUpi += amount;
          } else {
            stats.todayCod += amount;
          }
        }
        if (!orderDate.isBefore(sevenDaysAgo)) {
          stats.weeklyAmount += amount;
          stats.weeklyOrders++;
          final dayKey =
              '${orderDate.year}-${orderDate.month.toString().padLeft(2, '0')}-${orderDate.day.toString().padLeft(2, '0')}';
          stats.last7DaysAmount[dayKey] = (stats.last7DaysAmount[dayKey] ?? 0.0) + amount;
          stats.last7DaysCount[dayKey] = (stats.last7DaysCount[dayKey] ?? 0) + 1;
        }
      }
    }
    return statsMap;
  }

  _MerchantEarningsStats _lookupStats(
    Map<String, _MerchantEarningsStats> statsMap,
    String docId,
    String shopName,
  ) {
    if (statsMap.containsKey(docId)) return statsMap[docId]!;
    final lowerName = shopName.trim().toLowerCase();
    if (statsMap.containsKey(lowerName)) return statsMap[lowerName]!;
    return _MerchantEarningsStats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Merchants & Earnings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0.5,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded, color: AppColors.primaryPurple),
            tooltip: 'Sort Merchants',
            onSelected: (val) => setState(() => _sortBy = val),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'default', child: Text('Default Order')),
              PopupMenuItem(value: 'today', child: Text('Highest Today Earnings')),
              PopupMenuItem(value: 'weekly', child: Text('Highest Weekly Earnings')),
              PopupMenuItem(value: 'total', child: Text('Highest Total Earnings')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(105),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search by shop name, owner or phone...',
                      hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textMuted),
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
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                tabs: const [
                  Tab(text: 'PENDING STORES'),
                  Tab(text: 'ACTIVE STORES'),
                  Tab(text: 'ALL MERCHANTS'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('merchants').snapshots(),
        builder: (context, merchantSnap) {
          if (merchantSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
          }

          final allMerchants = merchantSnap.hasData ? merchantSnap.data!.docs : <QueryDocumentSnapshot>[];

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('orders').snapshots(),
            builder: (context, orderSnap) {
              final orderDocs = orderSnap.hasData ? orderSnap.data!.docs : <QueryDocumentSnapshot>[];
              final statsMap = _computeEarningsByMerchant(orderDocs);

              double allToday = 0;
              double allWeekly = 0;
              double allTotal = 0;
              for (final s in statsMap.values) {
                allToday += s.todayAmount;
                allWeekly += s.weeklyAmount;
                allTotal += s.totalAmount;
              }

              return Column(
                children: [
                  // Platform-wide Merchant Earnings Strip
                  Container(
                    margin: const EdgeInsets.fromLTRB(14, 10, 14, 2),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E293B), Color(0xFF334155)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        _topSummaryCol('TODAY', '₹${allToday.toStringAsFixed(0)}', AppColors.accentGreen),
                        Container(width: 1, height: 28, color: Colors.white24),
                        _topSummaryCol('THIS WEEK', '₹${allWeekly.toStringAsFixed(0)}', AppColors.accentBlue),
                        Container(width: 1, height: 28, color: Colors.white24),
                        _topSummaryCol('TOTAL AMOUNT', '₹${allTotal.toStringAsFixed(0)}', AppColors.accentOrange),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildStoreList(allMerchants, statsMap, filter: 'pending'),
                        _buildStoreList(allMerchants, statsMap, filter: 'approved'),
                        _buildStoreList(allMerchants, statsMap, filter: 'all'),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _topSummaryCol(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: valueColor, fontSize: 15, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildStoreList(
    List<QueryDocumentSnapshot> docs,
    Map<String, _MerchantEarningsStats> statsMap, {
    required String filter,
  }) {
    final filtered = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = (data['status'] ?? 'pending').toString().toLowerCase();
      final isApp = data['isApproved'] == true || status == 'approved';

      if (filter == 'pending' && isApp) return false;
      if (filter == 'approved' && !isApp) return false;

      if (_searchQuery.isNotEmpty) {
        final shop = (data['shopName'] ?? data['storeName'] ?? data['name'] ?? '').toString().toLowerCase();
        final phone = (data['phone'] ?? '').toString().toLowerCase();
        final addr = (data['address'] ?? data['location'] ?? '').toString().toLowerCase();
        return shop.contains(_searchQuery) || phone.contains(_searchQuery) || addr.contains(_searchQuery);
      }
      return true;
    }).toList();

    if (_sortBy != 'default') {
      filtered.sort((a, b) {
        final da = a.data() as Map<String, dynamic>;
        final db = b.data() as Map<String, dynamic>;
        final sa = _lookupStats(statsMap, a.id, (da['shopName'] ?? da['storeName'] ?? '').toString());
        final sb = _lookupStats(statsMap, b.id, (db['shopName'] ?? db['storeName'] ?? '').toString());
        if (_sortBy == 'today') return sb.todayAmount.compareTo(sa.todayAmount);
        if (_sortBy == 'weekly') return sb.weeklyAmount.compareTo(sa.weeklyAmount);
        return sb.totalAmount.compareTo(sa.totalAmount);
      });
    }

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storefront_rounded, size: 48, color: AppColors.textMuted.withAlpha(120)),
            const SizedBox(height: 12),
            Text(
              filter == 'pending' ? 'No new store registrations waiting for review.' : 'No merchants found.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final doc = filtered[index];
        final data = doc.data() as Map<String, dynamic>;
        final String docId = doc.id;

        final String shopName = (data['shopName'] ?? data['storeName'] ?? data['name'] ?? 'Merchant Store').toString();
        final String ownerName = (data['ownerName'] ?? data['fullName'] ?? data['contactPerson'] ?? 'Owner').toString();
        final String phone = (data['phone'] ?? data['phoneNumber'] ?? 'No phone').toString();
        final String address = (data['address'] ?? data['storeAddress'] ?? data['location'] ?? 'Nellore, Andhra Pradesh').toString();
        final String status = (data['status'] ?? (data['isApproved'] == true ? 'approved' : 'pending')).toString().toLowerCase();
        final bool isApproved = status == 'approved';

        final stats = _lookupStats(statsMap, docId, shopName);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0.5,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isApproved ? AppColors.accentGreen.withAlpha(70) : AppColors.accentOrange.withAlpha(80),
              width: 1.2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.store_mall_directory_rounded, color: AppColors.primaryPurple, size: 22),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(shopName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: AppColors.textDark)),
                                Text('Owner: $ownerName • 📞 $phone', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                              ],
                            ),
                          ),
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
                        isApproved ? 'APPROVED ✅' : 'PENDING ⏳',
                        style: TextStyle(
                          color: isApproved ? AppColors.accentGreen : AppColors.accentOrange,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Today, Weekly & Total Earnings Strip
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _showMerchantEarningsSheet(context, shopName, stats),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        _earningMetric('TODAY', stats.todayAmount, stats.todayOrders, AppColors.accentGreen),
                        Container(width: 1, height: 28, color: AppColors.borderSubtle),
                        _earningMetric('THIS WEEK', stats.weeklyAmount, stats.weeklyOrders, AppColors.accentBlue),
                        Container(width: 1, height: 28, color: AppColors.borderSubtle),
                        _earningMetric('TOTAL EARNED', stats.totalAmount, stats.totalOrders, AppColors.primaryPurple),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded, size: 15, color: AppColors.accentRed),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        address,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textDark),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (stats.activeOrders > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.accentOrangeLight, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          '${stats.activeOrders} active',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accentOrange),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Approval & Control Buttons
                Row(
                  children: [
                    if (!isApproved)
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                          ),
                          onPressed: () => _updateMerchantStatus(context, docId, 'approved'),
                          icon: const Icon(Icons.check_circle_outline, size: 16),
                          label: const Text('APPROVE & ACTIVATE STORE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      )
                    else ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accentRed,
                            side: const BorderSide(color: AppColors.accentRed),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                          ),
                          onPressed: () => _updateMerchantStatus(context, docId, 'blocked'),
                          icon: const Icon(Icons.block, size: 16),
                          label: const Text('PAUSE STORE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryPurple,
                            side: const BorderSide(color: AppColors.primaryPurple),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                          ),
                          onPressed: () => _showMerchantEarningsSheet(context, shopName, stats),
                          icon: const Icon(Icons.bar_chart_rounded, size: 16),
                          label: const Text('EARNINGS REPORT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
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

  Widget _earningMetric(String title, double amount, int orders, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text('₹${amount.toStringAsFixed(0)}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: color)),
          Text('$orders ord', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  void _showMerchantEarningsSheet(BuildContext context, String shopName, _MerchantEarningsStats stats) {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final sevenDaysAgo = todayMidnight.subtract(const Duration(days: 6));
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.borderSubtle, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 12),
              Text('$shopName — Earnings', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _detailCard('Today', stats.todayAmount, '${stats.todayOrders} orders', AppColors.accentGreen),
                  const SizedBox(width: 8),
                  _detailCard('This Week', stats.weeklyAmount, '${stats.weeklyOrders} orders', AppColors.accentBlue),
                  const SizedBox(width: 8),
                  _detailCard('Total', stats.totalAmount, '${stats.totalOrders} orders', AppColors.primaryPurple),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bgLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text('Today Online/UPI: ₹${stats.todayUpi.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryPurple)),
                    Text('Today COD: ₹${stats.todayCod.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accentOrange)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Last 7 Days Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
              const SizedBox(height: 8),
              ...List.generate(7, (i) {
                final day = sevenDaysAgo.add(Duration(days: i));
                final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                final amt = stats.last7DaysAmount[key] ?? 0.0;
                final cnt = stats.last7DaysCount[key] ?? 0;
                final dayLabel = '${weekdays[day.weekday - 1]} ${day.day}/${day.month}';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 82,
                        child: Text(dayLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: Text('$cnt orders', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                      ),
                      Text(
                        '₹${amt.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: amt > 0 ? AppColors.accentGreen : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _detailCard(String title, double amount, String sub, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 3),
            Text('₹${amount.toStringAsFixed(0)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
            Text(sub, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
