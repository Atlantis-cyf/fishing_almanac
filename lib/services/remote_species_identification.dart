import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import 'package:fishing_almanac/api/api_client.dart';
import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/api/catch_publish_image_prepare.dart';
import 'package:fishing_almanac/api/dto/species_identify_dto.dart';
import 'package:fishing_almanac/services/species_identification.dart';

/// 调用后端 / BFF 的鱼种识别（与 [StubSpeciesIdentificationService] 二选一注入）。
class RemoteSpeciesIdentificationService implements SpeciesIdentificationService {
  RemoteSpeciesIdentificationService({required ApiClient api}) : _api = api;

  final ApiClient _api;

  @override
  Future<SpeciesIdentificationResult> identifySpecies({
    Uint8List? imageBytes,
    String? imageUrl,
  }) async {
    final hasBytes = imageBytes != null && imageBytes.isNotEmpty;
    final url = imageUrl?.trim() ?? '';
    final hasUrl = url.isNotEmpty;

    if (!hasBytes && !hasUrl) {
      return const SpeciesIdentificationResult(scientificName: '—', confidence: 0);
    }

    final Response<dynamic> res;
    if (hasBytes) {
      final jpeg = CatchPublishImagePrepare.toUploadJpeg(imageBytes);
      final form = FormData.fromMap(<String, dynamic>{
        SpeciesIdentifyEndpoints.imageField: MultipartFile.fromBytes(
          jpeg,
          filename: 'identify.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
        if (hasUrl) 'image_url': url,
      });
      res = await _api.postMultipart<dynamic>(
        SpeciesIdentifyEndpoints.path,
        data: form,
      );
    } else {
      res = await _api.post<dynamic>(
        SpeciesIdentifyEndpoints.path,
        data: <String, dynamic>{'image_url': url},
      );
    }

    final payload = SpeciesIdentifyPayload.fromResponseData(res.data);
    return SpeciesIdentificationResult(
      scientificName: payload.scientificName,
      confidence: payload.confidence,
      rawLabel: payload.rawLabel,
      metadata: {
        ...?payload.metadata,
        'engine': 'remote',
      },
    );
  }
}
