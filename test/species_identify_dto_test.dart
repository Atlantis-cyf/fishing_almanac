import 'package:flutter_test/flutter_test.dart';
import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/api/dto/species_identify_dto.dart';

void main() {
  group('SpeciesIdentifyPayload.fromResponseData', () {
    test('parses root map (legacy zh maps to scientific)', () {
      final p = SpeciesIdentifyPayload.fromResponseData({
        'species_zh': '鲯鳅',
        'confidence': 0.91,
      });
      expect(p.scientificName, 'Coryphaena hippurus');
      expect(p.confidence, closeTo(0.91, 0.001));
    });

    test('unwraps data wrapper', () {
      final p = SpeciesIdentifyPayload.fromResponseData({
        'data': {
          'speciesZh': '蓝鳍金枪鱼',
          'score': 88,
        },
      });
      expect(p.scientificName, 'Thunnus maccoyii');
      expect(p.confidence, closeTo(0.88, 0.001));
    });

    test('throws when species missing', () {
      expect(
        () => SpeciesIdentifyPayload.fromResponseData({'confidence': 1}),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
