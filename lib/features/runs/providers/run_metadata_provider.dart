import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/resource_refs.dart';
import 'runs_providers.dart';

final runMetadataProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, RunRef>((ref, run) async {
      final files = await ref
          .watch(runsRepositoryProvider)
          .getRunFiles(
            entity: run.entity,
            project: run.project,
            runName: run.runName,
            fileNames: ['wandb-metadata.json'],
          );
      if (files.items.isEmpty) return {};
      final url = files.items.first.directUrl;
      if (url == null || Uri.tryParse(url)?.scheme != 'https')
        throw StateError('Run metadata has no secure download URL');
      final client = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      ref.onDispose(client.close);
      final response = await client.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      return jsonDecode(response.data!) as Map<String, dynamic>;
    });
