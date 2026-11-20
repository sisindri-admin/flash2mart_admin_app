import '../utils/parse_utils.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_colors.dart';

class AdminPayoutsScreen extends StatefulWidget {
  const AdminPayoutsScreen({super.key});

  @override
  State<AdminPayoutsScreen> createState() => _AdminPayoutsScreenState();
}

class _AdminPayoutsScreenState extends State<AdminPayoutsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Payout Settlements', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryPurple,
          indicatorWeight: 3,
          labelColor: AppColors.primaryPurple,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('payout_requests').where('status', isEqualTo: 'pending').snapshots(),
              builder: (context, snap) {
                final int count = snap.hasData ? snap.data!.docs.length : 0;
                return Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('PENDING PAYOUTS'),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.accentRed, borderRadius: BorderRadius.circular(10)),
                          child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const Tab(text: 'SETTLED HISTORY'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('payout_requests').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
          }

          final allDocs = snapshot.hasData ? snapshot.data!.docs : <QueryDocumentSnapshot>[];

          return TabBarView(
            controller: _tabController,
            children: [
              _buildPayoutList(allDocs, isPending: true),
              _buildPayoutList(allDocs, isPending: false),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPayoutList(List<QueryDocumentSnapshot> docs, {required bool isPending}) {
    final filtered = docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final s = (data['status'] ?? 'pending').toString().toLowerCase();
      if (isPending) {
        return s == 'pending' || s == 'processing';
      } else {
        return s == 'settled' || s == 'transferred' || s == 'rejected';
      }
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isPending ? Icons.check_circle_outline_rounded : Icons.history_rounded, size: 48, color: AppColors.textMuted.withAlpha(120)),
            const SizedBox(height: 12),
            Text(
              isPending ? 'No pending withdrawal requests. All settled!' : 'No payout history yet.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5, fontWeight: FontWeight.w600),
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
        final String docId = doc.id;

        final bool isRider = (data['role'] ?? '').toString() == 'delivery_partner' || (data['partnerId'] ?? '').toString().isNotEmpty;
        final String storeName = (data['storeName'] ?? data['merchantName'] ?? (isRider ? 'Delivery Partner' : 'Merchant Store')).toString();
        final double amount = ParseUtils.toDouble(data['amount']);
        final String status = (data['status'] ?? 'pending').toString().toLowerCase();
        final String utr = (data['utr'] ?? data['transactionReference'] ?? '').toString();

        final dynamic bankRaw = data['bankDetails'];
        Map<String, dynamic> bank = {};
        if (bankRaw is Map<String, dynamic>) {
          bank = bankRaw;
        }

        final String upi = (bank['upiId'] ?? data['upiId'] ?? '').toString();
        final String accHolder = (bank['accountHolder'] ?? '').toString();
        final String accNo = (bank['accountNumber'] ?? '').toString();
        final String ifsc = (bank['ifscCode'] ?? '').toString();
        final String bankName = (bank['bankName'] ?? '').toString();

        final bool isSettled = status == 'settled' || status == 'transferred';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0.5,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isSettled ? AppColors.accentGreen.withAlpha(60) : AppColors.accentOrange.withAlpha(80),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(storeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textDark)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isRider ? const Color(0xFFECFDF5) : const Color(0xFFF3E8FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isRider ? 'RIDER' : 'MERCHANT',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  color: isRider ? AppColors.accentGreen : AppColors.primaryPurple,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text('Req ID: #$docId', style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                      ],
                    ),
                    Text(
                      '₹${amount.toStringAsFixed(0)}',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: isSettled ? AppColors.accentGreen : AppColors.accentOrange),
                    ),
                  ],
                ),
                const Divider(height: 18),

                // Bank & UPI Details Card
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (upi.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.qr_code_rounded, size: 16, color: AppColors.primaryPurple),
                            const SizedBox(width: 6),
                            const Text('UPI ID: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                            SelectableText(upi, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.primaryPurple)),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (accNo.isNotEmpty) ...[
                        Text('A/C Name: $accHolder', style: const TextStyle(fontSize: 11.5)),
                        SelectableText('A/C No: $accNo ($bankName)', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        SelectableText('IFSC: $ifsc', style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
                      ],
                    ],
                  ),
                ),

                if (isSettled && utr.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.accentGreenLight, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.accentGreen, size: 16),
                        const SizedBox(width: 6),
                        Expanded(child: SelectableText('Bank UTR: $utr', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.accentGreen))),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Action Button: Settle with UTR
                if (!isSettled)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryPurple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () => _openSettleDialog(context, docId, data),
                          icon: const Icon(Icons.payment_rounded, size: 16),
                          label: const Text('MARK SETTLED (ENTER UTR)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openSettleDialog(BuildContext context, String docId, Map<String, dynamic> data) {
    final utrController = TextEditingController();
    final double amount = ParseUtils.toDouble(data['amount']);
    final String merchantId = (data['merchantId'] ?? '').toString();
    final String partnerId = (data['partnerId'] ?? '').toString();
    final bool isRider = (data['role'] ?? '').toString() == 'delivery_partner' || partnerId.isNotEmpty;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.verified_rounded, color: AppColors.accentGreen, size: 24),
            const SizedBox(width: 8),
            Text('Settle Payout ₹${amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${isRider ? 'Rider' : 'Merchant'}: ${data['storeName'] ?? data['merchantName'] ?? (isRider ? 'Delivery Partner' : 'Store')}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 12),
            const Text('Enter Bank / UPI UTR Reference Number:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: utrController,
              decoration: InputDecoration(
                hintText: 'e.g. UPI/4312894129 or NEFT12948',
                hintStyle: const TextStyle(fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentGreen, foregroundColor: Colors.white),
            onPressed: () async {
              final utr = utrController.text.trim();
              if (utr.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter Bank UTR number!')));
                return;
              }

              Navigator.pop(ctx);

              final batch = FirebaseFirestore.instance.batch();

              // Update payout request doc
              final pRef = FirebaseFirestore.instance.collection('payout_requests').doc(docId);
              batch.update(pRef, {
                'status': 'settled',
                'utr': utr,
                'transactionReference': utr,
                'settledAt': FieldValue.serverTimestamp(),
              });

              // Update merchant or delivery partner balance
              if (isRider && partnerId.isNotEmpty) {
                final dRef = FirebaseFirestore.instance.collection('delivery_partners').doc(partnerId);
                batch.set(dRef, {
                  'pendingPayoutAmount': FieldValue.increment(-amount),
                  'totalSettledPayouts': FieldValue.increment(amount),
                  'lastSettledAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
              } else if (merchantId.isNotEmpty) {
                final mRef = FirebaseFirestore.instance.collection('merchants').doc(merchantId);
                batch.set(mRef, {
                  'pendingPayoutAmount': FieldValue.increment(-amount),
                  'totalSettledPayouts': FieldValue.increment(amount),
                  'lastSettledAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
              }

              await batch.commit();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✅ Payout of ₹${amount.toStringAsFixed(0)} marked as Settled with UTR $utr!')),
                );
              }
            },
            child: const Text('CONFIRM SETTLED'),
          ),
        ],
      ),
    );
  }
}
