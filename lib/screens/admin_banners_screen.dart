import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_colors.dart';
import '../utils/image_helper.dart';

class AdminBannersScreen extends StatefulWidget {
  final bool showAppBar;
  const AdminBannersScreen({super.key, this.showAppBar = true});

  @override
  State<AdminBannersScreen> createState() => _AdminBannersScreenState();
}

class _AdminBannersScreenState extends State<AdminBannersScreen> {
  Future<void> _toggleBanner(BuildContext context, String docId, bool current) async {
    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance.collection('banners').doc(docId).update({
      'isActive': !current,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(!current ? 'Banner is now LIVE!' : 'Banner hidden.'),
        backgroundColor: !current ? AppColors.accentGreen : AppColors.accentOrange,
      ),
    );
  }

  Future<void> _deleteBanner(BuildContext context, String docId) async {
    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance.collection('banners').doc(docId).delete();
    messenger.showSnackBar(const SnackBar(content: Text('Banner deleted.'), backgroundColor: AppColors.accentRed));
  }

  void _showAddBannerDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final subCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    String imgStr = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Add Home Promo Banner'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final picked = await AdminImageHelper.pickAndCompressBase64(targetWidth: 400);
                      if (picked != null) {
                        setDialogState(() => imgStr = picked);
                      }
                    },
                    child: Container(
                      height: 110,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.bgLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: imgStr.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: AdminImageHelper.buildImage(imgStr, fit: BoxFit.cover),
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_rounded, size: 32, color: AppColors.primaryPurple),
                                SizedBox(height: 4),
                                Text('Tap to pick Banner Image', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Banner Title (e.g. Weekend Mega Sale)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: subCtrl,
                    decoration: const InputDecoration(labelText: 'Subtitle (e.g. Up to 40% OFF Fresh Fruits)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: targetCtrl,
                    decoration: const InputDecoration(labelText: 'Target Category (Optional)', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple, foregroundColor: Colors.white),
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty) return;
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);

                  await FirebaseFirestore.instance.collection('banners').add({
                    'title': title,
                    'subtitle': subCtrl.text.trim(),
                    'targetCategory': targetCtrl.text.trim(),
                    'imageUrl': imgStr,
                    'imageBase64': imgStr,
                    'isActive': true,
                    'createdAt': FieldValue.serverTimestamp(),
                  });

                  messenger.showSnackBar(
                    const SnackBar(content: Text('✅ Home Banner published!'), backgroundColor: AppColors.accentGreen),
                  );
                },
                child: const Text('PUBLISH BANNER'),
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
              title: const Text('Home Promo Banners', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textDark,
              elevation: 0.5,
            )
          : null,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        onPressed: () => _showAddBannerDialog(context),
        icon: const Icon(Icons.add_photo_alternate_rounded),
        label: const Text('ADD BANNER', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('banners').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
          }
          final docs = snap.hasData ? snap.data!.docs : <QueryDocumentSnapshot>[];
          if (docs.isEmpty) {
            return const Center(
              child: Text('No banners yet. Tap ADD BANNER to publish one!', style: TextStyle(color: AppColors.textMuted)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
            itemCount: docs.length,
            itemBuilder: (context, idx) {
              final doc = docs[idx];
              final d = doc.data() as Map<String, dynamic>;
              final title = (d['title'] ?? 'Promo Banner').toString();
              final sub = (d['subtitle'] ?? '').toString();
              final img = (d['imageBase64'] ?? d['imageUrl'] ?? '').toString();
              final isActive = d['isActive'] != false;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: Colors.white,
                elevation: 0.5,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (img.isNotEmpty)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                        child: SizedBox(
                          height: 110,
                          width: double.infinity,
                          child: AdminImageHelper.buildImage(img, fit: BoxFit.cover),
                        ),
                      ),
                    ListTile(
                      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: sub.isNotEmpty ? Text(sub, style: const TextStyle(fontSize: 12)) : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: isActive,
                            activeThumbColor: AppColors.accentGreen,
                            onChanged: (_) => _toggleBanner(context, doc.id, isActive),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppColors.accentRed),
                            onPressed: () => _deleteBanner(context, doc.id),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
