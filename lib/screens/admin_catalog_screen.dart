import '../utils/parse_utils.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_colors.dart';

class AdminCatalogScreen extends StatefulWidget {
  final bool showAppBar;
  const AdminCatalogScreen({super.key, this.showAppBar = true});

  @override
  State<AdminCatalogScreen> createState() => _AdminCatalogScreenState();
}

class _AdminCatalogScreenState extends State<AdminCatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openAddMasterProductDialog({String? docId, Map<String, dynamic>? data}) {
    final titleController = TextEditingController(text: (data?['name'] ?? data?['title'] ?? '').toString());
    final catController = TextEditingController(text: (data?['category'] ?? 'Groceries').toString());
    final unitController = TextEditingController(text: (data?['unit'] ?? '1 kg').toString());
    final mrpController = TextEditingController(text: ParseUtils.toDouble(data?['mrp'] ?? data?['marketPrice'], 50).toStringAsFixed(0));
    final imageController = TextEditingController(text: (data?['imageUrl'] ?? data?['image'] ?? '').toString());
    final barcodeController = TextEditingController(text: (data?['barcode'] ?? '').toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(docId == null ? 'Add Master Product' : 'Edit Master Product', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Product Title & Brand', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  hintText: 'e.g. Aashirvaad Superior MP Atta (5kg)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: catController,
                          decoration: InputDecoration(
                            hintText: 'Groceries / Veg',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Unit / Weight', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: unitController,
                          decoration: InputDecoration(
                            hintText: '1 kg / 500g',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Standard MRP (₹)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: mrpController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Barcode (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: barcodeController,
                          decoration: InputDecoration(
                            hintText: '8901030...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('High-Res Image URL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              TextField(
                controller: imageController,
                decoration: InputDecoration(
                  hintText: 'https://images.unsplash.com/... or CDN link',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple, foregroundColor: Colors.white),
            onPressed: () async {
              final title = titleController.text.trim();
              if (title.isEmpty) return;

              Navigator.pop(ctx);

              final itemData = {
                'name': title,
                'title': title,
                'category': catController.text.trim(),
                'unit': unitController.text.trim(),
                'marketPrice': double.tryParse(mrpController.text.trim()) ?? 50.0,
                'mrp': double.tryParse(mrpController.text.trim()) ?? 50.0,
                'imageUrl': imageController.text.trim(),
                'barcode': barcodeController.text.trim(),
                'updatedAt': FieldValue.serverTimestamp(),
              };

              if (docId != null) {
                await FirebaseFirestore.instance.collection('master_products').doc(docId).update(itemData);
              } else {
                itemData['createdAt'] = FieldValue.serverTimestamp();
                await FirebaseFirestore.instance.collection('master_products').add(itemData);
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Master Product "$title" saved to catalog!')),
                );
              }
            },
            child: const Text('SAVE TO MASTER CATALOG'),
          ),
        ],
      ),
    );
  }

  // Push Master Catalog Product directly to a Merchant's Store
  void _openPushToStoreDialog(BuildContext context, Map<String, dynamic> prodData) {
    String? selectedMerchantId;
    String selectedStoreName = '';
    final priceController = TextEditingController(text: ((prodData['marketPrice'] ?? 50) * 0.8).toStringAsFixed(0));
    final stockController = TextEditingController(text: '20');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setPushState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.send_to_mobile_rounded, color: AppColors.primaryPurple, size: 22),
                const SizedBox(width: 8),
                const Text('Push Product to Store', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Product: ${prodData['name'] ?? prodData['title']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const Divider(height: 16),
                  const Text('Select Target Merchant Store:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('merchants').snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) return const CircularProgressIndicator();
                      final mDocs = snap.data!.docs;
                      if (mDocs.isEmpty) return const Text('No active merchants available.');

                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        initialValue: selectedMerchantId,
                        hint: const Text('Choose Store...', style: TextStyle(fontSize: 12)),
                        items: mDocs.map((m) {
                          final mData = m.data() as Map<String, dynamic>;
                          final sName = (mData['shopName'] ?? mData['storeName'] ?? mData['name'] ?? 'Store').toString();
                          return DropdownMenuItem<String>(
                            value: m.id,
                            child: Text(sName, style: const TextStyle(fontSize: 12)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setPushState(() {
                            selectedMerchantId = val;
                            final match = mDocs.firstWhere((element) => element.id == val);
                            final matchData = match.data() as Map<String, dynamic>;
                            selectedStoreName = (matchData['shopName'] ?? matchData['storeName'] ?? matchData['name'] ?? 'Store').toString();
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Merchant Cost (₹):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: priceController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Initial Stock:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: stockController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                            ),
                          ],
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
                  if (selectedMerchantId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a merchant store!')));
                    return;
                  }

                  Navigator.pop(ctx);

                  final double mCost = double.tryParse(priceController.text.trim()) ?? 40.0;
                  const double defaultMargin = 5.0;
                  final double custPrice = mCost + defaultMargin;
                  final double mrp = ParseUtils.toDouble(prodData['marketPrice'], custPrice);
                  final int stock = int.tryParse(stockController.text.trim()) ?? 20;

                  // Create approved product in target store
                  await FirebaseFirestore.instance.collection('products').add({
                    'name': prodData['name'] ?? prodData['title'],
                    'title': prodData['name'] ?? prodData['title'],
                    'category': prodData['category'] ?? 'General',
                    'unit': prodData['unit'] ?? '1 item',
                    'merchantId': selectedMerchantId,
                    'storeName': selectedStoreName,
                    'shopName': selectedStoreName,
                    'merchantPrice': mCost,
                    'adminMargin': defaultMargin,
                    'price': custPrice,
                    'customerPrice': custPrice,
                    'marketPrice': mrp,
                    'stock': stock,
                    'imageUrl': prodData['imageUrl'] ?? '',
                    'barcode': prodData['barcode'] ?? '',
                    'isApproved': true,
                    'isApprovedByAdmin': true,
                    'status': 'approved',
                    'approvalStatus': 'approved',
                    'createdAt': FieldValue.serverTimestamp(),
                  });

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('✅ Product successfully pushed to "$selectedStoreName" at ₹$custPrice!')),
                    );
                  }
                },
                child: const Text('PUSH TO STORE'),
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
      appBar: AppBar(
        title: const Text('Master Catalog & Image Push', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0.5,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(55),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search master catalog products...',
                  hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textMuted),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('master_products').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
          }

          final allDocs = snapshot.hasData ? snapshot.data!.docs : <QueryDocumentSnapshot>[];
          final filtered = allDocs.where((d) {
            if (_searchQuery.isEmpty) return true;
            final data = d.data() as Map<String, dynamic>;
            final name = (data['name'] ?? data['title'] ?? '').toString().toLowerCase();
            final cat = (data['category'] ?? '').toString().toLowerCase();
            return name.contains(_searchQuery) || cat.contains(_searchQuery);
          }).toList();

          if (filtered.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.menu_book_rounded, size: 48, color: AppColors.textMuted),
                  const SizedBox(height: 12),
                  const Text('No products in Master Catalog yet.', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple, foregroundColor: Colors.white),
                    onPressed: () => _openAddMasterProductDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('ADD MASTER PRODUCT'),
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
              final name = (data['name'] ?? data['title'] ?? 'Master Product').toString();
              final category = (data['category'] ?? 'General').toString();
              final unit = (data['unit'] ?? '1 item').toString();
              final double mrp = ParseUtils.toDouble(data['marketPrice'] ?? data['mrp']);
              final String imageUrl = (data['imageUrl'] ?? '').toString();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0.5,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.borderSubtle)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 55,
                          height: 55,
                          color: const Color(0xFFF1F5F9),
                          child: imageUrl.isNotEmpty && imageUrl.startsWith('http')
                              ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.image, color: Colors.grey))
                              : const Icon(Icons.inventory_2_outlined, color: AppColors.primaryPurple, size: 24),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                            Text('🏷️ $category • $unit • MRP: ₹$mrp', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryLight,
                          foregroundColor: AppColors.primaryPurple,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _openPushToStoreDialog(context, data),
                        icon: const Icon(Icons.send_rounded, size: 14),
                        label: const Text('PUSH', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        onPressed: () => _openAddMasterProductDialog(),
        icon: const Icon(Icons.add),
        label: const Text('ADD MASTER PRODUCT'),
      ),
    );
  }
}
