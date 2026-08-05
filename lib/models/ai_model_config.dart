/// Descriptor for a downloadable on-device AI model.
library;

import 'package:flutter_gemma/flutter_gemma.dart';

class LocalModelConfig {
  const LocalModelConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.url,
    required this.sizeMb,
    required this.modelType,
    required this.fileType,
    this.isCustom = false,
  });

  /// Filename used as the model identifier (e.g. `Qwen3-0.6B.litertlm`).
  final String id;
  final String name;
  final String description;
  final String url;

  /// Approximate download size in megabytes.
  final int sizeMb;

  final ModelType modelType;
  final ModelFileType fileType;

  /// True for user-added models (not in the predefined list).
  final bool isCustom;

  LocalModelConfig copyWith({
    String? name,
    String? url,
    int? sizeMb,
    bool? isCustom,
  }) =>
      LocalModelConfig(
        id: id,
        name: name ?? this.name,
        description: description,
        url: url ?? this.url,
        sizeMb: sizeMb ?? this.sizeMb,
        modelType: modelType,
        fileType: fileType,
        isCustom: isCustom ?? this.isCustom,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'url': url,
        'sizeMb': sizeMb,
        'isCustom': isCustom,
        'modelTypeName': modelType.name,
        'fileTypeName': fileType.name,
      };

  factory LocalModelConfig.fromJson(Map<String, dynamic> j) =>
      LocalModelConfig(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String? ?? '',
        url: j['url'] as String,
        sizeMb: j['sizeMb'] as int? ?? 0,
        modelType: ModelType.values.firstWhere(
          (e) => e.name == j['modelTypeName'],
          orElse: () => ModelType.qwen3,
        ),
        fileType: ModelFileType.values.firstWhere(
          (e) => e.name == j['fileTypeName'],
          orElse: () => ModelFileType.litertlm,
        ),
        isCustom: j['isCustom'] as bool? ?? true,
      );
}

/// Predefined on-device models the user can choose from.
const kBuiltInLocalModels = [
  LocalModelConfig(
    id: 'Qwen3-0.6B.litertlm',
    name: 'Qwen3 0.6B',
    description: 'Fast, lightweight. Good for everyday queries.',
    url:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    sizeMb: 586,
    modelType: ModelType.qwen3,
    fileType: ModelFileType.litertlm,
  ),
  LocalModelConfig(
    id: 'Qwen3-1.7B.litertlm',
    name: 'Qwen3 1.7B',
    description: 'Stronger reasoning and better accuracy. Requires ~1.1 GB.',
    url:
        'https://huggingface.co/litert-community/Qwen3-1.7B/resolve/main/Qwen3-1.7B.litertlm',
    sizeMb: 1100,
    modelType: ModelType.qwen3,
    fileType: ModelFileType.litertlm,
  ),
];
