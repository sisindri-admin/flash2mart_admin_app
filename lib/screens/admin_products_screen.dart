import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/app_colors.dart';
import '../utils/parse_utils.dart';
import '../utils/image_helper.dart';

class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> with SingleTickerProviderStateMixin {
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

  List<String> _extractImages(Map<String, dynamic> data) {
    final List<String> imgs = [];
    if (data['images'] is List) {
      for (final it in (data['images'] as List)) {
        final s = it.toString().trim();
        if (s.isNotEmpty && !imgs.contains(s)) imgs.add(s);
      }
    }
    final primary = (data['imageBase64'] ?? data['imageUrl'] ?? data['image'] ?? '').toString().trim();
    if (primary.isNotEmpty && !imgs.contains(primary)) {
      imgs.insert(0, primary);
    }
    return imgs;
  }

  Future<void> _confirmDeleteProduct(BuildContext context, String docId, String name) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Product?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to permanently delete "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('products').doc(docId).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🗑️ "$name" deleted.'), backgroundColor: AppColors.accentRed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Products, Approval & Markup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17.5)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: 'Add Product directly to Category',
            icon: const Icon(Icons.add_circle_rounded, color: AppColors.primaryPurple, size: 28),
            onPressed: () => _openMarkupApprovalDialog(context, null, null),
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
                      hintText: 'Search by product, shop, category or sub-category...',
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
                indicatorColor: AppColors.primaryPurple,
                indicatorWeight: 3,
                labelColor: AppColors.primaryPurple,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                tabs: [
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('products').snapshots(),
                    builder: (context, snap) {
                      int pendingCount = 0;
                      if (snap.hasData) {
                        pendingCount = snap.data!.docs.where((d) {
                          final data = d.data() as Map<String, dynamic>;
                          final s = (data['status'] ?? data['approvalStatus'] ?? '').toString().toLowerCase();
                          final isApp = data['isApproved'] == true;
                          return !isApp || s == 'pending' || s == 'pending_approval';
                        }).length;
                      }
                      return Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('PENDING'),
                            if (pendingCount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.accentOrange,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('$pendingCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  const Tab(text: 'APPROVED & LIVE'),
                  const Tab(text: 'ALL PRODUCTS'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('products').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.accentRed)));
          }

          final allDocs = snapshot.hasData ? snapshot.data!.docs : <QueryDocumentSnapshot>[];

          return TabBarView(
            controller: _tabController,
            children: [
              _buildProductList(allDocs, filter: 'pending'),
              _buildProductList(allDocs, filter: 'approved'),
              _buildProductList(allDocs, filter: 'all'),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        onPressed: () => _openMarkupApprovalDialog(context, null, null),
        icon: const Icon(Icons.add),
        label: const Text('ADD PRODUCT'),
      ),
    );
  }

