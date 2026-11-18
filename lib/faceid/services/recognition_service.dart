import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../api.dart';
import '../services/database_service.dart';
import '../services/face_service.dart';
import '../services/photo_store.dart';
import '../services/settings_service.dart';

class NoKnownFacesException implements Exception {
  NoKnownFacesException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MatchDetails {
  const MatchDetails({
    required this.scores,
    required this.bestPersonId,
    required this.bestScore,
    required this.secondPersonId,
    required this.secondScore,
    required this.matched,
    required this.ambiguous,
    required this.threshold,
  });

  final Map<int, double> scores;
  final int? bestPersonId;
  final double bestScore;
  final int? secondPersonId;
  final double secondScore;
  final bool matched;
  final bool ambiguous;
  final double threshold;
}

class PhotoAnalysis {
  const PhotoAnalysis({
    required this.normalizedJpeg,
    required this.faceCount,
    this.embedding,
    this.alignedJpeg,
  });

  final Uint8List normalizedJpeg;
  final int faceCount;
  final Float32List? embedding;
  final Uint8List? alignedJpeg;
}

class FrameScan {
  const FrameScan({required this.analysis, required this.match, this.error});

  final PhotoAnalysis analysis;
  final MatchDetails? match;
  final String? error;

  int get faceCount => analysis.faceCount;
  bool get matched => match?.matched ?? false;
}

class ScanOutcome {
  const ScanOutcome({
    required this.frames,
    required this.selected,
    required this.maxFaceCount,
  });

  final List<FrameScan> frames;
  final FrameScan? selected;
  final int maxFaceCount;

  bool get anyFace => frames.any((frame) => frame.faceCount > 0);
}

class PersonScore {
  const PersonScore({required this.personId, required this.score});

  final int personId;
  final double score;
}

class RecognitionService {
  RecognitionService._();

  static final RecognitionService instance = RecognitionService._();

  final _faceService = FaceService.instance;
  final _db = DatabaseService.instance;
  final _settings = SettingsService.instance;

  Map<int, List<Float32List>>? _index;
  String? _indexAccount;

  Future<void> init() async {
    await _faceService.init();
  }

  Future<void> invalidateIndex() async {
    _index = null;
    _indexAccount = null;
  }

  Future<Map<int, List<Float32List>>> _loadIndex() async {
    // Yuzlarni faqat joriy account xodimlari ichida solishtiramiz.
    // Bir odam boshqa accountda ham xodim bo'lsa, ular bir-biriga
    // "o'xshash boshqa xodim" sifatida ko'rinmasligi kerak.
    final account = (Api.instance.user?.account ?? '').trim();
    final cached = _index;
    if (cached != null && _indexAccount == account) return cached;
    final stored = await _db.getAllEmbeddings(
      accountName: account.isEmpty ? null : account,
    );
    if (stored.isEmpty) {
      _index = <int, List<Float32List>>{};
      _indexAccount = account;
      return _index!;
    }
    final index = <int, List<Float32List>>{};
    for (final item in stored) {
      var norm = 0.0;
      for (final value in item.vector) {
        norm += value * value;
      }
      norm = math.sqrt(norm);
      if (norm <= 1e-9) continue;
      final vector = Float32List(item.vector.length);
      for (var i = 0; i < item.vector.length; i++) {
        vector[i] = item.vector[i] / norm;
      }
      index.putIfAbsent(item.personId, () => <Float32List>[]).add(vector);
    }
    _index = index;
    _indexAccount = account;
    return index;
  }

  Future<MatchDetails> matchEmbedding(
    Float32List embedding, {
    int? onlyPersonId,
  }) async {
    final index = await _loadIndex();
    final candidates = onlyPersonId == null
        ? index
        : <int, List<Float32List>>{
            if (index[onlyPersonId]?.isNotEmpty ?? false)
              onlyPersonId: index[onlyPersonId]!,
          };
    if (candidates.isEmpty) {
      throw NoKnownFacesException(
        onlyPersonId == null
            ? "Bazada ma'lum yuzlar yo'q. Avval xodimni ro'yxatdan o'tkazing."
            : "Sizning yuzingiz hali bog'lanmagan. Avval yuz rasmlarini "
                  "bog'lang yoki administratorga murojaat qiling.",
      );
    }

    final scores = <int, double>{};
    for (final entry in candidates.entries) {
      var best = -1.0;
      for (final known in entry.value) {
        var dot = 0.0;
        final length = math.min(embedding.length, known.length);
        for (var i = 0; i < length; i++) {
          dot += embedding[i] * known[i];
        }
        if (dot > best) best = dot;
      }
      scores[entry.key] = math.max(0.0, best);
    }

    final ordered = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final bestPersonId = ordered.first.key;
    final bestScore = ordered.first.value;
    final secondPersonId = ordered.length > 1 ? ordered[1].key : null;
    final secondScore = ordered.length > 1 ? ordered[1].value : 0.0;
    final threshold = _settings.matchThreshold;
    final ambiguous =
        bestScore >= threshold &&
        secondScore >= threshold &&
        (bestScore - secondScore) < _settings.ambiguityMargin;
    final matched = bestScore >= threshold && !ambiguous;

    return MatchDetails(
      scores: scores,
      bestPersonId: bestPersonId,
      bestScore: bestScore,
      secondPersonId: secondPersonId,
      secondScore: secondScore,
      matched: matched,
      ambiguous: ambiguous,
      threshold: threshold,
    );
  }

