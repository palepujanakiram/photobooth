class ThemeModel {
  final String id;
  final String categoryId;
  final String name;
  final String description;
  final String promptText;
  final String? negativePrompt;
  final String? sampleImageUrl;
  final bool isActive;
  final String? backgroundColor; // Hex color for text background (e.g., "#FF0000" or "FF0000")
  final String? textColor; // Hex color for text (e.g., "#FFFFFF" or "FFFFFF")

  const ThemeModel({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.promptText,
    this.negativePrompt,
    this.sampleImageUrl,
    required this.isActive,
    this.backgroundColor,
    this.textColor,
  });

  /// Getter for backward compatibility with code that uses .prompt
  String get prompt => promptText;

  ThemeModel copyWith({
    String? id,
    String? categoryId,
    String? name,
    String? description,
    String? promptText,
    String? negativePrompt,
    String? sampleImageUrl,
    bool? isActive,
    String? backgroundColor,
    String? textColor,
  }) {
    return ThemeModel(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      description: description ?? this.description,
      promptText: promptText ?? this.promptText,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      sampleImageUrl: sampleImageUrl ?? this.sampleImageUrl,
      isActive: isActive ?? this.isActive,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'categoryId': categoryId,
      'name': name,
      'description': description,
      'promptText': promptText,
      'negativePrompt': negativePrompt,
      'sampleImageUrl': sampleImageUrl,
      'isActive': isActive,
      'backgroundColor': backgroundColor,
      'textColor': textColor,
    };
  }

  factory ThemeModel.fromJson(Map<String, dynamic> json) {
    return ThemeModel(
      id: json['id'] as String,
      categoryId: json['categoryId'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      promptText: json['promptText'] as String,
      negativePrompt: json['negativePrompt'] as String?,
      sampleImageUrl: json['sampleImageUrl'] as String?,
      isActive: json['isActive'] as bool,
      backgroundColor: json['backgroundColor'] as String?,
      textColor: json['textColor'] as String?,
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

