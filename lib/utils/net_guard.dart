import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';

/// [Connectivity().checkConnectivity()] est un appel de canal méthode
/// Flutter↔Android : le canal est **sérialisé**, donc un seul appel qui
/// n'a jamais de réponse met en file d'attente TOUS les suivants, à jamais.
///
/// Mesuré le 2026-10-13 : le premier appel de la session, lancé pendant une
/// transition Wi-Fi/VPN du téléphone, n'a jamais répondu — et TOUTES les
/// pages artistes sont restées bloquées sur leurs squelettes (le futur de
/// `artistSongsProvider` ne se résolvait plus jamais, aucun `painted` en
/// log alors que chaque requête réseau répondait en 1-2 s).
///
/// Borné à 3 s : au-delà on suppose la connexion ACTIVE (optimiste) plutôt
/// que de figer l'app — les vrais appels réseau ont leurs propres timeouts,
/// un faux « en ligne » ne coûte qu'une tentative ratée, un faux « hors
/// ligne » coûte une page vide.
Future<List<ConnectivityResult>> safeConnectivity({
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    return await Connectivity().checkConnectivity().timeout(timeout);
  } catch (_) {
    return const <ConnectivityResult>[ConnectivityResult.wifi];
  }
}

/// Ouvre le panneau Wi-Fi système EN SURIMPRESSION au-dessus de l'app
/// (icône « Wi-Fi » de la coque). Android ≥ 10 interdit aux apps d'allumer
/// le Wi-Fi elles-mêmes — c'est une restriction système — mais le panneau
/// [Settings.Panel.ACTION_WIFI] s'ouvre sans quitter la musique : un clic,
/// l'utilisateur bascule le Wi-Fi, referme, et l'app reprend toute seule.
///
/// Appelé par le natif (`MainActivity.openWifiPanel`), avec repli sur
/// l'écran Wi-Fi complet ; renvoie false si même ce repli échoue.
const MethodChannel _appChannel = MethodChannel('com.shashwat.muzo/app');

Future<bool> openWifiPanel() async {
  try {
    await _appChannel.invokeMethod<void>('openWifiPanel');
    return true;
  } catch (_) {
    return false;
  }
}
