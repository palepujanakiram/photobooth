class ThemeModel {
  final String id;
  final String categoryId;
  /// Optional display name for the category (e.g. "Royal", "Superhero"). When set by API, used for category tabs.
  final String? categoryName;
  final String name;
  final String description;
  final String promptText;
  final String? negativePrompt;
  final String? sampleImageUrl;
  /// When sent by backend: true = show, false = hide. When omitted (null), show theme.
  final bool? isActive;
  /// When sent by backend: order for display (ascending). When omitted (null), order is unchanged.
  final int? displayOrder;
  final String? backgroundColor; // Hex color for text background (e.g., "#FF0000" or "FF0000")
  final String? textColor; // Hex color for text (e.g., "#FFFFFF" or "FFFFFF")

  const ThemeModel({
    required this.id,
    required this.categoryId,
    this.categoryName,
    required this.name,
    required this.description,
    required this.promptText,
    this.negativePrompt,
    this.sampleImageUrl,
    this.isActive,
    this.displayOrder,
    this.backgroundColor,
    this.textColor,
  });

  /// Getter for backward compatibility with code that uses .prompt
  String get prompt => promptText;

  ThemeModel copyWith({
    String? id,
    String? categoryId,
    String? categoryName,
    String? name,
    String? description,
    String? promptText,
    String? negativePrompt,
    String? sampleImageUrl,
    bool? isActive,
    int? displayOrder,
    String? backgroundColor,
    String? textColor,
  }) {
    return ThemeModel(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      name: name ?? this.name,
      description: description ?? this.description,
      promptText: promptText ?? this.promptText,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      sampleImageUrl: sampleImageUrl ?? this.sampleImageUrl,
      isActive: isActive ?? this.isActive,
      displayOrder: displayOrder ?? this.displayOrder,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'name': name,
      'description': description,
      'promptText': promptText,
      'negativePrompt': negativePrompt,
      'sampleImageUrl': sampleImageUrl,
      if (isActive != null) 'isActive': isActive,
      if (displayOrder != null) 'displayOrder': displayOrder,
      'backgroundColor': backgroundColor,
      'textColor': textColor,
    };
  }

  factory ThemeModel.fromJson(Map<String, dynamic> json) {
    return ThemeModel(
      id: json['id'] as String,
      categoryId: json['categoryId'] as String,
      categoryName: json['categoryName'] as String?,
      name: json['name'] as String,
      description: json['description'] as String,
      promptText: json['promptText'] as String,
      negativePrompt: json['negativePrompt'] as String?,
      sampleImageUrl: json['sampleImageUrl'] as String?,
      isActive: json['isActive'] as bool?,
      displayOrder: json['displayOrder'] as int?,
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

