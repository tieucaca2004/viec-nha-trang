import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/notifications_service.dart';

/// Thông báo push/in-app (đặc tả mục 17).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await context.read<NotificationsService>().list();
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _markRead(String id) async {
    await context.read<NotificationsService>().markRead(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thông báo'), automaticallyImplyLeading: false),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('Chưa có thông báo nào.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index] as Map<String, dynamic>;
                      final isRead = item['readAt'] != null;
                      return ListTile(
                        leading: Icon(isRead ? Icons.notifications_none : Icons.notifications_active, color: isRead ? Colors.grey : Colors.orange),
                        title: Text(item['title'] ?? '', style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold)),
                        subtitle: Text(item['body'] ?? ''),
                        onTap: () => _markRead(item['id']),
                      );
                    },
                  ),
                ),
    );
  }
}
