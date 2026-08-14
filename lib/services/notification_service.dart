import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';

class NotificationService {
  static const String baseUrl = AuthService.baseUrl;

  static Future<Map<String, dynamic>> getNotifications({
    bool unreadOnly = false,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/notifications/',
      ).replace(queryParameters: unreadOnly ? {'unread': 'true'} : null);

      final response = await http
          .get(uri, headers: await AuthService.authHeaders())
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          data is Map<String, dynamic> &&
          data['success'] == true) {
        return {
          'success': true,
          'notifications': data['notifications'] ?? [],
          'unread_count':
              int.tryParse(data['unread_count']?.toString() ?? '0') ?? 0,
        };
      }

      return {
        'success': false,
        'message': data is Map
            ? data['message']?.toString() ?? 'Could not load notifications'
            : 'Could not load notifications',
        'notifications': [],
        'unread_count': 0,
      };
    } catch (e) {
      debugPrint('[Notifications Error] $e');

      return {
        'success': false,
        'message': 'Could not load notifications',
        'notifications': [],
        'unread_count': 0,
      };
    }
  }

  static Future<int?> getUnreadCount() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/notifications/unread-count/'),
            headers: await AuthService.authHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          data is Map<String, dynamic> &&
          data['success'] == true) {
        return int.tryParse(data['unread_count']?.toString() ?? '0') ?? 0;
      }

      return null;
    } catch (e) {
      debugPrint('[Unread Notification Count Error] $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> markAsRead(int notificationId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/notifications/$notificationId/read/'),
            headers: await AuthService.authHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          data is Map<String, dynamic> &&
          data['success'] == true) {
        return {
          'success': true,
          'message': data['message']?.toString() ?? '',
          'unread_count':
              int.tryParse(data['unread_count']?.toString() ?? '0') ?? 0,
        };
      }

      return {
        'success': false,
        'message': data is Map
            ? data['message']?.toString() ??
                  'Could not mark notification as read'
            : 'Could not mark notification as read',
      };
    } catch (e) {
      debugPrint('[Mark Notification Read Error] $e');

      return {
        'success': false,
        'message': 'Could not mark notification as read',
      };
    }
  }

  static Future<Map<String, dynamic>> markAllAsRead() async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/notifications/read-all/'),
            headers: await AuthService.authHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          data is Map<String, dynamic> &&
          data['success'] == true) {
        return {
          'success': true,
          'message': data['message']?.toString() ?? '',
          'updated': int.tryParse(data['updated']?.toString() ?? '0') ?? 0,
          'unread_count': 0,
        };
      }

      return {
        'success': false,
        'message': data is Map
            ? data['message']?.toString() ??
                  'Could not mark notifications as read'
            : 'Could not mark notifications as read',
      };
    } catch (e) {
      debugPrint('[Mark All Notifications Read Error] $e');

      return {
        'success': false,
        'message': 'Could not mark notifications as read',
      };
    }
  }
}
