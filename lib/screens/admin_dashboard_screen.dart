import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_colors.dart';
import '../utils/parse_utils.dart';
import 'admin_orders_screen.dart';
import 'admin_products_screen.dart';
import 'admin_merchants_screen.dart';
import 'admin_payouts_screen.dart';
import 'admin_catalog_hub_screen.dart';
import 'admin_delivery_partners_screen.dart';
import 'admin_coupons_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_customers_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _currentIndex = 0;

  void _switchTab(int idx) {
    if (mounted) setState(() => _currentIndex = idx);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _AdminOverviewTab(onNavigateTab: _switchTab),
      const AdminOrdersScreen(),
      const AdminProductsScreen(),
      const AdminMerchantsScreen(),
      const AdminPayoutsScreen(),
      const AdminCatalogHubScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _switchTab,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primaryPurple,
        unselectedItemColor: AppColors.textMuted,
        selectedFontSize: 11,
        unselectedFontSize: 10.5,
        elevation: 6,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard_rounded),
            label: 'Overview',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_shipping_outlined),
            activeIcon: Icon(Icons.local_shipping_rounded),
            label: 'Orders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2_rounded),
            label: 'Products',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.storefront_outlined),
            activeIcon: Icon(Icons.storefront_rounded),
            label: 'Merchants',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.payments_outlined),
            activeIcon: Icon(Icons.payments_rounded),
            label: 'Payouts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_outlined),
            activeIcon: Icon(Icons.grid_view_rounded),
            label: 'Catalog',
          ),
        ],
      ),
    );
  }
}

class _AdminOverviewTab extends StatefulWidget {
  final ValueChanged<int> onNavigateTab;
  const _AdminOverviewTab({required this.onNavigateTab});

  @override
  State<_AdminOverviewTab> createState() => _AdminOverviewTabState();
}

class _AdminOverviewTabState extends State<_AdminOverviewTab> {
  bool _isDeleting = false;

  Future<void> _deleteAllOrders(BuildContext context) async {
    setState(() => _isDeleting = true);
    final messenger = ScaffoldMessenger.of(context);
    final collectionRef = FirebaseFirestore.instance.collection('orders');

    try {
      final snapshot = await collectionRef.get();
      if (snapshot.docs.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('Orders collection is already empty.')));
        return;
      }

