import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _isDeleting = false;

  // 1. అన్ని ఆర్డర్లను డిలీట్ చేసే ఫంక్షన్ (Batch Delete)
  Future<void> _deleteAllOrders() async {
    setState(() => _isDeleting = true);
    final collectionRef = FirebaseFirestore.instance.collection('orders');

    try {
      final snapshot = await collectionRef.get();
      if (snapshot.docs.isEmpty) {
        _showMessage('Orders కలెక్షన్ ఖాళీగా ఉంది!');
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

      _showMessage('$counter ఆర్డర్లు విజయవంతంగా డిలీట్ చేయబడ్డాయి!');
    } catch (e) {
      _showMessage('Error: $e');
    } finally {
      setState(() => _isDeleting = false);
    }
  }

  void _showMessage(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('అన్ని ఆర్డర్లను డిలీట్ చేయాలా?'),
        content: const Text('ఈ చర్య వల్ల orders కలెక్షన్‌లో ఉన్న డేటా మొత్తం తొలగించబడుతుంది.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteAllOrders();
            },
            child: const Text('Delete All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // 2. Merchant Status Update (Approve / Block)
  Future<void> _updateMerchantStatus(String merchantId, String status) async {
    await FirebaseFirestore.instance.collection('merchants').doc(merchantId).update({'status': status});
    _showMessage('Merchant status updated to $status');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flash2Mart Central Admin'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Analytics Stats
            const Text('System Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatCard('Total Orders', 'orders', Colors.blue),
                _buildStatCard('Merchants', 'merchants', Colors.orange),
                _buildStatCard('Customers', 'users', Colors.green),
              ],
            ),
            const SizedBox(height: 24),

            // Merchant Approvals
            const Text('Merchant Controls', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('merchants').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) return const Text('మర్చెంట్లు ఎవరూ లేరు.');

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final id = docs[index].id;
                    final status = data['status'] ?? 'pending';

                    return Card(
                      child: ListTile(
                        title: Text(data['shopName'] ?? data['name'] ?? 'Merchant Store'),
                        subtitle: Text('Phone: ${data['phone']} | Status: $status'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (status != 'approved')
                              IconButton(
                                icon: const Icon(Icons.check_circle, color: Colors.green),
                                onPressed: () => _updateMerchantStatus(id, 'approved'),
                              ),
                            if (status != 'blocked')
                              IconButton(
                                icon: const Icon(Icons.block, color: Colors.red),
                                onPressed: () => _updateMerchantStatus(id, 'blocked'),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 24),

            // Database Actions
            const Text('Database Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Card(
              color: Colors.red.shade50,
              child: ListTile(
                leading: const Icon(Icons.delete_sweep, color: Colors.red, size: 32),
                title: const Text('Delete All Orders'),
                subtitle: const Text('Firestore లోని orders కలెక్షన్ మొత్తం డిలీట్ చేస్తుంది'),
                trailing: _isDeleting
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: _showDeleteConfirmation,
                        child: const Text('Delete', style: TextStyle(color: Colors.white)),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String collectionName, Color color) {
    return Expanded(
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection(collectionName).snapshots(),
        builder: (context, snapshot) {
          final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
          return Card(
            color: color.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(count.toString(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(height: 4),
                  Text(title, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}