import 'dart:convert';
import 'database_helper.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class InvalidCompanyCredentialsException implements Exception {}

class CloudSyncConflictException implements Exception {}

class CompanySyncService {
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:3000',
  );
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _sessionTokenKey = 'clefbase_session_token';
  static Future<Map<String, dynamic>> signIn({
    required String companyName,
    required String username,
    required String pin,
  }) async {
    final response = await http
        .post(
          Uri.parse('$backendUrl/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'companyName': companyName,
            'username': username,
            'pin': pin,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      if (response.statusCode == 401) {
        throw InvalidCompanyCredentialsException();
      }
      throw Exception('Company sign-in failed.');
    }

    final session = jsonDecode(response.body) as Map<String, dynamic>;
    final token = session['token'];
    if (token is! String || token.isEmpty) {
      throw Exception('The server returned an invalid session.');
    }
    await _storage.write(key: _sessionTokenKey, value: token);
    return session;
  }

  static Future<Map<String, dynamic>?> restoreSession() async {
    final token = await _storage.read(key: _sessionTokenKey);
    if (token == null) return null;

    final response = await http
        .get(
          Uri.parse('$backendUrl/api/auth/session'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 401) {
      await clearSession();
      return null;
    }
    if (response.statusCode != 200) {
      throw Exception('Could not restore the company session.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<int> uploadSnapshot(
    Map<String, List<Map<String, dynamic>>> data, {
    required int revision,
  }) async {
    final token = await _storage.read(key: _sessionTokenKey);
    if (token == null) throw Exception('Company session is missing.');
    final response = await http
        .put(
          Uri.parse('$backendUrl/api/data/snapshot'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'data': data, 'revision': revision}),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      if (response.statusCode == 409) {
        throw CloudSyncConflictException();
      }
      throw Exception('Could not upload company data.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['revision'] as num).toInt();
  }

  static Future<({Map<String, List<Map<String, dynamic>>> data, int revision})>
  downloadSnapshot() async {
    final token = await _storage.read(key: _sessionTokenKey);
    if (token == null) throw Exception('Company session is missing.');
    final response = await http
        .get(
          Uri.parse('$backendUrl/api/data/snapshot'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw Exception('Could not download company data.');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;
    final rowsByCollection = data.map(
      (key, rows) => MapEntry(
        key,
        (rows as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(),
      ),
    );
    return (
      data: rowsByCollection,
      revision: (body['revision'] as num).toInt(),
    );
  }

  static Future<void> clearSession() => _storage.delete(key: _sessionTokenKey);

  static Future<void> signOut() async {
    final token = await _storage.read(key: _sessionTokenKey);
    if (token != null) {
      try {
        await http
            .delete(
              Uri.parse('$backendUrl/api/auth/session'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // Clear local access even when revocation cannot reach the server.
      }
    }
    await clearSession();
  }

  static Future<void> syncPendingChanges(DatabaseHelper database) async {
    if (await database.hasPendingCloudChanges()) {
      await uploadCurrentSnapshot(database);
      return;
    }

    final remoteRevision = await getRemoteRevision();
    if (remoteRevision <= await database.getCloudServerRevision()) return;
    final snapshot = await downloadSnapshot();
    await database.importCompanySnapshot(
      snapshot.data,
      cloudRevision: snapshot.revision,
    );
  }

  static Future<void> uploadCurrentSnapshot(DatabaseHelper database) async {
    final revision = await database.getCloudSyncRevision();
    final snapshot = await database.exportCompanySnapshot();
    final cloudRevision = await database.getCloudServerRevision();
    final savedCloudRevision = await uploadSnapshot(
      snapshot,
      revision: cloudRevision,
    );
    await database.markCloudChangesSyncedAtRevision(
      revision,
      savedCloudRevision,
    );
  }

  static Future<int> getRemoteRevision() async {
    final token = await _storage.read(key: _sessionTokenKey);
    if (token == null) throw Exception('Company session is missing.');
    final response = await http
        .get(
          Uri.parse('$backendUrl/api/data/revision'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Could not check company data revision.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['revision'] as num).toInt();
  }

  static Future<void> updateCompanyAccount({
    String? companyName,
    String? username,
    String? oldPin,
    String? newPin,
  }) async {
    final token = await _storage.read(key: _sessionTokenKey);
    if (token == null) throw Exception('Company session is missing.');
    final response = await http
        .put(
          Uri.parse('$backendUrl/api/account'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'companyName': companyName,
            'username': username,
            'oldPin': oldPin,
            'newPin': newPin,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Could not update the company account.');
    }
  }

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
