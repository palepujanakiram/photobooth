import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/utils/exceptions.dart';

import '../fakes/fake_api_service.dart';

class ThemesFakeApi extends FakeApiService {
  ThemesFakeApi(this.themes, {this.throwOnFetch = false});

  final List<ThemeModel> themes;
  final bool throwOnFetch;

  @override
  Future<List<ThemeModel>> getThemes() async {
    if (throwOnFetch) throw ApiException('themes down');
    return themes;
  }
}

ThemeModel sampleTheme(String id) => ThemeModel(
      id: id,
      categoryId: 'c1',
      name: 'Theme $id',
      description: 'd',
      promptText: 'p',
      sampleImageUrl: '/$id.jpg',
      isActive: true,
      displayOrder: 1,
    );
