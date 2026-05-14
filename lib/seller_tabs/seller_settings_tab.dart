import 'package:flutter/material.dart';

import '../seller_home_page.dart';
import '../seller_session.dart';

class SellerSettingsTab extends StatelessWidget {
  const SellerSettingsTab({super.key});

  Future<void> _logout(BuildContext context) async {
    await SellerSession.clear();
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SellerHomePage(isSellerMode: false)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.account_circle, size: 80, color: Colors.teal),
          const SizedBox(height: 20),
          FutureBuilder<SellerSession?>(
            future: SellerSession.current(),
            builder: (context, snapshot) {
              final session = snapshot.data;
              return Column(
                children: [
                  Text(
                    session?.name ?? 'Seller',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    session?.phoneNumber ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout),
            label: const Text('Logout', style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
