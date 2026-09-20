import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/list_sorting.dart';

class BatchesTab extends StatefulWidget {
  const BatchesTab({super.key});

  @override
  State<BatchesTab> createState() => _BatchesTabState();
}

class _BatchesTabState extends State<BatchesTab> {
  final supabase = Supabase.instance.client;
  List<dynamic> batches = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchBatches();
  }

  Future<void> fetchBatches() async {
    try {
      final response = await supabase.from('batches').select().order('name');
      setState(() {
        batches = sortBatches(response);
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching batches: $e');
      setState(() => isLoading = false);
    }
  }

  void _showBatchFormDialog({Map<String, dynamic>? batch}) {
    final isEditing = batch != null;
    final nameController = TextEditingController(
      text: isEditing ? batch['name'] : '',
    );
    final whatsappController = TextEditingController(
      text: isEditing ? batch['whatsapp_group_id'] ?? '' : '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? 'Edit Batch' : 'Add New Batch'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Batch Name'),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: whatsappController,
                decoration: const InputDecoration(
                  labelText: 'WhatsApp Group ID',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final wId = whatsappController.text.trim();
                if (name.isEmpty) return;

                Navigator.pop(context);
                setState(() => isLoading = true);

                try {
                  if (isEditing) {
                    await supabase
                        .from('batches')
                        .update({
                          'name': name,
                          'whatsapp_group_id': wId.isEmpty ? null : wId,
                        })
                        .eq('id', batch['id']);
                  } else {
                    await supabase.from('batches').insert({
                      'name': name,
                      'whatsapp_group_id': wId.isEmpty ? null : wId,
                    });
                  }
                  fetchBatches();
                } catch (e) {
                  debugPrint('Error saving batch: $e');
                  setState(() => isLoading = false);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _deleteBatch(String id, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Batch?'),
        content: Text(
          'Kiya tum waqai "$name" ko delete karna chahte ho? Is se jure tamam students error generate kar sakte hain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(context);
              setState(() => isLoading = true);
              try {
                await supabase.from('batches').delete().eq('id', id);
                fetchBatches();
              } catch (e) {
                debugPrint('Delete error: $e');
                setState(() => isLoading = false);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Error: Pehle is batch k students ko remove karo!',
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showBatchFormDialog(),
        child: const Icon(Icons.add),
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/school_bg.png'),
            fit: BoxFit.cover,
            opacity: 0.25,
          ),
        ),
        child: batches.isEmpty
            ? const Center(child: Text('No batches found in Supabase.'))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: batches.length,
                itemBuilder: (context, index) {
                  final batch = batches[index];
                  final batchName = batch['name']?.toString() ?? 'Batch';
                  final whatsappId =
                      batch['whatsapp_group_id']?.toString() ?? 'Not Set';

                  return Card(
                    elevation: 3,
                    color: Colors.white.withValues(alpha: 0.96),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      leading: const Icon(
                        Icons.class_,
                        color: Color(0xFF0B2B5E),
                        size: 26,
                      ),
                      title: Text(
                        batchName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      subtitle: Text(whatsappId),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showBatchFormDialog(batch: batch),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () =>
                                _deleteBatch(batch['id'], batch['name']),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
