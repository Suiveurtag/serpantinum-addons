# Niri avec Serpantinum et les addons

Le portage utilise le support Niri natif de Serpantinum et une version locale de Niri pour les interfaces supplémentaires nécessaires aux addons. Cette version locale a été autorisée par l'utilisateur. Hyprland reste disponible.

## Installation locale préparée

- Binaire : `~/.local/opt/niri-serpantinum/bin/niri`.
- Provenance : `~/.local/opt/niri-serpantinum/BUILD.json`.
- Base officielle : `niri-wm/niri`, commit `73a04441fccc78294c3899af8f8cdd2a1e38fa33`.
- Patch reproductible : `compositor/niri-serpantinum.patch`.
- Reconstruction : `compositor/build-niri.sh` ; aucune écriture dans les paquets système.
- Commande de session : `~/.local/bin/niri-serpantinum-session`.
- Configuration : `~/.config/niri/config.kdl`, avec sauvegarde `config.kdl.before-full-compat-*`.

L'entrée **Niri (Serpantinum + addons)** est enregistrée dans SDDM sur ce poste. Pour la réinstaller sur une autre installation, la commande est :

```sh
sudo install -m 644 ~/.local/share/wayland-sessions/niri-serpantinum.desktop /usr/share/wayland-sessions/niri-serpantinum.desktop
```

Ensuite, fermer normalement la session et choisir **Niri (Serpantinum + addons)**. Il est également possible de lancer `niri-serpantinum-session` depuis un TTY après avoir quitté la session graphique. Le lanceur refuse le lancement accidentel à l'intérieur d'un autre bureau. Le choix Hyprland permet de revenir à la session précédente.

## Fonctions adaptées

| Fonction | Chemin Niri |
| --- | --- |
| Clawd et Capri | Géométrie réelle des fenêtres, positions animées, écrans, workspaces, fenêtre active et pointeur global |
| Supports de Clawd | Rectangles natifs des widgets, barres et popups, avec réservations des écrans |
| Sessions Clawd | Focus du terminal par PID et identifiant de fenêtre Niri |
| Surge Clawd | Zoom du vrai bureau centré sur Clawd, masquage du pointeur pendant l'effet et retour au workspace initial |
| Zoom du bureau | Agrandissement natif du rendu, molette, animation, restauration et expiration automatique du pilote |
| Spotlight | Coordonnées du pointeur sur la surface native et prise en compte de l'origine de chaque écran |
| Pipette et dessin | Sélection d'écran indépendante de Hyprland ; capture et entrée Wayland natives |
| Raccourcis du Guide | Blocs multilignes, commandes, actions natives, fichiers inclus, ajout/suppression et détection des changements concurrents |
| Écrans du Guide | Modes, positions, échelle et rotation via les sorties Niri |
| Clavier | Dispositions XKB et conservation des autres options, notamment AltGr |
| Souris et trackpad | Accélération, vitesse, DWT et blocage séparé des clics pendant la frappe |
| Curseurs | Export existant conservé ; thème et taille configurés dans Niri, GTK et les environnements concernés |
| Démarrage | Fragment KDL séparé et préférences existantes conservées |
| Bordures | Activation/désactivation, couleurs et gradient de la palette du shell |
| Beamer 1.5.18/1.5.19 | Capture native, injection existante, position du pointeur, presse-papiers et moteur d'effets original sur des surfaces natives par écran |

Les fragments de périphériques conservent les options existantes : Niri remplace certains sous-blocs complets lors des inclusions. Les fichiers sont validés avec le binaire local avant conservation ; une erreur restaure les fichiers précédents. Les changements souris/trackpad sont également vérifiés dans la configuration effective du compositeur.

La configuration de session reprend les écrans DP-1 et HDMI-A-1, le clavier français, le curseur personnalisé, les applications au démarrage, les raccourcis du shell et des addons, les touches multimédias, la ligne AZERTY des workspaces, le redimensionnement et le changement d'écran. Le placement des fenêtres suit naturellement le modèle défilant de Niri.

## Interfaces locales et restauration

L'API `Serpantinum` est versionnée (`1`) et reste sur le socket IPC de la session Niri. Elle ne lance aucune commande shell. Les positions, facteurs de zoom et tailles des requêtes sont bornés.

Le zoom revient à ×1 si son pilote cesse de répondre pendant deux secondes. La capture Beamer possède un propriétaire explicite, une file bornée et une expiration d'une seconde ; elle est libérée à la déconnexion, à l'expiration, au verrouillage et après maintien d'Échap. La capture est désactivée tant que Beamer n'a pas explicitement placé ses barrières. Le Flatpak reçoit uniquement ses sockets dédiés, pas le socket IPC complet du compositeur.

## Vérifications

`tests/niri_live.py` démarre un compositeur imbriqué avec sockets et préférences isolés. Les essais ont validé :

- Une vraie fenêtre, ses coordonnées, le déplacement du pointeur et le retour de workspace.
- Les pixels du zoom natif, son pilote animé, la restauration après SIGKILL et le zoom centré du surge.
- L'application des réglages souris, clavier et trackpad, les bordures et le démarrage en préservant les options existantes.
- Le shell complet avec Clawd et Capri activés : fenêtres et pointeur réels, widgets, couches et fermeture d'une fenêtre.
- L'ouverture des outils du shell et un trait de dessin produit par de vrais événements Wayland de test.
- La capture Beamer par périphériques Wayland virtuels dans le compositeur isolé, les touches, la libération après expiration et la récupération du mouvement du pointeur.
- Une vraie application X11 via le `xwayland-satellite` local.
- Les deux surfaces Beamer utilisant son moteur original, et le chargement des adaptateurs dans le vrai Flatpak 1.5.19.

Les suites existantes Clawd (50 tests), Capri (23 tests), Beamer (47 tests), ainsi que les tests ciblés des curseurs, du zoom, du spotlight, des réglages et de l'API locale ont été exécutés. La validation KDL, le rechargement Hyprland et l'idempotence de l'installation complètent ces vérifications.

Une session principale Niri sur les deux écrans physiques, les gestes d'un trackpad physique et le passage Beamer entre deux ordinateurs restent à exercer en conditions réelles. Ces limites de validation ne sont pas remplacées par les tests isolés. Aucun basculement ni aucune fermeture de la session Hyprland de l'utilisateur n'a été effectué.
