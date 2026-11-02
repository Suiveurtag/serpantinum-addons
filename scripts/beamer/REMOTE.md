# Beamer avec Hyprland sur un deuxième ordinateur

Cette adaptation est expérimentale ; elle est prévue pour le Flatpak utilisateur Beamer **1.5.18** et ne modifie pas ses réglages ni son appairage. Installe aussi l'adaptation sur l'autre machine avant d'essayer le passage. Les deux postes doivent utiliser le lanceur **Beamer (Hyprland)**.

Dans un terminal de la session graphique Hyprland, depuis ce dossier :

```sh
python3 remote_install.py --check
python3 remote_install.py
```

Le premier contrôle indique les prérequis manquants et n'écrit rien ; le second crée le lanceur mais ne démarre pas Beamer. Il faut un Flatpak utilisateur Beamer 1.5.18, `python-evdev`, un accès lecture/écriture à `/dev/uinput`, `hyprctl`, `wl-paste`, `cc`, `pkg-config`, les outils et fichiers de développement Wayland ainsi que le protocole ext-data-control. Aucune permission système n'est modifiée par l'installateur. La configuration automatique exige Hyprland 0.57 ou plus récent avec sa configuration Lua standard ; si ce n'est pas le cas elle s'arrête sans l'écraser.

L'installateur ajoute à `~/.config/hypr/hyprland.lua` l'inclusion d'un fichier séparé et sauvegarde le fichier d'origine. Ce fichier désactive le flou du compositeur uniquement sur la fenêtre d'animation Beamer. L'installateur recharge la configuration et, si elle signale une erreur, restaure immédiatement l'original et ne garde rien.

Si une copie ou la création du lanceur échoue après la modification Hyprland, l'installateur annule les fichiers qu'il a créés s'ils n'ont pas changé depuis. Les fichiers modifiés entre-temps sont conservés et explicitement listés, ainsi que le chemin de la sauvegarde Hyprland ; ne les remplace pas automatiquement.

Pour les premiers essais, lance manuellement les deux instances avec `BEAMER_CAPTURE_TIMEOUT=30 python3 ~/.local/share/beamer-hyprland-compat/launcher.py` : cela libère automatiquement la capture après 30 secondes. Un test réel des deux sens et du presse-papiers reste nécessaire. Pour supprimer le lanceur et les auxiliaires sans toucher à Beamer ni aux fichiers modifiés : `python3 ~/.local/share/beamer-hyprland-compat/setup.py uninstall`. Le dossier contenant le code reste à supprimer manuellement après vérification.
