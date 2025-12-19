class ThemeModel {
  final String id;
  final String name;
  final String description;
  final String prompt;
  final String negativePrompt;
  final String? previewImageUrl;

  const ThemeModel({
    required this.id,
    required this.name,
    required this.description,
    required this.prompt,
    required this.negativePrompt,
    this.previewImageUrl,
  });

  ThemeModel copyWith({
    String? id,
    String? name,
    String? description,
    String? prompt,
    String? negativePrompt,
    String? previewImageUrl,
  }) {
    return ThemeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      prompt: prompt ?? this.prompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      previewImageUrl: previewImageUrl ?? this.previewImageUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'prompt': prompt,
      'negativePrompt': negativePrompt,
      'previewImageUrl': previewImageUrl,
    };
  }

  factory ThemeModel.fromJson(Map<String, dynamic> json) {
    return ThemeModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      prompt: json['prompt'] as String,
      negativePrompt: json['negativePrompt'] as String,
      previewImageUrl: json['previewImageUrl'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemeModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

