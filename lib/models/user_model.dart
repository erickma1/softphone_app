// lib/models/user_model.dart
class User {
  final int userId;
  final String username;
  final String email;
  final String token;

  User({
    required this.userId,
    required this.username,
    required this.email,
    required this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: json['userId'],
      username: json['username'],
      email: json['email'],
      token: json['token'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'email': email,
      'token': token,
    };
  }
}
