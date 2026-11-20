import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_colors.dart';
import '../utils/parse_utils.dart';

class _CustomerOrderStats {
  int totalOrders = 0;
  double totalSpend = 0;
}

class AdminCustomersScreen extends StatefulWidget {
  final bool showAppBar;
  const AdminCustomersScreen({super.key, this.showAppBar = true});

  @override
  State<AdminCustomersScreen> createState() => _AdminCustomersScreenState();
}

class _AdminCustomersScreenState extends State<AdminCustomersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleBlock(BuildContext context, String uid, String name, bool currentlyBlocked) async {
    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'isBlocked': !currentlyBlocked,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    messenger.showSnackBar(
      SnackBar(
        content: Text(!currentlyBlocked ? '🚫 $name blocked.' : '✅ $name unblocked.'),
        backgroundColor: !currentlyBlocked ? AppColors.accentRed : AppColors.accentGreen,
      ),
    );
  }

  void _showWalletRefundDialog(BuildContext context, String uid, String name, double currentWallet) {
    final amtCtrl = TextEditingController();
    final reasonCtrl = TextEditingController(text: 'Order Issue Refund / Goodwill Credit');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Wallet Credit • $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Wallet Balance: ₹${currentWallet.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.primaryPurple)),
            const SizedBox(height: 12),
            TextField(
              controller: amtCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Credit Amount (₹)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason / Order ID',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentGreen, foregroundColor: Colors.white),
            onPressed: () async {
              final amt = ParseUtils.toDouble(amtCtrl.text);
              if (amt <= 0) return;
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);

              await FirebaseFirestore.instance.collection('users').doc(uid).set({
                'walletBalance': FieldValue.increment(amt),
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));

              await FirebaseFirestore.instance.collection('wallet_transactions').add({
                'userId': uid,
                'customerName': name,
                'amount': amt,
                'type': 'credit',
                'reason': reasonCtrl.text.trim(),
                'issuedBy': 'Admin',
                'createdAt': FieldValue.serverTimestamp(),
              });

              messenger.showSnackBar(
                SnackBar(
                  content: Text('✅ Credited ₹${amt.toStringAsFixed(0)} to $name\'s wallet!'),
                  backgroundColor: AppColors.accentGreen,
                ),
              );
            },
            child: const Text('CREDIT WALLET'),
          ),
        ],
      ),
    );
  }

  Map<String, _CustomerOrderStats> _computeCustomerOrders(List<QueryDocumentSnapshot> orderDocs) {
    final Map<String, _CustomerOrderStats> map = {};
    for (final doc in orderDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final uid = (d['userId'] ?? '').toString().trim();
      if (uid.isEmpty) continue;
      final stats = map.putIfAbsent(uid, () => _CustomerOrderStats());
      stats.totalOrders++;
      final status = (d['orderStatus'] ?? d['status'] ?? '').toString().toLowerCase();
      if (status != 'cancelled' && status != 'rejected') {
        stats.totalSpend += ParseUtils.toDouble(d['grandTotal'] ?? d['totalAmount'] ?? d['itemTotal']);
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Customers & Wallet Refunds', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textDark,
              elevation: 0.5,
            )
          : null,
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search customer name, phone or email...',
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
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
                }
                final userDocs = userSnap.hasData ? userSnap.data!.docs : <QueryDocumentSnapshot>[];

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('orders').snapshots(),
                  builder: (context, orderSnap) {
                    final orderDocs = orderSnap.hasData ? orderSnap.data!.docs : <QueryDocumentSnapshot>[];
                    final statsMap = _computeCustomerOrders(orderDocs);

                    final filtered = userDocs.where((doc) {
                      if (_searchQuery.isEmpty) return true;
                      final d = doc.data() as Map<String, dynamic>;
                      final name = (d['name'] ?? d['fullName'] ?? '').toString().toLowerCase();
                      final phone = (d['phone'] ?? d['phoneNumber'] ?? '').toString().toLowerCase();
                      final email = (d['email'] ?? '').toString().toLowerCase();
                      return name.contains(_searchQuery) || phone.contains(_searchQuery) || email.contains(_searchQuery);
                    }).toList();

                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text('No customers found.', style: TextStyle(color: AppColors.textMuted)),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: filtered.length,
                      itemBuilder: (context, idx) {
                        final doc = filtered[idx];
                        final d = doc.data() as Map<String, dynamic>;
                        final name = (d['name'] ?? d['fullName'] ?? 'Flash2Mart Customer').toString();
                        final phone = (d['phone'] ?? d['phoneNumber'] ?? 'No phone').toString();
                        final wallet = ParseUtils.toDouble(d['walletBalance']);
                        final isBlocked = d['isBlocked'] == true;
                        final stats = statsMap[doc.id] ?? _CustomerOrderStats();

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          color: Colors.white,
                          elevation: 0.5,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isBlocked ? AppColors.accentRed.withAlpha(90) : AppColors.borderSubtle,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(13),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 19,
                                      backgroundColor: isBlocked ? AppColors.accentRedLight : AppColors.accentBlueLight,
                                      child: Icon(
                                        Icons.person_rounded,
                                        color: isBlocked ? AppColors.accentRed : AppColors.accentBlue,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                          Text('📞 $phone', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isBlocked ? AppColors.accentRedLight : AppColors.accentGreenLight,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        isBlocked ? 'BLOCKED' : 'ACTIVE',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          color: isBlocked ? AppColors.accentRed : AppColors.accentGreen,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.bgLight,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.borderSubtle),
                                  ),
                                  child: Row(
                                    children: [
                                      _col('ORDERS', '${stats.totalOrders}', AppColors.accentBlue),
                                      _col('TOTAL SPENT', '₹${stats.totalSpend.toStringAsFixed(0)}', AppColors.primaryPurple),
                                      _col('WALLET', '₹${wallet.toStringAsFixed(0)}', AppColors.accentGreen),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.accentGreen,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: () => _showWalletRefundDialog(context, doc.id, name, wallet),
                                        icon: const Icon(Icons.account_balance_wallet_rounded, size: 15),
                                        label: const Text('+ WALLET REFUND', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: isBlocked ? AppColors.accentGreen : AppColors.accentRed,
                                        side: BorderSide(color: isBlocked ? AppColors.accentGreen : AppColors.accentRed),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => _toggleBlock(context, doc.id, name, isBlocked),
                                      child: Text(isBlocked ? 'UNBLOCK' : 'BLOCK',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
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

  Widget _col(String label, String val, Color color) {
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
