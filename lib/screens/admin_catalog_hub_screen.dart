import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'admin_categories_screen.dart';
import 'admin_combos_screen.dart';
import 'admin_catalog_screen.dart';
import 'admin_coupons_screen.dart';
import 'admin_banners_screen.dart';
import 'admin_settings_screen.dart';

class AdminCatalogHubScreen extends StatefulWidget {
  const AdminCatalogHubScreen({super.key});

  @override
  State<AdminCatalogHubScreen> createState() => _AdminCatalogHubScreenState();
}

class _AdminCatalogHubScreenState extends State<AdminCatalogHubScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catalog, Promos & Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.primaryPurple,
          indicatorWeight: 3,
          labelColor: AppColors.primaryPurple,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: const [
            Tab(icon: Icon(Icons.category_rounded, size: 18), text: 'CATEGORIES'),
            Tab(icon: Icon(Icons.local_offer_rounded, size: 18), text: 'COMBOS'),
            Tab(icon: Icon(Icons.menu_book_rounded, size: 18), text: 'MASTER CATALOG'),
            Tab(icon: Icon(Icons.confirmation_number_rounded, size: 18), text: 'COUPONS'),
            Tab(icon: Icon(Icons.photo_library_rounded, size: 18), text: 'BANNERS'),
            Tab(icon: Icon(Icons.tune_rounded, size: 18), text: 'PRICING'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          AdminCategoriesScreen(showAppBar: false),
          AdminCombosScreen(showAppBar: false),
          AdminCatalogScreen(showAppBar: false),
          AdminCouponsScreen(showAppBar: false),
          AdminBannersScreen(showAppBar: false),
          AdminSettingsScreen(showAppBar: false),
        ],
      ),
    );
  }
}
