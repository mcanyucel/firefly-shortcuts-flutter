import 'package:dio/dio.dart';
import '../settings/settings_repository.dart';
import 'dio_client.dart';
import 'models/account_dto.dart';
import 'models/pagination.dart';
import 'models/reference_dtos.dart';
import 'models/transaction_request.dart';

class FireflyApiService {
  final Dio _dio;
  final SettingsRepository _settings;

  FireflyApiService({
    required DioClient dioClient,
    required SettingsRepository settingsRepository,
  }) : _dio = dioClient.dio,
       _settings = settingsRepository;

  Future<List<AccountDto>> getAccounts() =>
      _fetchAllPages('/api/v1/accounts', AccountDto.fromJson);

  Future<List<BillDto>> getBills() =>
      _fetchAllPages('/api/v1/bills', BillDto.fromJson);

  Future<List<BudgetDto>> getBudgets() =>
      _fetchAllPages('/api/v1/budgets', BudgetDto.fromJson);

  Future<List<CategoryDto>> getCategories() =>
      _fetchAllPages('/api/v1/categories', CategoryDto.fromJson);

  Future<List<PiggybankDto>> getPiggybanks() =>
      _fetchAllPages('/api/v1/piggy-banks', PiggybankDto.fromJson);

  Future<List<TagDto>> getTags() =>
      _fetchAllPages('/api/v1/tags', TagDto.fromJson);

  Future<void> createTransaction(TransactionRequest request) async {
    final base = await _settings.getServerUrl() ?? '';
    await _dio.post('$base/api/v1/transactions', data: request.toJson());
  }

  /// ID of the user the current token belongs to.
  Future<String> getCurrentUserId() async {
    final base = await _settings.getServerUrl() ?? '';
    final response = await _dio.get('$base/api/v1/about/user');
    final data = (response.data as Map<String, dynamic>)['data'];
    return (data as Map<String, dynamic>)['id'].toString();
  }

  Future<List<T>> _fetchAllPages<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final base = await _settings.getServerUrl() ?? '';
    final result = <T>[];
    var page = 1;

    while (true) {
      final response = await _dio.get(
        '$base$path',
        queryParameters: {'page': page},
      );
      final body = response.data as Map<String, dynamic>;
      final items = (body['data'] as List)
          .map((item) => fromJson(item as Map<String, dynamic>))
          .toList();
      result.addAll(items);

      final pagination = Pagination.fromJson(
        (body['meta'] as Map<String, dynamic>)['pagination']
            as Map<String, dynamic>,
      );
      if (!pagination.hasNextPage) break;
      page++;
    }

    return result;
  }
}
