import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/app_colors.dart';
import '../utils/parse_utils.dart';
import '../utils/image_helper.dart';

class _ComboSubItemDraft {
  final TextEditingController nameController;
  final TextEditingController qtyController;
  final TextEditingController actualPriceController;
  final TextEditingController offerPriceController;
  String imageStr;

  _ComboSubItemDraft({
    String name = '',
    String qty = '1 pack',
    String actualPrice = '',
    String offerPrice = '0',
    this.imageStr = '',
  })  : nameController = TextEditingController(text: name),
        qtyController = TextEditingController(text: qty),
        actualPriceController = TextEditingController(text: actualPrice),
        offerPriceController = TextEditingController(text: offerPrice);

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    actualPriceController.dispose();
    offerPriceController.dispose();
  }
}

class AdminCombosScreen extends StatefulWidget {
  final bool showAppBar;
  const AdminCombosScreen({super.key, this.showAppBar = true});

  @override
  State<AdminCombosScreen> createState() => _AdminCombosScreenState();
}

class _AdminCombosScreenState extends State<AdminCombosScreen> with SingleTickerProviderStateMixin {
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

  List<String> _extractImages(Map<String, dynamic> data) {
    final List<String> imgs = [];
    if (data['comboProductsList'] is List) {
      for (final item in (data['comboProductsList'] as List)) {
        if (item is Map) {
          final s = (item['imageUrl'] ?? item['imageBase64'] ?? '').toString().trim();
          if (s.isNotEmpty && !imgs.contains(s)) imgs.add(s);
        }
      }
    }
    if (data['images'] is List) {
      for (final item in (data['images'] as List)) {
        final s = item.toString().trim();
        if (s.isNotEmpty && !imgs.contains(s)) imgs.add(s);
      }
    }
    final primary = (data['imageBase64'] ?? data['imageUrl'] ?? data['image'] ?? '').toString().trim();
    if (primary.isNotEmpty && !imgs.contains(primary)) {
      imgs.insert(0, primary);
    }
    return imgs;
  }

