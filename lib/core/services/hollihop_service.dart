import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final hollihopServiceProvider = Provider<HolliHopService>((ref) {
  return HolliHopService();
});

class HolliHopService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: "https://sokol.t8s.ru/Api/V2/",
    queryParameters: {
      "authkey": "L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n",
    },
  ));

  Future<List<String>> getDisciplines() async {
    try {
      final response = await _dio.get("GetDisciplines");
      if (response.statusCode == 200) {
        return List<String>.from(response.data);
      }
    } catch (e) {
      print("Error fetching disciplines: $e");
    }
    return [];
  }

  Future<List<String>> getLevels() async {
    try {
      final response = await _dio.get("GetLevels");
      if (response.statusCode == 200) {
        return List<String>.from(response.data);
      }
    } catch (e) {
      print("Error fetching levels: $e");
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getLeadStatuses() async {
    try {
      final response = await _dio.get("GetLeadStatuses");
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return List<Map<String, dynamic>>.from(data['Statuses'] ?? []);
      }
    } catch (e) {
      print("Error fetching lead statuses: $e");
    }
    return [];
  }
}
