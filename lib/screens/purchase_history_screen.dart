import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class PurchaseHistoryScreen extends StatefulWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  bool _isLoading = true;
  String _errorMessage = '';
  List<Map<String, dynamic>> _topups = [];

  @override
  void initState() {
    super.initState();
    _loadTopups();
  }

  Future<void> _loadTopups() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final result = await AuthService.getTopups();

    if (!mounted) return;

    if (result['success'] == true) {
      final rawTopups = result['topups'];

      final items = <Map<String, dynamic>>[];

      if (rawTopups is List) {
        for (final item in rawTopups) {
          if (item is Map) {
            items.add(Map<String, dynamic>.from(item));
          }
        }
      }

      setState(() {
        _topups = items;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage =
            result['message']?.toString() ?? 'Could not load purchase history.';
      });
    }
  }

  String _value(
    Map<String, dynamic> item,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = item[key];

      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }

    return fallback;
  }

  String _formatAmount(Map<String, dynamic> item) {
    final amount = _value(item, [
      'amount',
      'usd_amount',
      'topup_amount',
    ], fallback: '0');

    final parsed = double.tryParse(amount);

    if (parsed == null) {
      return 'US\$ $amount';
    }

    return 'US\$ ${parsed.toStringAsFixed(2)}';
  }

  String _formatDate(Map<String, dynamic> item) {
    final raw = _value(item, ['created_at', 'createdAt', 'date', 'timestamp']);

    if (raw.isEmpty) {
      return 'Date unavailable';
    }

    final date = DateTime.tryParse(raw);

    if (date == null) {
      return raw;
    }

    final local = date.toLocal();

    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;

    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute';
  }

  String _status(Map<String, dynamic> item) {
    final value = _value(item, [
      'status',
      'payment_status',
    ], fallback: 'Completed');

    return value;
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'success':
      case 'successful':
      case 'paid':
        return Colors.green;

      case 'pending':
        return Colors.orange;

      case 'failed':
      case 'cancelled':
        return Colors.red;

      default:
        return Colors.blueGrey;
    }
  }

  Widget _buildTopupCard(Map<String, dynamic> item) {
    final status = _status(item);
    final reference = _value(item, [
      'reference',
      'transaction_reference',
      'payment_reference',
    ]);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: Colors.green.shade50,
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                color: Colors.green,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatAmount(item),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    _formatDate(item),
                    style: TextStyle(color: Colors.grey.shade600),
                  ),

                  if (reference.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      'Reference: $reference',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: _statusColor(status),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Purchase History')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    Text(_errorMessage, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _loadTopups,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadTopups,
              child: _topups.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 140),
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 56,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 12),
                        Center(
                          child: Text(
                            'No purchases yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _topups.length,
                      itemBuilder: (context, index) {
                        return _buildTopupCard(_topups[index]);
                      },
                    ),
            ),
    );
  }
}
