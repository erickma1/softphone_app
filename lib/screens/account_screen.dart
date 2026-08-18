import 'package:flutter/material.dart';

class AccountScreen extends StatelessWidget {
  final VoidCallback onAccountSettings;
  final VoidCallback onConnectionSettings;
  final VoidCallback onRates;
  final VoidCallback onPurchaseHistory;
  final VoidCallback onLogout;
  final VoidCallback onSupport;

  const AccountScreen({
    super.key,
    required this.onAccountSettings,
    required this.onConnectionSettings,
    required this.onRates,
    required this.onPurchaseHistory,
    required this.onLogout,
    required this.onSupport,
  });

  Widget _menuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.grey.shade100,
          child: Icon(icon, color: iconColor ?? Colors.blue),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Account',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 6),

          Text(
            'Manage your account, connection and calling preferences.',
            style: TextStyle(color: Colors.grey.shade600),
          ),

          const SizedBox(height: 24),

          _menuItem(
            icon: Icons.person_outline,
            title: 'Account Settings',
            subtitle: 'Personal and account details',
            onTap: onAccountSettings,
          ),

          _menuItem(
            icon: Icons.settings_ethernet,
            title: 'Connection Settings',
            subtitle: 'SIP registration and transport',
            onTap: onConnectionSettings,
          ),

          _menuItem(
            icon: Icons.attach_money,
            title: 'Rates',
            subtitle: 'International calling rates',
            onTap: onRates,
          ),

          _menuItem(
            icon: Icons.receipt_long_outlined,
            title: 'Purchase History',
            subtitle: 'View your wallet top-ups',
            onTap: onPurchaseHistory,
          ),

          _menuItem(
            icon: Icons.support_agent,
            title: 'Support',
            subtitle: 'Contact Number 6 support',
            onTap: onSupport,
            ),

          const SizedBox(height: 8),

          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.red.shade100),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: CircleAvatar(
                backgroundColor: Colors.red.shade50,
                child: const Icon(Icons.logout, color: Colors.red),
              ),
              title: const Text(
                'Log Out',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: onLogout,
            ),
          ),
        ],
      ),
    );
  }
}
