# Beamer avec Serpantinum : Hyprland et Niri

Cette adaptation est intégrée au menu et à l'installateur. Elle cible les Flatpaks utilisateur Beamer 1.5.18 et 1.5.19 et ne modifie pas ses fichiers. Le portail Hyprland fournit InputCapture, mais pas RemoteDesktop ; un pont local `uinput` fournit l'injection et un client Wayland gère le presse-papiers.

Pour préparer un essai, `./build-clipboard.sh` compile les auxiliaires dans le cache. `python3 launcher.py` démarre ensuite le pont et le Flatpak adapté ; fermer Beamer arrête le pont. Le lanceur refuse les autres versions de Beamer. L'essai exige notamment `python-evdev`, l'accès à `/dev/uinput`, `hyprctl`, `wl-paste`, un compilateur et les outils de développement Wayland.

Pendant une capture, maintenir la touche physique Échap pendant deux secondes demande le retour et la libération d'InputCapture. Pour un essai borné, définir `BEAMER_CAPTURE_TIMEOUT=30` avant de lancer le programme libère aussi automatiquement la capture au bout de 30 secondes ; la plage acceptée est de 5 à 3600 secondes et aucun délai n'est appliqué par défaut. Ces sécurités dépendent du fonctionnement du thread de capture Beamer : ce sont les seules protections, aucun raccourci de secours Hyprland n'existe plus.

Les tests sont lancés depuis la racine du dépôt avec `python3 -m pytest -q scripts/beamer`. Le presse-papiers multi-format et son anti-écho ont aussi été vérifiés dans KWin isolé. Sur la session Hyprland active, la liaison avec Jerogold, l'activation d'InputCapture et l'envoi d'événements vers Jerogold ont été observés. Le retour, l'injection réelle dans Hyprland, les verrous et changements de disposition clavier et le presse-papiers entre machines restent à vérifier avant le déploiement durable.

## Niri

Le build local décrit dans `../../docs/NIRI.md` fournit la capture d'entrée avec une expiration indépendante d'une seconde et le placement du pointeur. Le même moteur de pression et de raccourcis Beamer est conservé. Les effets utilisent leur moteur original dans des surfaces layer-shell natives par écran ; `layer-shell-qt`, Qt6Widgets et PySide6 sont requis. Le socket complet de Niri reste sur l'hôte, seuls les brokers dédiés sont accessibles au Flatpak.

Les essais Niri isolés ont exercé la capture par de vrais périphériques Wayland virtuels, les touches, la récupération du pointeur après expiration, les surfaces des effets et le chargement des adaptateurs dans Beamer 1.5.19. Le passage et le presse-papiers entre deux ordinateurs restent à tester en conditions réelles.
