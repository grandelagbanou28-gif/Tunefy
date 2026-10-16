import 'package:flutter_test/flutter_test.dart';
import 'package:muzo/services/stream_extraction_service.dart';

// Mesure du 2026-10-15 sur l'appareil : le PC sort sur une IP beninoise et les
// uploads « - Topic » francais sont sous liste de pays du label, qui exclut le
// Benin. YouTube repond donc UNPLAYABLE, yt-dlp le traduit par « Video
// unavailable », et le relais local ne livrait pas ce verdict (corps 502 coupe
// apres le budget de 28 s de l'app). Sans verdict enregistre, le meme id mort
// etait re-essaye 16 fois par session : 65 s de silence avant le toast.
void main() {
  const relayVerdict = 'FIAlvJKc3Y0';
  const twoAppVerdicts = 'h1wvM9P5Dbg';
  const oneAppVerdict = 'mJ-W7kcFY3M';
  const neverReported = 'TGN8R7EwdzQ';
  const deezerSeed = 'dz_1459516352';

  setUp(() {
    StreamExtractionService.reportVideoGone(relayVerdict, 'relay');
    StreamExtractionService.reportVideoGone(twoAppVerdicts, 'explode');
    StreamExtractionService.reportVideoGone(twoAppVerdicts, 'ytapi');
    StreamExtractionService.reportVideoGone(oneAppVerdict, 'explode');
  });

  test('un seul verdict du relais suffit a couper la cascade', () {
    expect(StreamExtractionService.isVideoGone(relayVerdict), isTrue);
  });

  test('deux clients de l\'app concordants suffisent aussi', () {
    expect(StreamExtractionService.isVideoGone(twoAppVerdicts), isTrue);
  });

  test('un client isolé ne déclare pas la vidéo morte', () {
    // L'IP de l'appareil a déjà refusé toutes les pistes sans que les uploads
    // soient en cause : un verdict unique ne doit pas raccourcir la cascade.
    expect(StreamExtractionService.isVideoGone(oneAppVerdict), isFalse);
  });

  test('un id jamais signalé reste résolvable normalement', () {
    expect(StreamExtractionService.isVideoGone(neverReported), isFalse);
  });

  test('un seed metadata n\'est pas une vidéo et ne peut pas être « mort »', () {
    StreamExtractionService.reportVideoGone(deezerSeed, 'relay');
    expect(StreamExtractionService.isMetadataSeedId(deezerSeed), isTrue);
    expect(StreamExtractionService.isVideoGone(deezerSeed), isFalse);
  });
}
