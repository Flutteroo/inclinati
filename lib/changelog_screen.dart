import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'constants.dart';

class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key});

  Future<String> _loadChangelog(BuildContext context) async {
    return await DefaultAssetBundle.of(context).loadString('CHANGELOG.md');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Changelog'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _loadChangelog(context),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Error loading changelog: ${snapshot.error}'),
              );
            }
            final contents = snapshot.data ?? 'No changelog available.';
            final base = Theme.of(context);
      final ms = MarkdownStyleSheet.fromTheme(base).copyWith(
        h1: base.textTheme.headlineSmall
          ?.copyWith(color: alertColor, fontFamily: '3270NerdFont'),
        h2: base.textTheme.titleLarge
          ?.copyWith(color: alertColor, fontFamily: '3270NerdFont'),
        h3: base.textTheme.titleMedium
          ?.copyWith(color: alertColor, fontFamily: '3270NerdFont'),
        p: base.textTheme.bodySmall?.copyWith(fontSize: (base.textTheme.bodySmall?.fontSize ?? 14) + 2),
        code: base.textTheme.bodySmall
          ?.copyWith(color: alertColor, fontFamily: '3270NerdFont'),
              codeblockDecoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
              ),
              blockquote: base.textTheme.bodySmall?.copyWith(color: Colors.white70),
              listBullet: base.textTheme.bodySmall,
            );

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Markdown(
                data: contents,
                selectable: true,
                styleSheet: ms,
              ),
            );
          },
        ),
      ),
    );
  }
}
