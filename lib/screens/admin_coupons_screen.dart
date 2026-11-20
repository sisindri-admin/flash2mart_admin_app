import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_colors.dart';
import '../utils/parse_utils.dart';

class AdminCouponsScreen extends StatefulWidget {
  final bool showAppBar;
  const AdminCouponsScreen({super.key, this.showAppBar = true});

  @override
  State<AdminCouponsScreen> createState() => _AdminCouponsScreenState();
}

class _AdminCouponsScreenState extends State<AdminCouponsScreen> {
  Future<void> _toggleActive(BuildContext context, String docId, bool currentVal) async {
    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance.collection('coupons').doc(docId).update({
      'isActive': !currentVal,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(!currentVal ? 'Coupon activated!' : 'Coupon paused.'),
        backgroundColor: !currentVal ? AppColors.accentGreen : AppColors.accentOrange,
      ),
    );
  }

  Future<void> _deleteCoupon(BuildContext context, String docId) async {
    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance.collection('coupons').doc(docId).delete();
    messenger.showSnackBar(const SnackBar(content: Text('Coupon deleted.'), backgroundColor: AppColors.accentRed));
  }

  void _showCouponDialog(BuildContext context, {String? docId, Map<String, dynamic>? existing}) {
    final codeCtrl = TextEditingController(text: (existing?['code'] ?? '').toString());
    final titleCtrl = TextEditingController(text: (existing?['title'] ?? existing?['description'] ?? '').toString());
    final valCtrl = TextEditingController(text: (existing?['discountValue'] ?? existing?['amount'] ?? '').toString());
    final minCtrl = TextEditingController(text: (existing?['minOrderAmount'] ?? '199').toString());
    final maxCtrl = TextEditingController(text: (existing?['maxDiscount'] ?? '100').toString());
    String discountType = (existing?['discountType'] ?? 'flat').toString();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(docId == null ? 'Create Promo Coupon' : 'Edit Coupon'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Coupon Code (e.g. WELCOME50)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Subtitle / Offer Text', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: discountType == 'percent' ? 'percent' : 'flat',
                    decoration: const InputDecoration(labelText: 'Discount Type', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'flat', child: Text('Flat ₹ Off')),
                      DropdownMenuItem(value: 'percent', child: Text('Percentage (%) Off')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => discountType = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: valCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: discountType == 'percent' ? 'Discount %' : 'Discount Amount (₹)',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Min Order (₹)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: maxCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Max Off (₹)', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple, foregroundColor: Colors.white),
                onPressed: () async {
                  final code = codeCtrl.text.trim().toUpperCase();
                  if (code.isEmpty) return;
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);

                  final payload = {
                    'code': code,
                    'title': titleCtrl.text.trim().isEmpty ? 'Special Flash2Mart Offer' : titleCtrl.text.trim(),
                    'description': titleCtrl.text.trim(),
                    'discountType': discountType,
                    'discountValue': ParseUtils.toDouble(valCtrl.text),
                    'amount': ParseUtils.toDouble(valCtrl.text),
                    'minOrderAmount': ParseUtils.toDouble(minCtrl.text, 199),
                    'maxDiscount': ParseUtils.toDouble(maxCtrl.text, 100),
                    'isActive': existing?['isActive'] ?? true,
                    'updatedAt': FieldValue.serverTimestamp(),
                    if (docId == null) 'createdAt': FieldValue.serverTimestamp(),
                  };

                  await FirebaseFirestore.instance.collection('coupons').doc(docId ?? code).set(payload, SetOptions(merge: true));
                  messenger.showSnackBar(
                    SnackBar(content: Text('✅ Coupon $code saved!'), backgroundColor: AppColors.accentGreen),
                  );
                },
                child: const Text('SAVE COUPON'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Coupons & Promo Codes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textDark,
              elevation: 0.5,
            )
          : null,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        onPressed: () => _showCouponDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('NEW COUPON', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('coupons').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
          }
          final docs = snap.hasData ? snap.data!.docs : <QueryDocumentSnapshot>[];
          if (docs.isEmpty) {
            return const Center(
              child: Text('No coupons yet. Tap NEW COUPON to create one!', style: TextStyle(color: AppColors.textMuted)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
            itemCount: docs.length,
            itemBuilder: (context, idx) {
              final doc = docs[idx];
              final d = doc.data() as Map<String, dynamic>;
              final code = (d['code'] ?? doc.id).toString();
              final title = (d['title'] ?? d['description'] ?? '').toString();
              final type = (d['discountType'] ?? 'flat').toString();
              final val = ParseUtils.toDouble(d['discountValue'] ?? d['amount']);
              final minOrd = ParseUtils.toDouble(d['minOrderAmount']);
              final isActive = d['isActive'] != false;

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                color: Colors.white,
                elevation: 0.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isActive ? AppColors.accentGreen.withAlpha(80) : AppColors.borderSubtle),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.confirmation_number_rounded, color: AppColors.primaryPurple),
                  ),
                  title: Row(
                    children: [
                      Text(code, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.accentGreenLight, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          type == 'percent' ? '${val.toStringAsFixed(0)}% OFF' : '₹${val.toStringAsFixed(0)} OFF',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accentGreen),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text('$title • Min order ₹${minOrd.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: isActive,
                        activeThumbColor: AppColors.accentGreen,
                        onChanged: (_) => _toggleActive(context, doc.id, isActive),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 19, color: AppColors.primaryPurple),
                        onPressed: () => _showCouponDialog(context, docId: doc.id, existing: d),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 19, color: AppColors.accentRed),
                        onPressed: () => _deleteCoupon(context, doc.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
