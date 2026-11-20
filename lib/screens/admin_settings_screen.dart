import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_colors.dart';
import '../utils/parse_utils.dart';

class AdminSettingsScreen extends StatefulWidget {
  final bool showAppBar;
  const AdminSettingsScreen({super.key, this.showAppBar = true});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _deliveryFeeCtrl = TextEditingController();
  final _freeThresholdCtrl = TextEditingController();
  final _handlingFeeCtrl = TextEditingController();
  final _surgeFeeCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController();

  bool _isSurgeActive = false;
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _deliveryFeeCtrl.dispose();
    _freeThresholdCtrl.dispose();
    _handlingFeeCtrl.dispose();
    _surgeFeeCtrl.dispose();
    _radiusCtrl.dispose();
    _commissionCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSettings(BuildContext context) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection('app_settings').doc('pricing').set({
        'deliveryFee': ParseUtils.toDouble(_deliveryFeeCtrl.text, 25),
        'freeDeliveryThreshold': ParseUtils.toDouble(_freeThresholdCtrl.text, 199),
        'handlingFee': ParseUtils.toDouble(_handlingFeeCtrl.text, 5),
        'surgeFee': ParseUtils.toDouble(_surgeFeeCtrl.text, 15),
        'isSurgeActive': _isSurgeActive,
        'deliveryRadiusKm': ParseUtils.toDouble(_radiusCtrl.text, 7),
        'adminCommissionPercent': ParseUtils.toDouble(_commissionCtrl.text, 10),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      messenger.showSnackBar(
        const SnackBar(content: Text('✅ Live Pricing & Delivery Settings updated!'), backgroundColor: AppColors.accentGreen),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Save error: $e'), backgroundColor: AppColors.accentRed));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Live Pricing & Surge Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textDark,
              elevation: 0.5,
            )
          : null,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('app_settings').doc('pricing').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !_loaded) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
          }

          if (!_loaded) {
            final d = (snap.hasData && snap.data!.exists)
                ? (snap.data!.data() as Map<String, dynamic>? ?? {})
                : <String, dynamic>{};
            _deliveryFeeCtrl.text = ParseUtils.toDouble(d['deliveryFee'], 25).toStringAsFixed(0);
            _freeThresholdCtrl.text = ParseUtils.toDouble(d['freeDeliveryThreshold'], 199).toStringAsFixed(0);
            _handlingFeeCtrl.text = ParseUtils.toDouble(d['handlingFee'], 5).toStringAsFixed(0);
            _surgeFeeCtrl.text = ParseUtils.toDouble(d['surgeFee'], 15).toStringAsFixed(0);
            _radiusCtrl.text = ParseUtils.toDouble(d['deliveryRadiusKm'], 7).toStringAsFixed(1);
            _commissionCtrl.text = ParseUtils.toDouble(d['adminCommissionPercent'], 10).toStringAsFixed(1);
            _isSurgeActive = d['isSurgeActive'] == true;
            _loaded = true;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Delivery & Fee Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 12),
                    _field(_deliveryFeeCtrl, 'Standard Delivery Fee (₹)'),
                    _field(_freeThresholdCtrl, 'Free Delivery Above (₹)'),
                    _field(_handlingFeeCtrl, 'Platform Handling Fee (₹)'),
                    _field(_radiusCtrl, 'Store Delivery Radius (km)'),
                    _field(_commissionCtrl, 'Admin Commission (%)'),
                    const Divider(height: 22),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Rain / Peak Surge Fee', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text('Apply extra surge charge during rain or peak hours', style: TextStyle(fontSize: 11.5)),
                      value: _isSurgeActive,
                      activeThumbColor: AppColors.accentOrange,
                      onChanged: (v) => setState(() => _isSurgeActive = v),
                    ),
                    if (_isSurgeActive) _field(_surgeFeeCtrl, 'Surge Fee Amount (₹)'),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _saving ? null : () => _saveSettings(context),
                        icon: _saving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_rounded),
                        label: const Text('SAVE LIVE SETTINGS', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }
}
