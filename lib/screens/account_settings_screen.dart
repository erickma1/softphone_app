import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  bool _isLoading = true;
  String _errorMessage = '';
  User? _user;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final result = await AuthService.getMe();

    if (!mounted) return;

    if (result['success'] == true && result['user'] is User) {
      setState(() {
        _user = result['user'] as User;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage =
            result['message']?.toString() ?? 'Could not load account details.';
      });
    }
  }

  String _memberSince(String? raw) {
    if (raw == null || raw.isEmpty) {
      return 'Not available';
    }

    final date = DateTime.tryParse(raw);

    if (date == null) {
      return raw;
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: Colors.blueGrey),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  value.isEmpty ? 'Not available' : value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final customer = user?.customer;

    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
              child: ElevatedButton.icon(
                onPressed: _loadAccount,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadAccount,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 38,
                      child: Text(
                        (customer?.name.isNotEmpty == true
                                ? customer!.name
                                : user?.username ?? '?')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  Center(
                    child: Text(
                      customer?.name.isNotEmpty == true
                          ? customer!.name
                          : user?.username ?? '',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _detailRow(
                            icon: Icons.person_outline,
                            label: 'Username',
                            value: user?.username ?? '',
                          ),
                          const Divider(),

                          _detailRow(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: customer?.email.isNotEmpty == true
                                ? customer!.email
                                : user?.email ?? '',
                          ),
                          const Divider(),

                          _detailRow(
                            icon: Icons.phone_outlined,
                            label: 'Phone',
                            value: customer?.phone ?? '',
                          ),
                          const Divider(),

                          _detailRow(
                            icon: Icons.call_outlined,
                            label: 'SIP Account',
                            value: user?.sip?.username ?? '',
                          ),
                          const Divider(),

                          _detailRow(
                            icon: Icons.verified_user_outlined,
                            label: 'Account Status',
                            value: customer?.status ?? '',
                            valueColor:
                                customer?.status.toLowerCase() == 'active'
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const Divider(),

                          _detailRow(
                            icon: Icons.phone_android,
                            label: 'Phone Verification',
                            value: customer?.phoneVerified == true
                                ? 'Verified'
                                : 'Not Verified',
                            valueColor: customer?.phoneVerified == true
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const Divider(),

                          _detailRow(
                            icon: Icons.calendar_today_outlined,
                            label: 'Member Since',
                            value: _memberSince(customer?.createdAt),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    'SIP credentials are managed automatically and are not displayed here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
    );
  }
}
