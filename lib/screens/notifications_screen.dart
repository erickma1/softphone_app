import 'package:flutter/material.dart';

import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  final VoidCallback? onNotificationsChanged;

  const NotificationsScreen({super.key, this.onNotificationsChanged});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> _notifications = [];
  bool _loading = true;
  bool _markingAll = false;
  String? _error;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await NotificationService.getNotifications();

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _notifications = List<dynamic>.from(result['notifications'] ?? []);

        _unreadCount =
            int.tryParse(result['unread_count']?.toString() ?? '0') ?? 0;

        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error =
            result['message']?.toString() ?? 'Could not load notifications.';
      });
    }
  }

  Future<void> _markAsRead(Map<String, dynamic> notification) async {
    final id = int.tryParse(notification['id']?.toString() ?? '');

    if (id == null) return;

    if (notification['is_read'] == true) {
      return;
    }

    final result = await NotificationService.markAsRead(id);

    if (!mounted) return;

    if (result['success'] == true) {
      await _loadNotifications();
      widget.onNotificationsChanged?.call();
    }
  }

  Future<void> _markAllAsRead() async {
    if (_markingAll || _unreadCount == 0) return;

    setState(() {
      _markingAll = true;
    });

    final result = await NotificationService.markAllAsRead();

    if (!mounted) return;

    setState(() {
      _markingAll = false;
    });

    if (result['success'] == true) {
      await _loadNotifications();
      widget.onNotificationsChanged?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Could not update notifications.',
          ),
        ),
      );
    }
  }

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'bonus':
        return Icons.card_giftcard;
      case 'payment':
        return Icons.payments;
      case 'promotion':
        return Icons.campaign;
      case 'account':
        return Icons.person;
      case 'system':
        return Icons.settings;
      default:
        return Icons.notifications;
    }
  }

  Color _colorForType(String type) {
    switch (type.toLowerCase()) {
      case 'bonus':
        return Colors.green;
      case 'payment':
        return Colors.blue;
      case 'promotion':
        return Colors.orange;
      case 'account':
        return Colors.purple;
      case 'system':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) return '';

    final parsed = DateTime.tryParse(value.toString());

    if (parsed == null) {
      return value.toString();
    }

    final local = parsed.toLocal();

    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();

    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute';
  }

  Widget _buildNotificationItem(dynamic item) {
    final notification = Map<String, dynamic>.from(item as Map);

    final title = notification['title']?.toString() ?? 'Notification';
    final message = notification['message']?.toString() ?? '';
    final type = notification['type']?.toString() ?? 'general';
    final isRead = notification['is_read'] == true;
    final createdAt = _formatDate(notification['created_at']);

    final typeColor = _colorForType(type);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: isRead ? Colors.white : Colors.blue.shade50,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _markAsRead(notification),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: typeColor.withValues(alpha: 0.12),
                child: Icon(_iconForType(type), color: typeColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: isRead
                                  ? FontWeight.w600
                                  : FontWeight.bold,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      createdAt,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (!isRead) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Tap to mark as read',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markingAll ? null : _markAllAsRead,
              child: _markingAll
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Mark all read'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadNotifications,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 80),
                  Icon(Icons.cloud_off, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _loadNotifications,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ),
                ],
              )
            : _notifications.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 100),
                  Icon(
                    Icons.notifications_none,
                    size: 72,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No notifications yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Messages, bonuses and account updates from Number Six will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _notifications.length,
                itemBuilder: (context, index) {
                  return _buildNotificationItem(_notifications[index]);
                },
              ),
      ),
    );
  }
}