      WriteBatch batch = FirebaseFirestore.instance.batch();
      int counter = 0;

      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
        counter++;
        if (counter % 500 == 0) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
        }
      }

      if (counter % 500 != 0) {
        await batch.commit();
      }

      messenger.showSnackBar(SnackBar(content: Text('✅ $counter orders deleted successfully!')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Orders?'),
        content: const Text('This will permanently delete all order documents from Firestore orders collection. Use only for testing cleanup.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRed),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteAllOrders(context);
            },
            child: const Text('DELETE ALL', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings_rounded, color: AppColors.primaryPurple, size: 24),
            SizedBox(width: 8),
            Text('Flash2Mart Admin Central', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.textDark)),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded, color: AppColors.textMuted),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Admin Greeting Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryPurple, Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.shield_rounded, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Super Admin Console', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('Logged in as: ${user?.email ?? 'Administrator'}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        const SizedBox(height: 4),
                        const Text('Nellore, AP Ecosystem Controller', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Live Revenue & Orders Summary
            _buildLiveEarningsSummary(),
            const SizedBox(height: 18),

            // Quick Management Controls
            const Text('Fleet, Promos & Pricing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textDark)),
            const SizedBox(height: 10),
            Row(
              children: [
                _quickTile(
                  icon: Icons.delivery_dining_rounded,
                  label: 'Riders & COD',
                  color: AppColors.accentGreen,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDeliveryPartnersScreen())),
                ),
                const SizedBox(width: 8),
                _quickTile(
                  icon: Icons.confirmation_number_rounded,
                  label: 'Coupons',
                  color: AppColors.primaryPurple,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminCouponsScreen())),
                ),
                const SizedBox(width: 8),
                _quickTile(
                  icon: Icons.tune_rounded,
                  label: 'Pricing/Surge',
                  color: AppColors.accentOrange,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSettingsScreen())),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Live Metrics Grid
            const Text('Live Operations Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textDark)),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildMetricCard(
                  title: 'Total Orders',
                  collection: 'orders',
                  color: AppColors.primaryPurple,
                  icon: Icons.receipt_long_rounded,
                  onTap: () => widget.onNavigateTab(1),
                ),
                const SizedBox(width: 10),
                _buildMetricCard(
                  title: 'Merchants',
                  collection: 'merchants',
                  color: AppColors.accentOrange,
                  icon: Icons.storefront_rounded,
                  onTap: () => widget.onNavigateTab(3),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildMetricCard(
                  title: 'Products Live',
                  collection: 'products',
                  color: AppColors.accentGreen,
                  icon: Icons.inventory_2_rounded,
                  onTap: () => widget.onNavigateTab(2),
                ),
                const SizedBox(width: 10),
                _buildMetricCard(
                  title: 'Customers',
                  collection: 'users',
                  color: AppColors.accentBlue,
                  icon: Icons.people_rounded,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminCustomersScreen())),
                ),
              ],
            ),
            const SizedBox(height: 22),

            // Quick Status Actions
            const Text('Database & Maintenance Tools', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textDark)),
            const SizedBox(height: 10),
            Card(
              color: Colors.white,
              elevation: 0.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.borderSubtle)),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.accentRedLight, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.delete_sweep_rounded, color: AppColors.accentRed, size: 24),
                ),
                title: const Text('Delete All Orders (Test Reset)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                subtitle: const Text('Cleans up test orders from orders collection.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                trailing: _isDeleting
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentRed))
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRedLight, foregroundColor: AppColors.accentRed, elevation: 0),
                        onPressed: () => _showDeleteConfirmation(context),
                        child: const Text('PURGE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withAlpha(70)),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: color.withAlpha(25),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textDark)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveEarningsSummary() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.hasData ? snapshot.data!.docs : <QueryDocumentSnapshot>[];
        final now = DateTime.now();
        final todayMidnight = DateTime(now.year, now.month, now.day);
        final sevenDaysAgo = todayMidnight.subtract(const Duration(days: 6));

        double todayRevenue = 0;
        int todayCount = 0;
        double weeklyRevenue = 0;
        int weeklyCount = 0;
        double totalRevenue = 0;
        int activeCount = 0;

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final status = (data['orderStatus'] ?? data['status'] ?? data['currentStatus'] ?? '').toString().toLowerCase();
          final isDelivered = status == 'delivered' || status == 'completed';
          final isCancelled = status == 'cancelled' || status == 'rejected';

          if (!isDelivered && !isCancelled) activeCount++;
          if (!isDelivered) continue;

          final amt = ParseUtils.toDouble(data['grandTotal'] ?? data['totalAmount'] ?? data['itemTotal']);
          totalRevenue += amt;

          DateTime? orderDate;
          final dynamic ts = data['createdAt'] ?? data['acceptedAt'] ?? data['updatedAt'];
          if (ts is Timestamp) orderDate = ts.toDate();

          if (orderDate != null) {
            if (!orderDate.isBefore(todayMidnight)) {
              todayRevenue += amt;
              todayCount++;
            }
            if (!orderDate.isBefore(sevenDaysAgo)) {
              weeklyRevenue += amt;
              weeklyCount++;
            }
          }
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Platform Revenue & Live Orders', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textDark)),
                  InkWell(
                    onTap: () => widget.onNavigateTab(1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        '$activeCount Active • Track →',
                        style: const TextStyle(color: AppColors.primaryPurple, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _revPill('TODAY', '₹${todayRevenue.toStringAsFixed(0)}', '$todayCount ord', AppColors.accentGreen),
                  const SizedBox(width: 8),
                  _revPill('THIS WEEK', '₹${weeklyRevenue.toStringAsFixed(0)}', '$weeklyCount ord', AppColors.accentBlue),
                  const SizedBox(width: 8),
                  _revPill('TOTAL', '₹${totalRevenue.toStringAsFixed(0)}', 'All time', AppColors.primaryPurple),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _revPill(String label, String amount, String sub, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(55)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(amount, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color)),
            Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String collection,
    required Color color,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection(collection).snapshots(),
        builder: (context, snapshot) {
          final int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$count', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: color)),
                        Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}