  Future<PersonScore?> bestOtherMatch(
    Float32List embedding, {
    int? excludePersonId,
  }) async {
    final index = await _loadIndex();
    if (index.isEmpty) return null;

    PersonScore? best;
    for (final entry in index.entries) {
      if (excludePersonId != null && entry.key == excludePersonId) continue;
      var personBest = -1.0;
      for (final known in entry.value) {
        var dot = 0.0;
        final length = math.min(embedding.length, known.length);
        for (var i = 0; i < length; i++) {
          dot += embedding[i] * known[i];
        }
        if (dot > personBest) personBest = dot;
      }
      if (personBest < 0) continue;
      if (best == null || personBest > best.score) {
        best = PersonScore(personId: entry.key, score: personBest);
      }
    }
    return best;
  }

  Future<PhotoAnalysis> analyzePhoto(String originalPath) async {
    final original = await _readFile(originalPath);
    final normalized = await _faceService.normalizeImage(original);
    if (normalized == null) {
      return PhotoAnalysis(normalizedJpeg: original, faceCount: 0);
    }

    final normalizedBytes = normalized['bytes'] as Uint8List;
    final tempName =
        'scan_${DateTime.now().microsecondsSinceEpoch}_${p.basename(originalPath)}.jpg';
    final tempPath = await PhotoStore.writeTemp(normalizedBytes, tempName);

    try {
      final faces = await _faceService.detectFaces(tempPath);
      if (faces.isEmpty) {
        return PhotoAnalysis(normalizedJpeg: normalizedBytes, faceCount: 0);
      }
      if (faces.length > 1) {
        return PhotoAnalysis(
          normalizedJpeg: normalizedBytes,
          faceCount: faces.length,
        );
      }

      final prepared = await _faceService.prepareFaceInput(
        imageBytes: normalizedBytes,
        face: faces.first,
      );
      if (prepared == null) {
        return PhotoAnalysis(normalizedJpeg: normalizedBytes, faceCount: 1);
      }
      final embedding = _faceService.embed(prepared.input);
      return PhotoAnalysis(
        normalizedJpeg: normalizedBytes,
        faceCount: 1,
        embedding: embedding,
        alignedJpeg: prepared.alignedJpeg,
      );
    } finally {
      await PhotoStore.deleteQuietly(tempPath);
    }
  }

  Future<ScanOutcome> scanPhotos(
    List<String> paths, {
    void Function(int done, int total)? onProgress,
    int? onlyPersonId,
  }) async {
    final frames = <FrameScan>[];
    for (var i = 0; i < paths.length; i++) {
      try {
        final analysis = await analyzePhoto(paths[i]);
        MatchDetails? match;
        if (analysis.embedding != null) {
          match = await matchEmbedding(
            analysis.embedding!,
            onlyPersonId: onlyPersonId,
          );
        }
        frames.add(FrameScan(analysis: analysis, match: match));
      } on NoKnownFacesException {
        rethrow;
      } catch (error) {
        frames.add(
          FrameScan(
            analysis: PhotoAnalysis(normalizedJpeg: Uint8List(0), faceCount: 0),
            match: null,
            error: error.toString(),
          ),
        );
      }
      onProgress?.call(i + 1, paths.length);
    }

    if (frames.every((frame) => frame.analysis.normalizedJpeg.isEmpty)) {
      throw StateError("Rasmlarni o'qib bo'lmadi.");
    }

    final singleMatched =
        frames
            .where(
              (frame) =>
                  frame.faceCount == 1 && frame.matched && frame.match != null,
            )
            .toList()
          ..sort((a, b) => b.match!.bestScore.compareTo(a.match!.bestScore));
    final singleFace = frames.where((frame) => frame.faceCount == 1).toList()
      ..sort(
        (a, b) => (b.match?.bestScore ?? 0).compareTo(a.match?.bestScore ?? 0),
      );

    FrameScan? selected;
    if (singleMatched.isNotEmpty) {
      selected = singleMatched.first;
    } else if (singleFace.isNotEmpty) {
      selected = singleFace.first;
    } else {
      final maxFaces = frames.fold<int>(
        0,
        (value, frame) => math.max(value, frame.faceCount),
      );
      if (maxFaces > 1) {
        selected = frames.firstWhere((frame) => frame.faceCount == maxFaces);
      } else {
        selected = frames.isNotEmpty ? frames.last : null;
      }
    }

    final maxFaceCount = frames.fold<int>(
      0,
      (value, frame) => math.max(value, frame.faceCount),
    );
    return ScanOutcome(
      frames: frames,
      selected: selected,
      maxFaceCount: maxFaceCount,
    );
  }

  Future<Uint8List> _readFile(String path) async {
    return File(path).readAsBytes();
  }
}
