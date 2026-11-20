import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/app_colors.dart';
import '../utils/parse_utils.dart';
import '../utils/image_helper.dart';

class AdminCategoriesScreen extends StatefulWidget {
  final bool showAppBar;
  const AdminCategoriesScreen({super.key, this.showAppBar = true});

  @override
  State<AdminCategoriesScreen> createState() => _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState extends State<AdminCategoriesScreen> {
  Future<void> _seedDefaultCategories() async {
    final defaults = [
      {'name': 'Vegetables & Fruits', 'icon': '🥦', 'order': 1, 'isActive': true},
      {'name': 'Grocery / Supermarket', 'icon': '🛒', 'order': 2, 'isActive': true},
      {'name': 'Dairy, Bread & Eggs', 'icon': '🥛', 'order': 3, 'isActive': true},
      {'name': 'Non-Veg & Meat', 'icon': '🍗', 'order': 4, 'isActive': true},
      {'name': 'Snacks & Munchies', 'icon': '🍿', 'order': 5, 'isActive': true},
      {'name': 'Medicines & Pharmacy', 'icon': '💊', 'order': 6, 'isActive': true},
      {'name': 'Electronics & Home', 'icon': '🔌', 'order': 7, 'isActive': true},
    ];

    final existing = await FirebaseFirestore.instance.collection('categories').get();
    final existingNames = existing.docs
        .map((d) => (d.data()['name'] ?? d.data()['title'] ?? '').toString().toLowerCase())
        .toSet();

    final batch = FirebaseFirestore.instance.batch();
    int added = 0;
    for (final cat in defaults) {
      if (!existingNames.contains((cat['name'] as String).toLowerCase())) {
        final ref = FirebaseFirestore.instance.collection('categories').doc();
        batch.set(ref, {
          ...cat,
          'title': cat['name'],
          'imageUrl': '',
          'imageBase64': '',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        added++;
      }
    }
    if (added > 0) {
      await batch.commit();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(added > 0 ? '✅ Added $added default categories for editing!' : 'All default categories already exist.')),
      );
    }
  }



  void _openChildCategoriesManager(
    String docId,
    String catName,
    List<Map<String, dynamic>> subList,
    int subIdx,
    VoidCallback onParentRefresh,
  ) {
    final subMap = subList[subIdx];
    final String subName = (subMap['name'] ?? 'Sub-Category').toString();
    final List<Map<String, dynamic>> childList = (subMap['childCategories'] is List)
        ? (subMap['childCategories'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setChildSheetState) {
            void openAddOrEditChild({int? editIndex}) {
              final existing = editIndex != null ? childList[editIndex] : null;
              final nameCtrl = TextEditingController(text: (existing?['name'] ?? '').toString());
              String imgStr = (existing?['imageBase64'] ?? existing?['imageUrl'] ?? '').toString();
              bool picking = false;

              showDialog(
                context: context,
                builder: (dlgCtx) => StatefulBuilder(
                  builder: (dCtx, setDlgState) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: Text(
                      editIndex == null ? "Add Child Item to $subName" : "Edit Child Item",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.primaryPurple.withAlpha(80)),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: imgStr.isNotEmpty
                                ? AdminImageHelper.buildImage(imgStr, width: 72, height: 72, fit: BoxFit.cover)
                                : const Icon(Icons.spa_rounded, size: 30, color: AppColors.primaryPurple),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            onPressed: picking
                                ? null
                                : () async {
                                    setDlgState(() => picking = true);
                                    final b64 = await AdminImageHelper.pickAndCompressBase64(
                                      source: ImageSource.gallery,
                                      targetWidth: 200,
                                    );
                                    setDlgState(() {
                                      picking = false;
                                      if (b64 != null) imgStr = b64;
                                    });
                                  },
                            icon: const Icon(Icons.photo_library_rounded, size: 16),
                            label: Text(picking ? "Loading..." : "Pick Image", style: const TextStyle(fontSize: 11.5)),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              labelText: "Child Item Name *",
                              hintText: "e.g. Mango, Apple, Banana",
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text("CANCEL")),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple, foregroundColor: Colors.white),
                        onPressed: () async {
                          final cName = nameCtrl.text.trim();
                          if (cName.isEmpty) return;
                          final item = {
                            "name": cName,
                            "imageBase64": imgStr,
                            "imageUrl": imgStr,
                          };
                          setChildSheetState(() {
                            if (editIndex != null) {
                              childList[editIndex] = item;
                            } else {
                              childList.add(item);
                            }
                            subList[subIdx]["childCategories"] = childList;
                          });
                          onParentRefresh();
                          Navigator.pop(dlgCtx);
                          await FirebaseFirestore.instance.collection("categories").doc(docId).update({
                            "subCategories": subList,
                            "updatedAt": FieldValue.serverTimestamp(),
                          });
                        },
                        child: const Text("SAVE"),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.68,
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          "$catName ➔ $subName (Left Rail Items)",
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.textDark),
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        onPressed: () => openAddOrEditChild(),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text("ADD CHILD", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: childList.isEmpty
                        ? const Center(
                            child: Text(
                              "No child items yet (e.g. Mango, Apple, Banana).\nTap ADD CHILD to create left-sidebar items!",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            itemCount: childList.length,
                            itemBuilder: (_, idx) {
                              final ch = childList[idx];
                              final chName = (ch["name"] ?? "Item").toString();
                              final chImg = (ch["imageBase64"] ?? ch["imageUrl"] ?? "").toString();
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 42,
                                      height: 42,
                                      color: AppColors.primaryLight,
                                      child: chImg.isNotEmpty
                                          ? AdminImageHelper.buildImage(chImg, width: 42, height: 42, fit: BoxFit.cover)
                                          : const Icon(Icons.spa_rounded, color: AppColors.primaryPurple),
                                    ),
                                  ),
                                  title: Text(chName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_rounded, color: AppColors.primaryPurple, size: 19),
                                        onPressed: () => openAddOrEditChild(editIndex: idx),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: AppColors.accentRed, size: 19),
                                        onPressed: () async {
                                          setChildSheetState(() {
                                            childList.removeAt(idx);
                                            subList[subIdx]["childCategories"] = childList;
                                          });
                                          onParentRefresh();
                                          await FirebaseFirestore.instance.collection("categories").doc(docId).update({
                                            "subCategories": subList,
                                            "updatedAt": FieldValue.serverTimestamp(),
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openSubCategoriesManager(String docId, String catName, List<dynamic> rawSubs) {
    final List<Map<String, dynamic>> subList = rawSubs
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void openAddOrEditSub({int? editIndex}) {
              final existing = editIndex != null ? subList[editIndex] : null;
              final nameCtrl = TextEditingController(text: (existing?['name'] ?? '').toString());
              String imgStr = (existing?['imageBase64'] ?? existing?['imageUrl'] ?? '').toString();
              bool picking = false;

              showDialog(
                context: context,
                builder: (dlgCtx) => StatefulBuilder(
                  builder: (dCtx, setDlgState) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: Text(editIndex == null ? "Add Sub-Category to $catName" : "Edit Sub-Category", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.primaryPurple.withAlpha(80)),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: imgStr.isNotEmpty
                                ? AdminImageHelper.buildImage(imgStr, width: 76, height: 76, fit: BoxFit.cover)
                                : const Icon(Icons.category_rounded, size: 32, color: AppColors.primaryPurple),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            onPressed: picking
                                ? null
                                : () async {
                                    setDlgState(() => picking = true);
                                    final b64 = await AdminImageHelper.pickAndCompressBase64(
                                      source: ImageSource.gallery,
                                      targetWidth: 220,
                                    );
                                    setDlgState(() {
                                      picking = false;
                                      if (b64 != null) imgStr = b64;
                                    });
                                  },
                            icon: const Icon(Icons.photo_library_rounded, size: 16),
                            label: Text(picking ? "Loading..." : "Pick Image from Gallery", style: const TextStyle(fontSize: 11.5)),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              labelText: "Sub-Category Name *",
                              hintText: "e.g. Fresh Fruits, Leafy Greens",
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text("CANCEL")),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple, foregroundColor: Colors.white),
                        onPressed: () async {
                          final subName = nameCtrl.text.trim();
                          if (subName.isEmpty) return;
                          final item = {
                            "name": subName,
                            "imageBase64": imgStr,
                            "imageUrl": imgStr,
                            if (existing != null && existing["childCategories"] != null) "childCategories": existing["childCategories"],
                          };
                          setSheetState(() {
                            if (editIndex != null) {
                              subList[editIndex] = item;
                            } else {
                              subList.add(item);
                            }
                          });
                          Navigator.pop(dlgCtx);
                          await FirebaseFirestore.instance.collection("categories").doc(docId).update({
                            "subCategories": subList,
                            "updatedAt": FieldValue.serverTimestamp(),
                          });
                        },
                        child: const Text("SAVE"),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          "Sub-Categories in $catName",
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.textDark),
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () => openAddOrEditSub(),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text("ADD SUB-ITEM", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const Divider(height: 18),
                  Expanded(
                    child: subList.isEmpty
                        ? const Center(
                            child: Text(
                              "No sub-categories yet. Tap ADD SUB-ITEM to create one!",
                              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            itemCount: subList.length,
                            itemBuilder: (_, idx) {
                              final s = subList[idx];
                              final sName = (s["name"] ?? "Sub-Item").toString();
                              final sImg = (s["imageBase64"] ?? s["imageUrl"] ?? "").toString();
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      color: AppColors.primaryLight,
                                      child: sImg.isNotEmpty
                                          ? AdminImageHelper.buildImage(sImg, width: 44, height: 44, fit: BoxFit.cover)
                                          : const Icon(Icons.subdirectory_arrow_right_rounded, color: AppColors.primaryPurple),
                                    ),
                                  ),
                                  title: Text(sName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                  subtitle: InkWell(
                                    onTap: () => _openChildCategoriesManager(
                                      docId,
                                      catName,
                                      subList,
                                      idx,
                                      () => setSheetState(() {}),
                                    ),
                                    child: Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentGreenLight,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        "+ Child Items (${(s["childCategories"] is List) ? (s["childCategories"] as List).length : 0})",
                                        style: const TextStyle(color: AppColors.accentGreen, fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_rounded, color: AppColors.primaryPurple, size: 19),
                                        onPressed: () => openAddOrEditSub(editIndex: idx),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: AppColors.accentRed, size: 19),
                                        onPressed: () async {
                                          setSheetState(() => subList.removeAt(idx));
                                          await FirebaseFirestore.instance.collection("categories").doc(docId).update({
                                            "subCategories": subList,
                                            "updatedAt": FieldValue.serverTimestamp(),
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openCategoryDialog({String? docId, Map<String, dynamic>? data}) {
    final titleController = TextEditingController(text: (data?['name'] ?? data?['title'] ?? '').toString());
    final iconController = TextEditingController(text: (data?['icon'] ?? '🛒').toString());
    final orderController = TextEditingController(text: ParseUtils.toInt(data?['order'], 1).toString());
    String selectedImageStr = (data?['imageBase64'] ?? data?['imageUrl'] ?? '').toString();
    bool isActive = ParseUtils.toBool(data?['isActive'], true);
    bool isPicking = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(docId == null ? 'Add New Category' : 'Edit & Update Category', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category Image Picker from Gallery
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.primaryPurple.withAlpha(80)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: selectedImageStr.isNotEmpty
                              ? AdminImageHelper.buildImage(selectedImageStr, width: 84, height: 84, fit: BoxFit.cover)
                              : Center(
                                  child: Text(
                                    iconController.text.trim().isNotEmpty ? iconController.text.trim() : '🛒',
                                    style: const TextStyle(fontSize: 32),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryPurple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: isPicking
                                  ? null
                                  : () async {
                                      setDlgState(() => isPicking = true);
                                      final b64 = await AdminImageHelper.pickAndCompressBase64(
                                        source: ImageSource.gallery,
                                        targetWidth: 250,
                                      );
                                      setDlgState(() {
                                        isPicking = false;
                                        if (b64 != null) {
                                          selectedImageStr = b64;
                                        }
                                      });
                                    },
                              icon: const Icon(Icons.photo_library_rounded, size: 16),
                              label: Text(isPicking ? 'Loading...' : 'Pick from Gallery', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            ),
                            if (selectedImageStr.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: 'Remove Image',
                                icon: const Icon(Icons.delete_outline, color: AppColors.accentRed, size: 20),
                                onPressed: () => setDlgState(() => selectedImageStr = ''),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  const Text('Category Name *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      hintText: 'e.g. Fresh Vegetables, Dairy, Non-Veg',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),

                  const Text('Fallback Emoji (if no Gallery Image)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: iconController,
                    onChanged: (_) => setDlgState(() {}),
                    decoration: InputDecoration(
                      hintText: 'e.g. 🥦, 🥛, 🍎, 🍗',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),

                  const Text('Display Priority Order', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: orderController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '1, 2, 3...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 8),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active in Customer App', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    value: isActive,
                    activeTrackColor: AppColors.primaryPurple,
                    onChanged: (val) => setDlgState(() => isActive = val),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple, foregroundColor: Colors.white),
                onPressed: () async {
                  final name = titleController.text.trim();
                  if (name.isEmpty) return;

                  Navigator.pop(ctx);

                  final docData = {
                    'name': name,
                    'title': name,
                    'icon': iconController.text.trim(),
                    'imageUrl': selectedImageStr,
                    'imageBase64': selectedImageStr,
                    'order': int.tryParse(orderController.text.trim()) ?? 1,
                    'isActive': isActive,
                    'updatedAt': FieldValue.serverTimestamp(),
                  };

                  if (docId != null) {
                    await FirebaseFirestore.instance.collection('categories').doc(docId).set(docData, SetOptions(merge: true));
                  } else {
                    docData['createdAt'] = FieldValue.serverTimestamp();
                    await FirebaseFirestore.instance.collection('categories').add(docData);
                  }

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('✅ Category "$name" saved & synced to Customer App!')),
                    );
                  }
                },
                child: const Text('SAVE CATEGORY'),
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
              title: const Text('Categories Manager', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textDark,
              elevation: 0.5,
              actions: [
                IconButton(
                  tooltip: 'Load Default Categories',
                  icon: const Icon(Icons.auto_fix_high_rounded, color: AppColors.accentOrange),
                  onPressed: _seedDefaultCategories,
                ),
                IconButton(
                  tooltip: 'Add Category',
                  icon: const Icon(Icons.add_circle_rounded, color: AppColors.primaryPurple, size: 28),
                  onPressed: () => _openCategoryDialog(),
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          if (!widget.showAppBar)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Manage Live Categories', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  TextButton.icon(
                    onPressed: _seedDefaultCategories,
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 16, color: AppColors.primaryPurple),
                    label: const Text('Sync Default Categories', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primaryPurple)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('categories').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
                }

                final docs = List<QueryDocumentSnapshot>.from(snapshot.hasData ? snapshot.data!.docs : []);
                docs.sort((a, b) {
                  final aOrd = ParseUtils.toInt((a.data() as Map<String, dynamic>)['order'], 99);
                  final bOrd = ParseUtils.toInt((b.data() as Map<String, dynamic>)['order'], 99);
                  return aOrd.compareTo(bOrd);
                });

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.category_outlined, size: 48, color: AppColors.textMuted),
                        const SizedBox(height: 12),
                        const Text('No categories in Firestore yet.', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple, foregroundColor: Colors.white),
                              onPressed: () => _openCategoryDialog(),
                              icon: const Icon(Icons.add),
                              label: const Text('ADD NEW CATEGORY'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _seedDefaultCategories,
                              icon: const Icon(Icons.auto_fix_high_rounded),
                              label: const Text('LOAD DEFAULTS'),
                            ),
                          ],
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
                    final name = (data['name'] ?? data['title'] ?? 'Category').toString();
                    final icon = (data['icon'] ?? '🛒').toString();
                    final imgStr = (data['imageBase64'] ?? data['imageUrl'] ?? '').toString();
                    final int order = ParseUtils.toInt(data['order'], 1);
                    final bool isActive = ParseUtils.toBool(data['isActive'], true);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 0.5,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.borderSubtle)),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 46,
                            height: 46,
                            color: AppColors.primaryLight,
                            child: imgStr.isNotEmpty
                                ? AdminImageHelper.buildImage(imgStr, width: 46, height: 46, fit: BoxFit.cover)
                                : Center(child: Text(icon.length <= 4 ? icon : '🛒', style: const TextStyle(fontSize: 20))),
                          ),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Order: #$order • ${isActive ? "Active ✅" : "Hidden ⏸️"}',
                              style: TextStyle(color: isActive ? AppColors.accentGreen : AppColors.textMuted, fontSize: 11),
                            ),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () => _openSubCategoriesManager(
                                doc.id,
                                name,
                                (data['subCategories'] is List) ? data['subCategories'] as List : const [],
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  "+ Sub-Items (${(data['subCategories'] is List) ? (data['subCategories'] as List).length : 0})",
                                  style: const TextStyle(color: AppColors.primaryPurple, fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit & Update',
                              icon: const Icon(Icons.edit_rounded, color: AppColors.primaryPurple, size: 20),
                              onPressed: () => _openCategoryDialog(docId: doc.id, data: data),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.accentRed, size: 20),
                              onPressed: () async {
                                final bool? confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Category?'),
                                    content: Text('Are you sure you want to delete "$name"?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('DELETE', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await FirebaseFirestore.instance.collection('categories').doc(doc.id).delete();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        onPressed: () => _openCategoryDialog(),
        icon: const Icon(Icons.add),
        label: const Text('NEW CATEGORY'),
      ),
    );
  }
}
