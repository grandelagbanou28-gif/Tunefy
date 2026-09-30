import 'package:flutter/material.dart';

import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/utils/app_colors.dart';

/// Écran de confirmation affiché juste après un paiement Moov Celestis réussi
/// (webhook confirmé côté serveur → l'app reçoit le reçu). Conçu pour être
/// poussé par le futur flux de paiement PSP ; grâce à [credits] l'écran reste
/// réutilisable quel que soit le nombre de crédits débloqués.
class MoovThanksScreen extends StatelessWidget {
  const MoovThanksScreen({super.key, this.credits = 1});

  /// Nombre de crédits ajoutés après ce paiement.
  final int credits;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Stack(
          children: [
            // Fine glow behind the check for a warmer finish.
            Positioned(
              top: -120,
              right: -120,
              child: Container(
                width: 280,
                height: 280,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x331DB954), Colors.transparent],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 550),
                    curve: Curves.easeOutBack,
                    builder: (context, t, child) => Transform.scale(
                      scale: t,
                      child: child,
                    ),
                    child: Container(
                      width: 108,
                      height: 108,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1DB954), Color(0xFF1DDA63)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x661DB954),
                            blurRadius: 28,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.black, size: 64),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    l10n.paymentThanksTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.paymentThanksSubtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 18),
                      decoration: BoxDecoration(
                        color: AppColors.cardTranslucent,
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.savings_outlined,
                              color: Color(0xFF1DB954), size: 26),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.paymentThanksCredits
                                      .replaceAll('{credits}', '$credits'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.moovCelestis,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.paymentThanksEnjoy,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        l10n.done,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}