  Widget _buildProductList(List<QueryDocumentSnapshot> docs, {required String filter}) {
    final filtered = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final s = (data['status'] ?? data['approvalStatus'] ?? '').toString().toLowerCase();
      final bool isApp = data['isApproved'] == true;

      if (filter == 'pending') {
        if (isApp && s == 'approved') return false;
      } else if (filter == 'approved') {
        if (!isApp || s != 'approved') return false;
      }

      if (_searchQuery.isNotEmpty) {
        final name = (data['name'] ?? data['title'] ?? '').toString().toLowerCase();
        final store = (data['storeName'] ?? data['shopName'] ?? '').toString().toLowerCase();
        final cat = (data['category'] ?? '').toString().toLowerCase();
        final sub = (data['subCategory'] ?? '').toString().toLowerCase();
        return name.contains(_searchQuery) || store.contains(_searchQuery) || cat.contains(_searchQuery) || sub.contains(_searchQuery);
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              filter == 'pending' ? Icons.check_circle_outline_rounded : Icons.inventory_2_outlined,
              size: 48,
              color: AppColors.textMuted.withAlpha(120),
            ),
            const SizedBox(height: 12),
            Text(
              filter == 'pending' ? 'No pending products waiting for review!' : 'No products found.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final doc = filtered[index];
        final data = doc.data() as Map<String, dynamic>;
        final String docId = doc.id;

        final String name = (data['name'] ?? data['title'] ?? 'Unnamed Product').toString();
        final String store = (data['storeName'] ?? data['shopName'] ?? 'Flash2Mart Merchant').toString();
        final String category = (data['category'] ?? 'General').toString();
        final String subCategory = (data['subCategory'] ?? '').toString();
        final String unit = (data['unit'] ?? data['weight'] ?? '1 item').toString();
        final int stock = ParseUtils.toInt(data['stock'], 0);
        final List<String> imgs = _extractImages(data);
        final String imageUrl = imgs.isNotEmpty ? imgs.first : '';

        final double merchantPrice = ParseUtils.toDouble(data['merchantPrice'] ?? data['price']);
        final double adminMargin = ParseUtils.toDouble(data['adminMargin']);
        final double customerPrice = ParseUtils.toDouble(data['customerPrice'] ?? data['price'], merchantPrice + adminMargin);
        final double mrp = ParseUtils.toDouble(data['marketPrice'], customerPrice > 0 ? customerPrice * 1.2 : 0);

        final bool isApproved = data['isApproved'] == true && data['status'] == 'approved';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0.5,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isApproved ? AppColors.accentGreen.withAlpha(60) : AppColors.accentOrange.withAlpha(80),
              width: 1.2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Real Product Image Thumbnail (supports Base64 & HTTP URLs)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 64,
                        height: 64,
                        color: const Color(0xFFF1F5F9),
                        child: imageUrl.isNotEmpty
                            ? AdminImageHelper.buildImage(imageUrl, width: 64, height: 64, fit: BoxFit.cover)
                            : const Icon(Icons.fastfood_rounded, color: AppColors.primaryPurple, size: 28),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textDark),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isApproved ? AppColors.accentGreenLight : AppColors.accentOrangeLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isApproved ? 'LIVE ✅' : 'PENDING ⏳',
                                  style: TextStyle(
                                    color: isApproved ? AppColors.accentGreen : AppColors.accentOrange,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '🏪 $store • 🏷️ $category${subCategory.isNotEmpty ? " ➔ $subCategory" : ""} ($unit)',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                          const SizedBox(height: 2),
                          Text('📦 Stock: $stock available', style: TextStyle(color: stock < 5 ? AppColors.accentRed : AppColors.accentGreen, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),

                // Pricing Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Merchant Cost', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                          Text('₹${merchantPrice.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark)),
                        ],
                      ),
                      const Text('+', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Admin Margin', style: TextStyle(fontSize: 10, color: AppColors.accentOrange)),
                          Text('+₹${adminMargin.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.accentOrange)),
                        ],
                      ),
                      const Text('=', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Customer Price', style: TextStyle(fontSize: 10, color: AppColors.accentGreen)),
                          Text('₹${customerPrice.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.accentGreen)),
                        ],
                      ),
                      if (mrp > customerPrice)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('MRP', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                            Text('₹${mrp.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, decoration: TextDecoration.lineThrough, color: Colors.grey)),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Actions: Verify/Edit, Approve, Delete
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryPurple,
                          side: const BorderSide(color: AppColors.primaryPurple),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: () => _openMarkupApprovalDialog(context, docId, data),
                        icon: const Icon(Icons.visibility_rounded, size: 16),
                        label: Text(
                          isApproved ? 'EDIT & UPDATE' : 'VERIFY & APPROVE',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ),
                    if (!isApproved) ...[
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        onPressed: () async {
                          final double effectiveMargin = adminMargin > 0 ? adminMargin : 5.0;
                          final double finalCustPrice = merchantPrice + effectiveMargin;
                          await FirebaseFirestore.instance.collection('products').doc(docId).update({
                            'isApproved': true,
                            'isApprovedByAdmin': true,
                            'status': 'approved',
                            'approvalStatus': 'approved',
                            'adminApprovalStatus': 'approved',
                            'merchantPrice': merchantPrice,
                            'adminMargin': effectiveMargin,
                            'price': finalCustPrice,
                            'customerPrice': finalCustPrice,
                            'approvedAt': FieldValue.serverTimestamp(),
                          });
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('✅ $name approved & published to Customer App at ₹${finalCustPrice.toStringAsFixed(0)}!')),
                            );
                          }
                        },
                        icon: const Icon(Icons.check, size: 15),
                        label: const Text('APPROVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ],
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Delete Product',
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.accentRed, size: 22),
                      onPressed: () => _confirmDeleteProduct(context, docId, name),
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

  /// Unified Add Product (docId == null) & Verify/Edit/Preview Modal (docId != null)
  void _openMarkupApprovalDialog(BuildContext context, String? docId, Map<String, dynamic>? data) {
    final bool isNew = docId == null;
    final double initMerchantPrice = isNew ? 40.0 : ParseUtils.toDouble(data?['merchantPrice'] ?? data?['price']);
    final double initMargin = isNew ? 10.0 : ParseUtils.toDouble(data?['adminMargin'], 5.0);
    final double initMrp = isNew ? 60.0 : ParseUtils.toDouble(data?['marketPrice'], initMerchantPrice + initMargin + 10.0);
    final int initStock = isNew ? 25 : ParseUtils.toInt(data?['stock'], 10);

    final nameController = TextEditingController(text: (data?['name'] ?? data?['title'] ?? '').toString());
    final unitController = TextEditingController(text: (data?['unit'] ?? data?['weight'] ?? '1 kg').toString());
    final descController = TextEditingController(text: (data?['description'] ?? '').toString());
    final catController = TextEditingController(text: (data?['category'] ?? 'Vegetables & Fruits').toString());
    final subCatController = TextEditingController(text: (data?['subCategory'] ?? '').toString());
    final childCatController = TextEditingController(text: (data?['childCategory'] ?? '').toString());
    final merchantPriceController = TextEditingController(text: initMerchantPrice.toStringAsFixed(0));
    final marginController = TextEditingController(text: initMargin.toStringAsFixed(0));
    final mrpController = TextEditingController(text: initMrp.toStringAsFixed(0));
    final stockController = TextEditingController(text: initStock.toString());

    final List<String> productImages = data != null ? _extractImages(data) : [];
    bool isPicking = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final double currentMerchant = double.tryParse(merchantPriceController.text.trim()) ?? 0.0;
            final double currentMargin = double.tryParse(marginController.text.trim()) ?? 0.0;
            final double currentCustomerPrice = currentMerchant + currentMargin;
            final double currentMrp = double.tryParse(mrpController.text.trim()) ?? currentCustomerPrice;
            final int discPct = currentMrp > currentCustomerPrice && currentMrp > 0
                ? (((currentMrp - currentCustomerPrice) / currentMrp) * 100).round()
                : 0;

            return Container(
              height: MediaQuery.of(context).size.height * 0.92,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                top: 18,
                left: 18,
                right: 18,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isNew ? '✨ Add Product to Category' : '🔍 Verify Product & Customer Preview',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5, color: AppColors.textDark),
                            ),
                            if (!isNew)
                              Text(
                                'Merchant: ${data?['storeName'] ?? data?['shopName'] ?? 'Partner'}',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                              ),
                          ],
                        ),
                      ),
                      if (!isNew)
                        IconButton(
                          tooltip: 'Delete Product',
                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.accentRed),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _confirmDeleteProduct(this.context, docId, nameController.text.trim());
                          },
                        ),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const Divider(height: 12),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. LIVE CUSTOMER APP PREVIEW CARD
                          const Text('👁️ Customer App Card Preview:', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.primaryPurple)),
                          const SizedBox(height: 6),
                          Center(
                            child: Container(
                              width: 148,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.borderSubtle, width: 1.2),
                                boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    height: 100,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: productImages.isNotEmpty
                                              ? AdminImageHelper.buildImage(productImages.first, width: double.infinity, fit: BoxFit.cover)
                                              : const Center(child: Icon(Icons.image_outlined, size: 32, color: Colors.grey)),
                                        ),
                                        Container(
                                          height: 22,
                                          width: double.infinity,
                                          color: const Color(0xFFF1F5F9),
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            unitController.text.trim().isEmpty ? '1 kg' : unitController.text.trim(),
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Row(
                                    children: [
                                      Text('₹${currentCustomerPrice.toInt()}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF09090B))),
                                      if (currentMrp > currentCustomerPrice) ...[
                                        const SizedBox(width: 4),
                                        Text('₹${currentMrp.toInt()}', style: const TextStyle(fontSize: 10.5, decoration: TextDecoration.lineThrough, color: Color(0xFF64748B))),
                                        const SizedBox(width: 4),
                                        Text('$discPct% off', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.accentGreen)),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    nameController.text.trim().isEmpty ? 'Product Name' : nameController.text.trim(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: Color(0xFF09090B)),
                                  ),
                                  const Text('⚡ 15 mins', style: TextStyle(fontSize: 10, color: Color(0xFF16A34A), fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // 2. IMAGES VERIFY & GALLERY UPLOAD
                          const Text('Product Images (Verify Merchant Photos or Add from Gallery):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 68,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                ...productImages.asMap().entries.map((entry) {
                                  return Stack(
                                    children: [
                                      Container(
                                        width: 64,
                                        height: 64,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: AppColors.primaryPurple.withAlpha(80)),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: AdminImageHelper.buildImage(entry.value, width: 64, height: 64, fit: BoxFit.cover),
                                      ),
                                      Positioned(
                                        top: 2,
                                        right: 10,
                                        child: GestureDetector(
                                          onTap: () => setModalState(() => productImages.removeAt(entry.key)),
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                                            child: const Icon(Icons.close, color: Colors.white, size: 12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                                if (productImages.length < 4)
                                  InkWell(
                                    onTap: isPicking
                                        ? null
                                        : () async {
                                            setModalState(() => isPicking = true);
                                            final b64 = await AdminImageHelper.pickAndCompressBase64(
                                              source: ImageSource.gallery,
                                              targetWidth: 320,
                                            );
                                            setModalState(() {
                                              isPicking = false;
                                              if (b64 != null) productImages.add(b64);
                                            });
                                          },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryLight,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: AppColors.primaryPurple.withAlpha(90)),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.add_photo_alternate_rounded, color: AppColors.primaryPurple, size: 20),
                                          Text(isPicking ? '...' : 'Gallery', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppColors.primaryPurple)),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 3. PRODUCT TITLE & UNIT
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: nameController,
                                  onChanged: (_) => setModalState(() {}),
                                  decoration: InputDecoration(
                                    labelText: 'Product Title *',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: unitController,
                                  onChanged: (_) => setModalState(() {}),
                                  decoration: InputDecoration(
                                    labelText: 'Unit/Wt',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 4. DYNAMIC CATEGORY & SUB-CATEGORY SELECTOR FROM FIRESTORE
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance.collection('categories').snapshots(),
                            builder: (context, catSnap) {
                              final List<String> catNames = [];
                              final Map<String, List<String>> subMap = {};
                              final Map<String, List<String>> childMap = {};
                              if (catSnap.hasData) {
                                for (final d in catSnap.data!.docs) {
                                  final cd = d.data() as Map<String, dynamic>;
                                  final cName = (cd['name'] ?? cd['title'] ?? '').toString().trim();
                                  if (cName.isNotEmpty) {
                                    catNames.add(cName);
                                    if (cd['subCategories'] is List) {
                                      final List<String> subNames = [];
                                      for (final m in (cd['subCategories'] as List).whereType<Map>()) {
                                        final sn = (m['name'] ?? '').toString().trim();
                                        if (sn.isNotEmpty) {
                                          subNames.add(sn);
                                          if (m['childCategories'] is List) {
                                            childMap["$cName::$sn"] = (m['childCategories'] as List)
                                                .whereType<Map>()
                                                .map((cm) => (cm['name'] ?? '').toString().trim())
                                                .where((s) => s.isNotEmpty)
                                                .toList();
                                          }
                                        }
                                      }
                                      subMap[cName] = subNames;
                                    }
                                  }
                                }
                              }
                              final currentCat = catController.text.trim();
                              final currentSub = subCatController.text.trim();
                              final subsForCat = subMap[currentCat] ?? const <String>[];
                              final childrenForSub = childMap["$currentCat::$currentSub"] ?? const <String>[];

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Category & Sub-Category:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  const SizedBox(height: 6),
                                  if (catNames.isNotEmpty)
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: catNames.map((cn) {
                                        final isSel = currentCat == cn;
                                        return ChoiceChip(
                                          label: Text(cn, style: TextStyle(fontSize: 11, color: isSel ? Colors.white : AppColors.textDark, fontWeight: FontWeight.w600)),
                                          selected: isSel,
                                          selectedColor: AppColors.primaryPurple,
                                          onSelected: (v) {
                                            if (v) {
                                              setModalState(() {
                                                catController.text = cn;
                                                subCatController.clear();
                                                childCatController.clear();
                                              });
                                            }
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  const SizedBox(height: 8),
                                  if (subsForCat.isNotEmpty) ...[
                                    const Text('Sub-Category:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.primaryPurple)),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: subsForCat.map((sc) {
                                        final isSel = subCatController.text.trim() == sc;
                                        return ChoiceChip(
                                          label: Text(sc, style: TextStyle(fontSize: 11, color: isSel ? Colors.white : AppColors.textDark)),
                                          selected: isSel,
                                          selectedColor: AppColors.accentGreen,
                                          onSelected: (v) => setModalState(() {
                                            subCatController.text = v ? sc : '';
                                            childCatController.clear();
                                          }),
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  if (childrenForSub.isNotEmpty) ...[
                                    const Text('Child Sub-Item (e.g. Mango, Apple):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.accentGreen)),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: childrenForSub.map((cc) {
                                        final isSel = childCatController.text.trim() == cc;
                                        return ChoiceChip(
                                          label: Text(cc, style: TextStyle(fontSize: 11, color: isSel ? Colors.white : AppColors.textDark)),
                                          selected: isSel,
                                          selectedColor: const Color(0xFF0284C7),
                                          onSelected: (v) => setModalState(() => childCatController.text = v ? cc : ''),
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: catController,
                                          decoration: InputDecoration(
                                            labelText: 'Category',
                                            isDense: true,
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: TextField(
                                          controller: subCatController,
                                          decoration: InputDecoration(
                                            labelText: 'Sub-Category',
                                            isDense: true,
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: TextField(
                                          controller: childCatController,
                                          decoration: InputDecoration(
                                            labelText: 'Child Item',
                                            isDense: true,
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),

                          // 5. PRICING BREAKDOWN CARD
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.primaryPurple.withAlpha(40)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: merchantPriceController,
                                        keyboardType: TextInputType.number,
                                        onChanged: (_) => setModalState(() {}),
                                        decoration: InputDecoration(
                                          labelText: isNew ? 'Base Price (₹)' : 'Merchant Cost (₹)',
                                          isDense: true,
                                          filled: true,
                                          fillColor: Colors.white,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: marginController,
                                        keyboardType: TextInputType.number,
                                        onChanged: (_) => setModalState(() {}),
                                        decoration: InputDecoration(
                                          labelText: 'Admin Margin (₹)',
                                          isDense: true,
                                          filled: true,
                                          fillColor: Colors.white,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [2, 5, 10, 15, 20].map((amt) {
                                    final bool isSelected = currentMargin == amt.toDouble();
                                    return InkWell(
                                      onTap: () => setModalState(() => marginController.text = amt.toString()),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: isSelected ? AppColors.primaryPurple : Colors.white,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: isSelected ? AppColors.primaryPurple : AppColors.borderSubtle),
                                        ),
                                        child: Text('+₹$amt', style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : AppColors.textDark, fontSize: 11.5)),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const Divider(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Customer Selling Price:', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: AppColors.accentGreen)),
                                    Text('₹${currentCustomerPrice.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.accentGreen)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: mrpController,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setModalState(() {}),
                                  decoration: InputDecoration(
                                    labelText: 'MRP (₹)',
                                    isDense: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: stockController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Stock Qty',
                                    isDense: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: descController,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: 'Description (Optional)',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (!isNew) ...[
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accentRed,
                            side: const BorderSide(color: AppColors.accentRed),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(this.context);
                            Navigator.pop(ctx);
                            await FirebaseFirestore.instance.collection('products').doc(docId).update({
                              'isApproved': false,
                              'isApprovedByAdmin': false,
                              'status': 'rejected',
                              'approvalStatus': 'rejected',
                              'rejectedAt': FieldValue.serverTimestamp(),
                            });
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Product marked as Rejected.')),
                            );
                          },
                          child: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () async {
                            final updatedName = nameController.text.trim();
                            if (updatedName.isEmpty) return;

                            final double finalMargin = double.tryParse(marginController.text.trim()) ?? 0.0;
                            final double finalMerchant = double.tryParse(merchantPriceController.text.trim()) ?? 0.0;
                            final double finalCustomer = finalMerchant + finalMargin;
                            final double finalMrp = double.tryParse(mrpController.text.trim()) ?? finalCustomer;
                            final int finalStock = int.tryParse(stockController.text.trim()) ?? 0;
                            final String primaryImg = productImages.isNotEmpty ? productImages.first : '';

                            final messenger = ScaffoldMessenger.of(this.context);
                            Navigator.pop(ctx);

                            final Map<String, dynamic> payload = {
                              'name': updatedName,
                              'title': updatedName,
                              'unit': unitController.text.trim().isEmpty ? '1 kg' : unitController.text.trim(),
                              'weight': unitController.text.trim().isEmpty ? '1 kg' : unitController.text.trim(),
                              'category': catController.text.trim().isEmpty ? 'General' : catController.text.trim(),
                              'subCategory': subCatController.text.trim(),
                              'childCategory': childCatController.text.trim(),
                              'description': descController.text.trim(),
                              'isApproved': true,
                              'isApprovedByAdmin': true,
                              'status': 'approved',
                              'approvalStatus': 'approved',
                              'adminApprovalStatus': 'approved',
                              'merchantPrice': finalMerchant,
                              'adminMargin': finalMargin,
                              'price': finalCustomer,
                              'customerPrice': finalCustomer,
                              'marketPrice': finalMrp,
                              'stock': finalStock,
                              if (primaryImg.isNotEmpty) 'imageUrl': primaryImg,
                              if (primaryImg.isNotEmpty) 'imageBase64': primaryImg,
                              if (productImages.isNotEmpty) 'images': productImages,
                              'approvedAt': FieldValue.serverTimestamp(),
                              'updatedAt': FieldValue.serverTimestamp(),
                            };

                            if (isNew) {
                              final newRef = FirebaseFirestore.instance.collection('products').doc();
                              payload['productId'] = newRef.id;
                              payload['id'] = newRef.id;
                              payload['createdByAdmin'] = true;
                              payload['storeName'] = 'Flash2Mart Official';
                              payload['shopName'] = 'Flash2Mart Official';
                              payload['createdAt'] = FieldValue.serverTimestamp();
                              await newRef.set(payload);
                            } else {
                              await FirebaseFirestore.instance.collection('products').doc(docId).set(payload, SetOptions(merge: true));
                            }

                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('✅ "$updatedName" published to Customer App at ₹${finalCustomer.toStringAsFixed(0)}!'),
                                backgroundColor: AppColors.accentGreen,
                              ),
                            );
                          },
                          child: Text(
                            isNew ? 'PUBLISH PRODUCT TO CUSTOMER APP' : 'SAVE & APPROVE FOR CUSTOMER APP',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
