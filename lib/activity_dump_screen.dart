import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'inclinometer_data.dart';

class ActivityDumpScreen extends StatelessWidget {
  const ActivityDumpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear log',
            onPressed: () {
              context.read<InclinometerData>().clearActivityLog();
            },
          ),
        ],
      ),
      body: Consumer<InclinometerData>(
        builder: (context, data, _) {
          final entries = data.activityLog.reversed.toList();
          if (entries.isEmpty) {
            return const Center(
              child: Text('No activity recorded yet.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                dense: true,
                title: Text(entry.message),
                subtitle: Text(entry.timestamp.toIso8601String()),
              );
            },
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemCount: entries.length,
          );
        },
      ),
    );
  }
}