  void _openComboDialog({String? docId, Map<String, dynamic>? data}) {
    final titleController = TextEditingController(text: (data?['name'] ?? data?['title'] ?? '').toString());
    final itemsSummaryController = TextEditingController(text: (data?['comboItems'] ?? '').toString());

    final double initMerchantCost = ParseUtils.toDouble(data?['merchantPrice'] ?? data?['price'], 250);
    final double initMargin = ParseUtils.toDouble(data?['adminMargin'], docId == null ? 50 : 10);
    final double initMrp = ParseUtils.toDouble(data?['marketPrice'], initMerchantCost + initMargin + 70);
    final int initStock = ParseUtils.toInt(data?['stock'], 20);

    final merchantPriceController = TextEditingController(text: initMerchantCost.toStringAsFixed(0));
    final marginController = TextEditingController(text: initMargin.toStringAsFixed(0));
    final mrpController = TextEditingController(text: initMrp.toStringAsFixed(0));
    final stockController = TextEditingController(text: initStock.toString());

    // Build initial sub-items list from existing data or create 2 starter rows
    final List<_ComboSubItemDraft> subItems = [];
    if (data?['comboProductsList'] is List && (data!['comboProductsList'] as List).isNotEmpty) {
      for (final raw in (data['comboProductsList'] as List)) {
        if (raw is Map) {
          subItems.add(_ComboSubItemDraft(
            name: (raw['name'] ?? '').toString(),
            qty: (raw['quantity'] ?? raw['qty'] ?? '1 pack').toString(),
            actualPrice: ParseUtils.toDouble(raw['actualPrice'], 0).toStringAsFixed(0),
            offerPrice: ParseUtils.toDouble(raw['offerPrice'], 0).toStringAsFixed(0),
            imageStr: (raw['imageUrl'] ?? raw['imageBase64'] ?? '').toString(),
          ));
        }
      }
    } else {
      subItems.add(_ComboSubItemDraft(name: 'Apple', qty: '1/2 kg', actualPrice: '70', offerPrice: '0'));
      subItems.add(_ComboSubItemDraft(name: 'Fresh Vegetables Mix', qty: '2 kg', actualPrice: '300', offerPrice: '300'));
    }

    final List<String> extraComboImages = data != null ? _extractImages(data) : [];
    bool isLive = docId == null ? true : (data?['isApproved'] == true);
    bool isPicking = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final double mPrice = double.tryParse(merchantPriceController.text.trim()) ?? 0.0;
            final double margin = double.tryParse(marginController.text.trim()) ?? 0.0;
            final double finalPrice = mPrice + margin;

            // Compute sum of actual prices from sub-items if entered
            double subItemsActualSum = 0.0;
            for (final it in subItems) {
              subItemsActualSum += double.tryParse(it.actualPriceController.text.trim()) ?? 0.0;
            }
            final double mrp = subItemsActualSum > finalPrice
                ? subItemsActualSum
                : (double.tryParse(mrpController.text.trim()) ?? finalPrice);
            final int discount = mrp > finalPrice && mrp > 0 ? (((mrp - finalPrice) / mrp) * 100).round() : 0;

            return Container(
              height: MediaQuery.of(context).size.height * 0.90,
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
                              docId == null ? '✨ Admin: Multi-Item Combo Builder' : '🔍 Verify & Edit Multi-Item Combo',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF4C1D95)),
                            ),
                            if (data != null && (data['storeName'] ?? '').toString().isNotEmpty)
                              Text('Submitted by: ${data['storeName']}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const Divider(height: 14),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Combo Offer Title *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: titleController,
                            decoration: InputDecoration(
                              hintText: 'e.g. Super Saver Fruit & Veggie Combo',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Multi-Item Combo Breakdown Builder
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Combo Products (Each Item Cost, Qty & Image)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: Color(0xFF4C1D95))),
                              TextButton.icon(
                                onPressed: () => setModalState(() {
                                  subItems.add(_ComboSubItemDraft(name: '', qty: '500g', actualPrice: '50', offerPrice: '50'));
                                }),
                                icon: const Icon(Icons.add_circle, size: 16, color: Color(0xFF7C3AED)),
                                label: const Text('Add Item', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF7C3AED))),
                              ),
                            ],
                          ),

                          ...subItems.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final item = entry.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAF5FF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF7C3AED).withAlpha(60)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      // Item Image Picker
                                      GestureDetector(
                                        onTap: isPicking
                                            ? null
                                            : () async {
                                                setModalState(() => isPicking = true);
                                                final b64 = await AdminImageHelper.pickAndCompressBase64(
                                                  source: ImageSource.gallery,
                                                  targetWidth: 260,
                                                );
                                                setModalState(() {
                                                  isPicking = false;
                                                  if (b64 != null) item.imageStr = b64;
                                                });
                                              },
                                        child: Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: const Color(0xFF7C3AED).withAlpha(80)),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: item.imageStr.isNotEmpty
                                              ? AdminImageHelper.buildImage(item.imageStr, width: 56, height: 56, fit: BoxFit.cover)
                                              : const Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.add_a_photo_rounded, size: 18, color: Color(0xFF7C3AED)),
                                                    Text('Photo', style: TextStyle(fontSize: 9, color: Color(0xFF7C3AED), fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            TextField(
                                              controller: item.nameController,
                                              decoration: InputDecoration(
                                                labelText: 'Item #${idx + 1} Name (e.g. Apple)',
                                                isDense: true,
                                                filled: true,
                                                fillColor: Colors.white,
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller: item.qtyController,
                                                    decoration: InputDecoration(
                                                      labelText: 'Qty (e.g. 1/2 kg)',
                                                      isDense: true,
                                                      filled: true,
                                                      fillColor: Colors.white,
                                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: TextField(
                                                    controller: item.actualPriceController,
                                                    keyboardType: TextInputType.number,
                                                    onChanged: (_) => setModalState(() {}),
                                                    decoration: InputDecoration(
                                                      labelText: 'Actual ₹ (70)',
                                                      isDense: true,
                                                      filled: true,
                                                      fillColor: Colors.white,
                                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: TextField(
                                                    controller: item.offerPriceController,
                                                    keyboardType: TextInputType.number,
                                                    onChanged: (_) => setModalState(() {}),
                                                    decoration: InputDecoration(
                                                      labelText: 'Combo ₹ (0=Free)',
                                                      isDense: true,
                                                      filled: true,
                                                      fillColor: Colors.white,
                                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (subItems.length > 1)
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: AppColors.accentRed, size: 20),
                                          onPressed: () => setModalState(() => subItems.removeAt(idx)),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),

                          const SizedBox(height: 8),
                          const Text('Extra Banner / Uploaded Images', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 68,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                ...extraComboImages.asMap().entries.map((entry) {
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
                                          onTap: () => setModalState(() => extraComboImages.removeAt(entry.key)),
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
                                InkWell(
                                  onTap: isPicking
                                      ? null
                                      : () async {
                                          setModalState(() => isPicking = true);
                                          final b64 = await AdminImageHelper.pickAndCompressBase64(
                                            source: ImageSource.gallery,
                                            targetWidth: 300,
                                          );
                                          setModalState(() {
                                            isPicking = false;
                                            if (b64 != null) extraComboImages.add(b64);
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
                                    child: const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_photo_alternate_rounded, color: AppColors.primaryPurple, size: 20),
                                        Text('Gallery', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppColors.primaryPurple)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Total Pricing Row
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Merchant Cost (₹)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: merchantPriceController,
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) => setModalState(() {}),
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
                                    const Text('Admin Margin (₹)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.primaryPurple)),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: marginController,
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) => setModalState(() {}),
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 68,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Stock', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: stockController,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: AppColors.accentGreenLight, borderRadius: BorderRadius.circular(10)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Customer Total: ₹${finalPrice.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.accentGreen)),
                                    Text('Actual Items Total: ₹${mrp.toStringAsFixed(0)} (Save ₹${(mrp - finalPrice).clamp(0, 99999).toStringAsFixed(0)})', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: const Color(0xFF7C3AED), borderRadius: BorderRadius.circular(8)),
                                  child: Text('$discount% OFF COMBO', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Approved & Live in Customer App', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            value: isLive,
                            activeTrackColor: AppColors.accentGreen,
                            onChanged: (val) => setModalState(() => isLive = val),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (docId != null) ...[
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accentRed,
                            side: const BorderSide(color: AppColors.accentRed),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await FirebaseFirestore.instance.collection('products').doc(docId).update({
                              'isApproved': false,
                              'isApprovedByAdmin': false,
                              'status': 'rejected',
                              'approvalStatus': 'rejected',
                              'rejectedAt': FieldValue.serverTimestamp(),
                            });
                          },
                          child: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7C3AED),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () async {
                            final title = titleController.text.trim();
                            if (title.isEmpty) return;

                            final List<Map<String, dynamic>> structuredItems = [];
                            final List<String> allComboImages = [];
                            final List<String> summaryParts = [];

                            for (final it in subItems) {
                              final iName = it.nameController.text.trim();
                              if (iName.isEmpty) continue;
                              final iQty = it.qtyController.text.trim();
                              final iActual = double.tryParse(it.actualPriceController.text.trim()) ?? 0.0;
                              final iOffer = double.tryParse(it.offerPriceController.text.trim()) ?? 0.0;

                              structuredItems.add({
                                'name': iName,
                                'quantity': iQty,
                                'actualPrice': iActual,
                                'offerPrice': iOffer,
                                'imageUrl': it.imageStr,
                              });
                              if (it.imageStr.isNotEmpty && !allComboImages.contains(it.imageStr)) {
                                allComboImages.add(it.imageStr);
                              }
                              summaryParts.add('$iQty $iName');
                            }

                            for (final ex in extraComboImages) {
                              if (ex.isNotEmpty && !allComboImages.contains(ex)) {
                                allComboImages.add(ex);
                              }
                            }

                            final String primaryImg = allComboImages.isNotEmpty ? allComboImages.first : '';
                            final int stock = int.tryParse(stockController.text.trim()) ?? 20;
                            final String comboItemsText = summaryParts.isNotEmpty
                                ? summaryParts.join(', ')
                                : itemsSummaryController.text.trim();

                            Navigator.pop(ctx);

                            final comboData = {
                              'name': title,
                              'title': title,
                              'category': 'Combo Offers & Deals',
                              'isCombo': true,
                              'isComboOffer': true,
                              'comboItems': comboItemsText,
                              'comboProductsList': structuredItems,
                              'merchantPrice': mPrice,
                              'adminMargin': margin,
                              'price': finalPrice,
                              'customerPrice': finalPrice,
                              'marketPrice': mrp,
                              'stock': stock,
                              'unit': '${structuredItems.length} Items Combo',
                              'weight': '${structuredItems.length} Items Combo',
                              'discountPercent': discount,
                              'discountTag': '$discount% OFF COMBO DEAL',
                              if (primaryImg.isNotEmpty) 'imageUrl': primaryImg,
                              if (primaryImg.isNotEmpty) 'imageBase64': primaryImg,
                              if (allComboImages.isNotEmpty) 'images': allComboImages,
                              'isApproved': isLive,
                              'isApprovedByAdmin': isLive,
                              'status': isLive ? 'approved' : 'pending_approval',
                              'approvalStatus': isLive ? 'approved' : 'pending_approval',
                              'updatedAt': FieldValue.serverTimestamp(),
                            };

                            if (docId != null) {
                              await FirebaseFirestore.instance.collection('products').doc(docId).set(comboData, SetOptions(merge: true));
                            } else {
                              final newRef = FirebaseFirestore.instance.collection('products').doc();
                              comboData['productId'] = newRef.id;
                              comboData['id'] = newRef.id;
                              comboData['createdByAdmin'] = true;
                              comboData['storeName'] = 'Flash2Mart Official Combo';
                              comboData['createdAt'] = FieldValue.serverTimestamp();
                              await newRef.set(comboData);
                            }

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✅ Combo "$title" (${structuredItems.length} items) ${isLive ? "published" : "saved"} at ₹${finalPrice.toStringAsFixed(0)}!'),
                                  backgroundColor: AppColors.accentGreen,
                                ),
                              );
                            }
                          },
                          child: Text(
                            docId == null ? 'PUBLISH MULTI-ITEM COMBO' : (isLive ? 'VERIFY, SAVE & APPROVE' : 'SAVE CHANGES'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Combo Offers & Deals', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textDark,
              elevation: 0.5,
              actions: [
                IconButton(
                  tooltip: 'Create Combo',
                  icon: const Icon(Icons.add_circle_rounded, color: Color(0xFF7C3AED), size: 28),
                  onPressed: () => _openComboDialog(),
                ),
              ],
            )
          : null,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('products').where('isCombo', isEqualTo: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF7C3AED)));
          }

          final allCombos = snapshot.hasData ? snapshot.data!.docs : <QueryDocumentSnapshot>[];
          final pendingCombos = allCombos.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return data['isApproved'] != true || (data['status'] ?? '') != 'approved';
          }).toList();
          final liveCombos = allCombos.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return data['isApproved'] == true && (data['status'] ?? 'approved') == 'approved';
          }).toList();

          return Column(
            children: [
              Container(
                color: Colors.white,
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: const Color(0xFF7C3AED),
                  labelColor: const Color(0xFF7C3AED),
                  unselectedLabelColor: AppColors.textMuted,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('PENDING VERIFY'),
                          if (pendingCombos.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.accentOrange, borderRadius: BorderRadius.circular(10)),
                              child: Text('${pendingCombos.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Tab(text: 'APPROVED & LIVE (${liveCombos.length})'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildComboList(pendingCombos, isPendingTab: true),
                    _buildComboList(liveCombos, isPendingTab: false),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        onPressed: () => _openComboDialog(),
        icon: const Icon(Icons.add),
        label: const Text('NEW ADMIN COMBO'),
      ),
    );
  }

  Widget _buildComboList(List<QueryDocumentSnapshot> docs, {required bool isPendingTab}) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_offer_outlined, size: 48, color: AppColors.textMuted.withAlpha(120)),
            const SizedBox(height: 12),
            Text(
              isPendingTab ? 'No merchant combos waiting for verification.' : 'No live combo offers yet.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), foregroundColor: Colors.white),
              onPressed: () => _openComboDialog(),
              icon: const Icon(Icons.add),
              label: const Text('CREATE ADMIN COMBO'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final data = doc.data() as Map<String, dynamic>;
        final String name = (data['name'] ?? data['title'] ?? 'Combo Deal').toString();
        final String store = (data['storeName'] ?? 'Flash2Mart').toString();
        final String items = (data['comboItems'] ?? '').toString();
        final double mPrice = ParseUtils.toDouble(data['merchantPrice'] ?? data['price']);
        final double margin = ParseUtils.toDouble(data['adminMargin']);
        final double price = ParseUtils.toDouble(data['price'], mPrice + margin);
        final double mrp = ParseUtils.toDouble(data['marketPrice']);
        final String tag = (data['discountTag'] ?? 'COMBO DEAL').toString();
        final List<String> imgs = _extractImages(data);
        final int subCount = data['comboProductsList'] is List ? (data['comboProductsList'] as List).length : 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0.5,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: isPendingTab ? AppColors.accentOrange.withAlpha(90) : const Color(0xFF7C3AED).withAlpha(70)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imgs.isNotEmpty) ...[
                  SizedBox(
                    height: 68,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: imgs.length,
                      itemBuilder: (_, i) => Container(
                        width: 68,
                        height: 68,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: AdminImageHelper.buildImage(imgs[i], width: 68, height: 68, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textDark)),
                          Text('🏪 $store ${subCount > 0 ? "• $subCount Items" : ""}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFF3E8FF), borderRadius: BorderRadius.circular(8)),
                      child: Text(tag, style: const TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.bold, fontSize: 10)),
                    ),
                  ],
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Items: $items', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                ],
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Customer: ₹${price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.accentGreen)),
                            if (mrp > price) ...[
                              const SizedBox(width: 6),
                              Text('₹${mrp.toStringAsFixed(0)}', style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey, fontSize: 12)),
                            ],
                          ],
                        ),
                        Text('Merchant: ₹${mPrice.toStringAsFixed(0)} + Admin: ₹${margin.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                      ],
                    ),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF7C3AED),
                            side: const BorderSide(color: Color(0xFF7C3AED)),
                          ),
                          onPressed: () => _openComboDialog(docId: doc.id, data: data),
                          icon: const Icon(Icons.edit, size: 14),
                          label: Text(isPendingTab ? 'VERIFY & APPROVE' : 'EDIT', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.accentRed, size: 20),
                          onPressed: () => FirebaseFirestore.instance.collection('products').doc(doc.id).delete(),
                        ),
                      ],
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
}
