import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

class AuthService {
  // Android emulator uses 10.0.2.2 to reach your computer localhost.
  // static const String baseUrl = 'http://10.0.2.2:8000/api/v1';
  static const String baseUrl = 'http://192.168.110.22:8000/api/v1';

  static const String _tokenKey = 'user_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _sipUsernameKey = 'sip_username';
  static const String _sipPasswordKey = 'sip_password';
  static const String _sipDomainKey = 'sip_domain';

  // ---------- Token Storage ----------
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> saveRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_refreshTokenKey, token);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  Future<void> saveSipDetails(SipAccount sip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sipUsernameKey, sip.username);
    await prefs.setString(_sipPasswordKey, sip.password);
    await prefs.setString(_sipDomainKey, sip.domain);
  }

  Future<Map<String, String?>> getSipDetails() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'username': prefs.getString(_sipUsernameKey),
      'password': prefs.getString(_sipPasswordKey),
      'domain': prefs.getString(_sipDomainKey),
    };
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_sipUsernameKey);
    await prefs.remove(_sipPasswordKey);
    await prefs.remove(_sipDomainKey);
  }

  static Map<String, String> _jsonHeaders() {
    return {'Content-Type': 'application/json'};
  }

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService().getToken();

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // ---------- API Methods ----------
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register/'),
        headers: _jsonHeaders(),
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
          'confirmPassword': confirmPassword,
        }),
      );

      final data = jsonDecode(response.body);

      if ((response.statusCode == 201 || response.statusCode == 200) &&
          data['success'] == true) {
        final user = User.fromJson(data['data']);

        final auth = AuthService();
        await auth.saveToken(user.token);

        if (user.refreshToken != null) {
          await auth.saveRefreshToken(user.refreshToken!);
        }

        if (user.sip != null) {
          await auth.saveSipDetails(user.sip!);
        }

        return {'success': true, 'message': data['message'], 'user': user};
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Registration failed',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login/'),
        headers: _jsonHeaders(),
        body: jsonEncode({'username': username, 'password': password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final user = User.fromJson(data['data']);

        final auth = AuthService();
        await auth.saveToken(user.token);

        if (user.refreshToken != null) {
          await auth.saveRefreshToken(user.refreshToken!);
        }

        if (user.sip != null) {
          await auth.saveSipDetails(user.sip!);
        }

        return {'success': true, 'message': data['message'], 'user': user};
      }

      return {'success': false, 'message': data['message'] ?? 'Login failed'};
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getMe() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/me/'),
        headers: await _authHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final user = User.fromJson(data['data']);

        final auth = AuthService();
        if (user.sip != null) {
          await auth.saveSipDetails(user.sip!);
        }

        return {'success': true, 'user': user};
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Could not fetch profile',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getBalance() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/balance/'),
        headers: await _authHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'balance': data['balance']};
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Could not fetch balance',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getCdrs() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/cdrs/'),
        headers: await _authHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'cdrs': data['cdrs']};
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Could not fetch CDRs',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getTopups() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/topups/'),
        headers: await _authHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'topups': data['topups']};
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Could not fetch top-ups',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> createCheckoutSession({
    required String amount,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/topups/create-checkout-session/'),
        headers: await _authHeaders(),
        body: jsonEncode({'amount': amount}),
      );

      final data = jsonDecode(response.body);

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data['success'] == true) {
        return {
          'success': true,
          'checkoutUrl': data['checkout_url'],
          'message': data['message'] ?? 'Checkout session created',
        };
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Could not start top-up',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> requestPasswordReset({
    required String email,
  }) async {
    return {
      'success': false,
      'message': 'Password reset API will be connected later',
    };
  }

  static Future<Map<String, dynamic>> resetPassword({
    required String token,
    required String password,
    required String confirmPassword,
  }) async {
    return {
      'success': false,
      'message': 'Password reset API will be connected later',
    };
  }

  static Future<Map<String, dynamic>> verifyToken({
    required String token,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/me/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'user': User.fromJson(data['data'])};
      }

      return {'success': false, 'message': data['message'] ?? 'Invalid token'};
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}
