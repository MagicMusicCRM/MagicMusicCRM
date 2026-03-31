import 'dart:convert';
import 'dart:io';

const String apiUrl = "https://sokol.t8s.ru/Api/V2/";
const String authKey = "L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n";

final String backupDir = "hollihop_backup_${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}";

Future<dynamic> _fetch(String endpoint, bool useV1, [Map<String, String>? params]) async {
  final queryParams = <String, String>{
    'authkey': authKey,
    ...?params,
  };
  
  final base = useV1 ? apiUrl.replaceAll('/V2/', '/V1/') : apiUrl;
  final uri = Uri.parse("$base$endpoint").replace(queryParameters: queryParams);
  print("Fetching from $endpoint ${useV1 ? '(V1)' : '(V2)'}...");
  
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final content = await response.transform(utf8.decoder).join();
    try {
      return json.decode(content);
    } catch (_) {
      if (response.statusCode != 200) {
        print("Failed to fetch $endpoint: HTTP ${response.statusCode}");
      }
      return null;
    }
  } catch (e) {
    print("Error fetching $endpoint: $e");
    return null;
  } finally {
    client.close();
  }
}

Future<dynamic> fetchData(String endpoint, [Map<String, String>? params]) => _fetch(endpoint, false, params);
Future<dynamic> fetchDataV1(String endpoint, [Map<String, String>? params]) => _fetch(endpoint, true, params);

Future<void> saveJson(String filename, dynamic data) async {
  final file = File("$backupDir/$filename");
  await file.parent.create(recursive: true);
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  print("Saved $filename");
}

void main() async {
  print("Starting HolliHop CRM Export to $backupDir...");
  
  final take = "200";

  // Core (V2)
  final core = ["GetLocations", "GetOffices", "GetLeadStatuses", "GetTeachers", "GetEdUnits"];
  for (final ep in core) {
    final data = await fetchData(ep);
    if (data != null) await saveJson("${ep.toLowerCase().replaceAll('get', '')}.json", data);
  }

  // Paginated (V2)
  final paginated = {
    "GetLeads": "Leads",
    "GetStudents": "Students",
    "GetEdUnitStudents": "EdUnitStudents",
    "GetPayments": "Payments",
  };

  List<dynamic> allStudentsList = [];

  for (final entry in paginated.entries) {
    List<dynamic> all = [];
    int skip = 0;
    while (true) {
      final res = await fetchData(entry.key, {"skip": skip.toString(), "take": take});
      if (res == null || res[entry.value] == null) break;
      final List chunk = res[entry.value];
      all.addAll(chunk);
      print("  Fetched ${chunk.length} ${entry.value} (Total: ${all.length})");
      if (chunk.length < int.parse(take)) break;
      skip += int.parse(take);
    }
    if (all.isNotEmpty) {
      await saveJson("${entry.key.toLowerCase().replaceAll('get', '')}.json", {entry.value: all});
      if (entry.key == "GetStudents") allStudentsList = all;
    }
  }

  // History / Logs
  print("\n--- Testing History & Logs ---");
  for (final ep in ["GetTasks", "GetStudentLogs", "GetCommunicationLogs", "GetComments"]) {
      final dataV1 = await fetchDataV1(ep);
      if (dataV1 != null) await saveJson("${ep.toLowerCase()}_v1.json", dataV1);
      final dataV2 = await fetchData(ep);
      if (dataV2 != null) await saveJson("${ep.toLowerCase()}_v2.json", dataV2);
  }

  // Individual Student details (Sample)
  if (allStudentsList.isNotEmpty) {
    print("\n--- Fetching individual student details (Sample) ---");
    final sampleSize = allStudentsList.length > 5 ? 5 : allStudentsList.length;
    List<dynamic> details = [];
    for (int i = 0; i < sampleSize; i++) {
        final id = allStudentsList[i]["Id"];
        final d = await fetchData("GetStudent", {"id": id.toString()});
        if (d != null) details.add(d);
    }
    if (details.isNotEmpty) await saveJson("student_details_sample.json", details);
  }

  print("\nExport complete in $backupDir!");
}
