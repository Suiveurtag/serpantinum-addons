# Beamer sous Hyprland : adaptation expérimentale

Cette adaptation est en cours de validation et n'est pas encore intégrée au menu ni à l'installateur. Elle cible le Flatpak utilisateur Beamer 1.5.18 et ne modifie pas ses fichiers. Le portail Hyprland fournit InputCapture, mais pas RemoteDesktop ; un pont local `uinput` fournit l'injection et un client Wayland gère le presse-papiers.

Pour préparer un essai, `./build-clipboard.sh` compile les auxiliaires dans le cache. `python3 launcher.py` démarre ensuite le pont et le Flatpak adapté ; fermer Beamer arrête le pont. Le lanceur refuse une autre version de Beamer. L'essai exige notamment `python-evdev`, l'accès à `/dev/uinput`, `hyprctl`, `wl-paste`, un compilateur et les outils de développement Wayland.

Pendant une capture, maintenir la touche physique Échap pendant deux secondes demande le retour et la libération d'InputCapture. Pour un essai borné, définir `BEAMER_CAPTURE_TIMEOUT=30` avant de lancer le programme libère aussi automatiquement la capture au bout de 30 secondes ; la plage acceptée est de 5 à 3600 secondes et aucun délai n'est appliqué par défaut. Ces sécurités dépendent du fonctionnement du thread de capture Beamer ; elles ne remplacent pas un secours Hyprland indépendant.

Les tests sont lancés depuis la racine du dépôt avec `python3 -m pytest -q scripts/beamer`. Le presse-papiers multi-format et son anti-écho ont aussi été vérifiés dans KWin isolé. Sur la session Hyprland active, la liaison avec Jerogold, l'activation d'InputCapture et l'envoi d'événements vers Jerogold ont été observés. Le retour, l'injection réelle dans Hyprland, les verrous et changements de disposition clavier et le presse-papiers entre machines restent à vérifier avant le déploiement durable.
