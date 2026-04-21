import 'package:dio/dio.dart';

import '../../domain/entities/github_repo.dart';
import '../../domain/ports/github_repos_port.dart';

/// Production [GitHubReposPort] backed by dio. Calls
/// `GET /user/repos?per_page=100&sort=updated` with the bearer token,
/// returning every accessible repo (public + private, personal + org).
///
/// Pagination: for M1c we use `per_page=100`; GitHub caps at 100 per
/// page but lists more via `Link: rel="next"` headers. The vast majority
/// of users reviewing specs have <100 repos to pick from, so this covers
/// the happy path. Real pagination is an M1d follow-up.
class DioGitHubReposAdapter implements GitHubReposPort {
  DioGitHubReposAdapter({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _endpoint = 'https://api.github.com/user/repos';

  @override
  Future<List<GitHubRepo>> listUserRepos(String token) async {
    final Response<dynamic> resp;
    try {
      resp = await _dio.get<dynamic>(
        _endpoint,
        queryParameters: const {
          'per_page': 100,
          'sort': 'updated',
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
          responseType: ResponseType.json,
        ),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        throw GitHubReposAuthError(
          'GitHub /user/repos returned $status: ${e.response?.data}',
        );
      }
      throw GitHubReposNetworkError('dio: ${e.type} — ${e.message}');
    }
    final status = resp.statusCode ?? -1;
    if (status != 200) {
      throw GitHubReposNetworkError('Unexpected status $status: ${resp.data}');
    }
    final data = resp.data;
    if (data is! List) {
      throw GitHubReposNetworkError(
        'Expected a JSON list, got ${data.runtimeType}',
      );
    }
    return [for (final item in data) _fromJson(item as Map<String, dynamic>)];
  }

  GitHubRepo _fromJson(Map<String, dynamic> j) => GitHubRepo(
        owner: ((j['owner'] as Map<String, dynamic>)['login'] as String?) ?? '',
        name: j['name'] as String? ?? '',
        defaultBranch: j['default_branch'] as String? ?? 'main',
        isPrivate: j['private'] as bool? ?? false,
      );
}
