import 'dart:ui';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupaLeadService {
  final SupabaseClient _client;

  SupaLeadService(this._client);

  /// Get leads as a stream
  Stream<List<Map<String, dynamic>>> getLeadsStream() {
    return _client
        .from('leads')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  /// Get all lead statuses
  Future<List<Map<String, dynamic>>> getStatuses() async {
    return await _client
        .from('lead_statuses')
        .select()
        .order('sort_order', ascending: true);
  }

  /// Add a new lead
  Future<void> addLead({
    required String name,
    required String phone,
    required String source,
  }) async {
    await _client.from('leads').insert({
      'name': name,
      'phone': phone,
      'source': source,
      'status': 'new',
    });
  }

  /// Update lead status (e.g. for Kanban move)
  Future<void> updateLeadStatus(String id, String newStatus) async {
    await _client.from('leads').update({'status': newStatus}).eq('id', id);
  }

  /// Update a lead's full data
  Future<void> updateLead({
    required String id,
    required Map<String, dynamic> data,
  }) async {
    await _client.from('leads').update(data).eq('id', id);
  }

  /// Get branches for metadata
  Future<List<Map<String, dynamic>>> getBranches() async {
    return await _client.from('branches').select('id, name');
  }

  /// Get lead comments as a stream
  Stream<List<Map<String, dynamic>>> getLeadCommentsStream(String leadId) {
    return _client
        .from('lead_comments')
        .stream(primaryKey: ['id'])
        .eq('lead_id', leadId)
        .order('created_at', ascending: false);
  }

  /// Add a lead-specific comment
  Future<void> addLeadComment({
    required String leadId,
    required String content,
    required String authorId,
  }) async {
    await _client.from('lead_comments').insert({
      'lead_id': leadId,
      'author_id': authorId,
      'content': content,
    });
  }

  /// Delete a lead
  Future<void> deleteLead(String id) async {
    await _client.from('leads').delete().eq('id', id);
  }

  /// Add a comment to a lead
  Future<void> addComment({
    required String leadId,
    required String content,
    required String authorId,
  }) async {
    await _client.from('entity_comments').insert({
      'entity_id': leadId,
      'entity_type': 'lead',
      'content': content.trim(),
      'author_id': authorId,
    });
  }

  /// Create a task related to a lead
  Future<void> addLeadTask({
    required String leadId,
    required String title,
    required String creatorId,
  }) async {
    await _client.from('tasks').insert({
      'title': title.trim(),
      'lead_id': leadId,
      'status': 'todo',
      'created_by': creatorId,
    });
  }

  /// Schedule a trial lesson for a lead
  Future<void> scheduleTrial({
    required String leadId,
    required String teacherId,
    required String roomId,
    required DateTime scheduledAt,
  }) async {
    await _client.from('lessons').insert({
      'lead_id': leadId,
      'teacher_id': teacherId,
      'room_id': roomId,
      'scheduled_at': scheduledAt.toIso8601String(),
      'is_trial': true,
      'status': 'planned',
    });
  }

  /// Add a new lead status
  Future<void> addStatus({
    required String key,
    required String label,
    required String color,
    required int sortOrder,
  }) async {
    await _client.from('lead_statuses').insert({
      'key': key,
      'label': label,
      'color': color,
      'sort_order': sortOrder,
    });
  }

  /// Delete a lead status
  Future<void> deleteStatus(String id) async {
    await _client.from('lead_statuses').delete().eq('id', id);
  }

  /// Update statuses list (for ManageStatusesDialog)
  Future<void> updateStatuses(List<Map<String, dynamic>> statuses) async {
     // This might be more complex depending on how the dialog update works,
     // but for now we provide a way to push updates.
     // Usually involves deleting old ones or upserting.
  }
}
