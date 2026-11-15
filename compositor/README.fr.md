# Niri local pour les addons Serpantinum

Base officielle : https://github.com/niri-wm/niri/tree/73a04441fccc78294c3899af8f8cdd2a1e38fa33

`niri-serpantinum.patch` ajoute une API IPC versionnée, le zoom du rendu, les instantanés de géométrie et la capture d'entrée Beamer avec expiration. Il contient aussi les tests Rust de ces mécanismes. Le compositeur reste sous sa licence GPL-3.0-or-later ; le code amont et ses avis sont conservés lors de la reconstruction.

`./build-niri.sh` récupère la révision épinglée, applique le patch et installe le résultat dans `~/.local/opt/niri-serpantinum`. Il conserve les sources déjà modifiées au lieu de les réinitialiser. Les dépendances de compilation sont celles de Niri ; sur ce poste elles étaient déjà disponibles. `SERPANTINUM_NIRI_SOURCE`, `SERPANTINUM_NIRI_PREFIX` et `SERPANTINUM_NIRI_JOBS` permettent de choisir le cache, la destination et la concurrence.

Le lancement d'une session complète est décrit dans `../docs/NIRI.md`. L'installation du compositeur n'est pas nécessaire pour les utilisateurs qui restent sous Hyprland.

Pour répéter les tests natifs sur le poste de développement :

```sh
python3 tests/native/build.py /tmp/serpantinum-niri-input
SERPANTINUM_TEST_INPUT=/tmp/serpantinum-niri-input \
SERPANTINUM_TEST_X11=1 SERPANTINUM_TEST_SHELL=1 SERPANTINUM_TEST_CAPTURE=1 \
SERPANTINUM_TEST_PIXELS=1 SERPANTINUM_TEST_EFFECTS=1 \
python3 tests/niri_live.py ~/.local/opt/niri-serpantinum/bin/niri
```

Ces tests créent une fenêtre Niri temporaire dans la session courante, avec un répertoire runtime privé. Les événements de test sont injectés uniquement dans ce compositeur enfant. Le test des pixels nécessite une session Hyprland avec `grim`. Les tests Beamer nécessitent son Flatpak et les auxiliaires construits par l'installateur des addons. Aucun appairage ou envoi vers un autre ordinateur n'est lancé par ces tests.
