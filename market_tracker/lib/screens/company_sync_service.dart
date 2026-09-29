import 'dart:convert';
import 'package:http/http.dart' as http;

class CompanySyncService {
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:3000',
  );

  static Future<bool> registerCompany({
    required String companyName,
    required String username,
  }) async {
    final response = await http.post(
      Uri.parse('$backendUrl/api/companies/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'companyName': companyName, 'username': username}),
    );

    return response.statusCode >= 200 && response.statusCode < 300;
  }

  static Future<Map<String, dynamic>?> getCompanyStatus({
    required String companyName,
  }) async {
    final response = await http.post(
      Uri.parse('$backendUrl/api/companies/status'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'companyName': companyName}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
