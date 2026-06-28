import '../../utils/json_parse_helpers.dart';

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
  /// Audience flags from `/api/themes` (client filters by session person count).
  final bool? applicableSolo;
  final bool? applicableCouple;
  /// Legacy fallback when solo/couple flags are unset.
  final bool? applicableSmallGroup;
  final bool? applicableLargeGroup;
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
    this.applicableSolo,
    this.applicableCouple,
    this.applicableSmallGroup,
    this.applicableLargeGroup,
    this.backgroundColor,
    this.textColor,
  });

  /// Getter for backward compatibility with code that uses .prompt
  String get prompt => promptText;

  /// Returns a copy with fields updated via [update] (Sonar S107).
  ThemeModel copyWith(void Function(ThemeModelCopyPatch patch) update) {
    final patch = ThemeModelCopyPatch._from(this);
    update(patch);
    return patch.build();
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
      if (applicableSolo != null) 'applicableSolo': applicableSolo,
      if (applicableCouple != null) 'applicableCouple': applicableCouple,
      if (applicableSmallGroup != null)
        'applicableSmallGroup': applicableSmallGroup,
      if (applicableLargeGroup != null)
        'applicableLargeGroup': applicableLargeGroup,
      'backgroundColor': backgroundColor,
      'textColor': textColor,
    };
  }

  factory ThemeModel.fromJson(Map<String, dynamic> json) {
    // Backends sometimes rename this field (sampleImageUrl vs imageUrl, etc.).
    // Keep a single `sampleImageUrl` surface in the app by accepting common aliases.
    final sample = JsonParseHelpers.stringOrNull(json['sampleImageUrl']) ??
        JsonParseHelpers.stringOrNull(json['imageUrl']) ??
        JsonParseHelpers.stringOrNull(json['image_url']) ??
        JsonParseHelpers.stringOrNull(json['themeImageUrl']) ??
        JsonParseHelpers.stringOrNull(json['theme_image_url']);

    return ThemeModel(
      id: JsonParseHelpers.stringValue(json['id']),
      categoryId: JsonParseHelpers.stringValue(
        json['categoryId'] ?? json['category_id'],
      ),
      categoryName: JsonParseHelpers.stringOrNull(json['categoryName']),
      name: JsonParseHelpers.stringValue(json['name']),
      description: JsonParseHelpers.stringValue(json['description']),
      promptText: JsonParseHelpers.stringValue(
        json['promptText'] ?? json['prompt'],
      ),
      negativePrompt: JsonParseHelpers.stringOrNull(json['negativePrompt']),
      sampleImageUrl: sample,
      isActive: JsonParseHelpers.boolOrNull(json['isActive']),
      displayOrder: JsonParseHelpers.intOrNull(json['displayOrder']),
      applicableSolo: JsonParseHelpers.boolOrNull(json['applicableSolo']),
      applicableCouple: JsonParseHelpers.boolOrNull(json['applicableCouple']),
      applicableSmallGroup:
          JsonParseHelpers.boolOrNull(json['applicableSmallGroup']),
      applicableLargeGroup:
          JsonParseHelpers.boolOrNull(json['applicableLargeGroup']),
      backgroundColor: JsonParseHelpers.stringOrNull(json['backgroundColor']),
      textColor: JsonParseHelpers.stringOrNull(json['textColor']),
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

/// Mutable patch for [ThemeModel.copyWith] (Sonar S107).
class ThemeModelCopyPatch {
  ThemeModelCopyPatch._from(ThemeModel base)
      : id = base.id,
        categoryId = base.categoryId,
        categoryName = base.categoryName,
        name = base.name,
        description = base.description,
        promptText = base.promptText,
        negativePrompt = base.negativePrompt,
        sampleImageUrl = base.sampleImageUrl,
        isActive = base.isActive,
        displayOrder = base.displayOrder,
        applicableSolo = base.applicableSolo,
        applicableCouple = base.applicableCouple,
        applicableSmallGroup = base.applicableSmallGroup,
        applicableLargeGroup = base.applicableLargeGroup,
        backgroundColor = base.backgroundColor,
        textColor = base.textColor;

  String id;
  String categoryId;
  String? categoryName;
  String name;
  String description;
  String promptText;
  String? negativePrompt;
  String? sampleImageUrl;
  bool? isActive;
  int? displayOrder;
  bool? applicableSolo;
  bool? applicableCouple;
  bool? applicableSmallGroup;
  bool? applicableLargeGroup;
  String? backgroundColor;
  String? textColor;

  ThemeModel build() {
    return ThemeModel(
      id: id,
      categoryId: categoryId,
      categoryName: categoryName,
      name: name,
      description: description,
      promptText: promptText,
      negativePrompt: negativePrompt,
      sampleImageUrl: sampleImageUrl,
      isActive: isActive,
      displayOrder: displayOrder,
      applicableSolo: applicableSolo,
      applicableCouple: applicableCouple,
      applicableSmallGroup: applicableSmallGroup,
      applicableLargeGroup: applicableLargeGroup,
      backgroundColor: backgroundColor,
      textColor: textColor,
    );
  }
}

