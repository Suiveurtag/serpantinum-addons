# Serpantinum — addons personnels v2

Addons pour l'interface native Serpantinum (Settings / Guide), indépendants de l'ancien installeur v1.

> **Avertissement :** projet personnel, susceptible d'être instable. Les mises à jour et la maintenance ne sont pas garanties. Une partie du code a été écrite en « vibe coding » : relisez les changements et testez-les dans votre propre installation avant de vous y fier.

Compatibilité vérifiée avec Serpantinum **2.3.0**.

## Sommaire

1. [Prérequis](#prérequis)
2. [Installation et désinstallation](#installation-et-désinstallation)
3. [Liste des fonctionnalités](#liste-des-fonctionnalités)
   1. [Réglages généraux](#1-réglages-généraux-addons--général)
   2. [Capri, compagne de bureau](#2-capri-compagne-de-bureau)
   3. [Clawd, mascotte Claude Code](#3-clawd-mascotte-claude-code)
   4. [Halloween, effets saisonniers](#4-halloween-effets-saisonniers)
   5. [AI Tokens, compteur de tokens](#5-ai-tokens-compteur-de-tokens)
   6. [Réseau et veille](#6-réseau-et-veille)
   7. [Écrans (Monitors)](#7-écrans-monitors)
   8. [Raccourcis clavier et disposition (Keybinds)](#8-raccourcis-clavier-et-disposition-keybinds)
   9. [Démarrage automatique (Startup)](#9-démarrage-automatique-startup)
   10. [Souris, curseurs et pavé tactile](#10-souris-curseurs-et-pavé-tactile)
   11. [Outils du bureau](#11-outils-du-bureau)
   12. [Thème et couleurs](#12-thème-et-couleurs)
   13. [Fonds Wallpaper Engine (scènes)](#13-fonds-wallpaper-engine-scènes)
   14. [Apparence : Liquid Glass et flou classique](#14-apparence--liquid-glass-et-flou-classique)
4. [Raccourcis clavier ajoutés](#raccourcis-clavier-ajoutés)
5. [Commandes IPC](#commandes-ipc)
6. [Tests et validation](#tests-et-validation)
7. [Outils de développement](#outils-de-développement)
8. [Documentation détaillée](#documentation-détaillée)

## Prérequis

| Élément | Usage |
| --- | --- |
| Serpantinum 2.3.0 installé | Shell modifié par l'installeur |
| Hyprland avec configuration Lua | Raccourcis, curseurs, pavé tactile, zoom, contour (le garde de clics demande Hyprland 0.55+) |
| NetworkManager, systemd-resolved, `jq`, `matugen` | DNS Mullvad et génération des couleurs |
| Python 3 avec Pillow | Installeur, couleurs, curseurs |
| Node.js | Hooks et chat de Capri et Clawd |
| `grim`, `wl-copy` | Sélecteur de couleur, capture figée |
| `udevadm` | Détection des pavés tactiles |
| systemd (session utilisateur) | Collecteur AI Tokens, service Wallpaper Engine |
| CLI Codex (`codex login`) | Chat Clawd et fournisseur ChatGPT de Capri (abonnement) |
| Ollama (facultatif) | Capri en local |
| Qt 6.12, CMake, EGL, GBM, epoxy, `we-layerd` | Fonds Wallpaper Engine (facultatif) |

## Installation et désinstallation

```sh
python3 install.py
serpantinum reload
```

- Les modifications du shell sont calculées d'abord, puis appliquées. Un ancrage inconnu arrête l'installation **sans rien modifier**.
- Chaque fichier modifié est sauvegardé (dates) dans `~/.local/share/serpantinum-addons-v2/backups/`.
- Une seconde installation ne modifie aucun fichier (idempotente).
- À réinstaller après chaque mise à jour de Serpantinum.

Désinstallation partielle, les autres addons restent en place :

```sh
python3 install.py --without-halloween   # effets saisonniers
python3 install.py --without-capri       # Capri
python3 install.py --without-clawd       # Clawd (retire aussi ses hooks Claude/Codex et la relance de statut)
python3 install.py --without-tokens      # widget AI Tokens et son service (la base reste)
serpantinum reload
```

Les valeurs de réglage restent dans la configuration, dormantes, et reviennent à la réinstallation.

---

## Liste des fonctionnalités

### 1. Réglages généraux (Addons → Général)

- **Contour de fenêtre thémé** : fin liseré Hyprland aux couleurs de la palette active, saisons comprises. Désactivé par défaut.
- **Masquer la localisation météo** : le nom de la ville du widget météo est brouillé en continu (caractères aléatoires), sans changer la donnée.
- **DNS Mullvad** : bascule DNS-over-TLS vers Mullvad sur la connexion active (voir [Réseau](#6-réseau-et-veille)).
- **Design d'horloge legacy** : restaure le calendrier et l'horloge v1.
- **Addons passifs** : liste des outils actifs sans interrupteur, avec leur raccourci (Capri, Clawd, dessin, zoom, sélecteur de couleur, capture, écrans, raccourcis, Vibrant/Vivid).
- **Halloween** : interrupteur des effets saisonniers (voir [Halloween](#4-halloween-effets-saisonniers)).
- **Capri** et **Clawd** : cartes avec interrupteur et options (voir plus bas).
- Les lignes sont trouvables dans la recherche des Settings (y compris les options repliées).

### 2. Capri, compagne de bureau

Petite compagne animée, installée sur le bureau, avec une carte illustrée dans Addons → Général.

**Activation et affichage**
- Interrupteur dans Settings ; `Super+Shift+K` bascule la même option.
- `Ctrl+Alt+C` la range dans sa biopuce (coin inférieur gauche) ou la fait ressortir.
- Désactivée : fenêtres, minuteurs, moteur et helper Node sont déchargés ; la carte reste une image fixe.
- Taille : petite (0,45), moyenne (0,6), grande (0,8), appliquée immédiatement.
- Sur un autre écran : déplacement, ou suivi du pointeur entre écrans.
- Errance, perchée sur les fenêtres et possession de fenêtres (interrupteur « wander / window effects »).
- Réactions indépendantes : jalousie des assistants et réactions système (« PC reactions »).
- Lieu de repos : coin ou barre des tâches.
- Animations : automatique (suit le mode performance du shell), complète, ou réduite.
- Langue : langue du shell, anglais, français, espagnol, portugais ou russe ; repli sur l'anglais.
- Assistant surveillé : Codex, Claude Code, Antigravity ou aucun (distinct du fournisseur de chat).
- Mode Ne pas déranger (DND) : elle n'émet plus de réaction spontanée, mais continue à tenir ses comptes de hooks.

**Hooks des agents (sur demande uniquement)**
- Connexion explicite à Claude Code, Codex et Antigravity, chacun avec « Connecter », « Déconnecter » et « Vérifier à nouveau ».
- N'ajoute que les commandes de Capri, sauvegarde le fichier avant de le modifier (`*.capri-backup-*`), respecte `CLAUDE_CONFIG_DIR`, `CODEX_HOME` et `AGY_CONFIG_DIR`.
- Rien n'est installé à l'ouverture des réglages, à l'activation de Capri ou à l'installation.
- Le pont écoute uniquement sur `127.0.0.1:47823` et rejette les requêtes venant d'un navigateur.

**Menu (clic droit)**
- Téléportation, satellite, démo, « Comment ça marche ? », parler, « Regarde mon écran », choix du modèle IA, « Rends-la tienne », signaler, rappels, ranger, taille, écran, son, errance/possession/jalousie/PC, « Regarde mon écran de temps en temps », lieu de repos, animations, surveillance, hooks, langue, quitter.
- « Comment ça marche ? » : elle pointe avec son bras vers « Où est Claude ? » (la fenêtre du dernier prompt), « Dossier de Claude » (ouvre `~/.claude`, `~/.codex` ou `~/.gemini/config` et sélectionne le fichier de hooks), « Où est mon icône ? » (pas d'icône de barre sur ce shell), « Branche-moi », parler, personnaliser.
- Accueil : premier passage ou hooks absents, elle propose de se brancher ; sinon « Capri en ligne ».

**Configuration du chat (« Configure-la avec elle »)**
- En local avec Ollama : démarrage de `ollama serve` si besoin, téléchargement d'un modèle avec barre de progression (gemma3:4b ou llama3.2, le plus gros d'abord si la machine le permet), modèles cloud d'Ollama si connecté.
- En ligne sans compte : Pollinations.
- Par clé API collée : masquée à la frappe, vérifiée, conservée dans l'état du helper (0600).
- « Gratuit avec Ollama » : ouvre un terminal (`$TERMINAL`, xdg-terminal-exec, kitty, foot…) qui lance `ollama launch claude|codex`, après ses hooks.
- Sans Ollama installé : elle ouvre la page de téléchargement.

**Fournisseurs**
- Ollama, LM Studio, llama.cpp / vLLM, Pollinations, OpenRouter, OpenAI, Groq, Gemini, DeepSeek, Mistral, serveur HTTP compatible, Claude Code, ChatGPT / Codex.
- Les services à clé demandent leurs propres identifiants. Un fournisseur en ligne reçoit la conversation ; le chat l'indique (« local » ou « en ligne »).
- ChatGPT / Codex : `codex login` puis choix de **ChatGPT** ; Capri vérifie la connexion, sans formulaire d'identifiants. Appels isolés (répertoire vide temporaire, sandbox lecture seule, configuration utilisateur ignorée, hooks, mémoires, plugins, outils d'exécution et navigateur désactivés).
- Enregistrement avec vérification ; l'ancienne configuration est restaurée en cas d'échec.

**Regarder l'écran**
- Menu « Regarde mon écran », ou « regarde mon écran » / « regarde mon écran » dans son chat.
- Première fois : elle demande où envoyer l'image (IA locale ou service en ligne).
- Capture avec `grim` sur son écran, 1280 px de large au maximum, JPEG gardé en mémoire pendant deux minutes au plus, jamais sur disque ; avec ChatGPT, transmis à `codex exec -i` depuis un répertoire temporaire supprimé ensuite.
- Option « de temps en temps » : toutes les 8 à 15 minutes quand vous êtes là et sur une autre fenêtre.
- Nécessite un modèle capable de voir (gemma3, ChatGPT, Gemini, OpenAI) ; sinon elle le signale et arrête.

**Chat et mémoire**
- Historique et faits mémorisés dans `~/.local/state/serpantinum/capri/{chat,memory}.json` (dossier 0700, fichiers 0600).
- « Oublier nos conversations » efface l'historique et la session Claude ; les faits restent modifiables séparément.
- « Rends-la tienne » : nom, persona, faits mémorisés et répliques personnalisées ; le menu propose aussi la version guidée.

**Sons**
- 18 signaux (téléportation, fini, alerte, erreur, bonjour, blips de voix, tic, étoile, atterrissage, envol, éclair, charge, possession, lancer, chute, rappel, jalousie) synthétisés en WAV par `scripts/build-capri-sounds.py`, lus avec QtMultimedia.
- Remplacement par vos fichiers (`done.mp3`, `alert.wav`, `.ogg`, `.m4a`…) dans `~/.config/serpantinum/capri/sounds/` ; ouverture du dossier depuis le menu Son.
- Muet depuis le menu (`addonsV2CapriMuted`).

**Limites connues** : une app plein écran peut recouvrir la compagne ou son éditeur ; quitter le plein écran ou choisir un autre écran la rend visible.

### 3. Clawd, mascotte Claude Code

Mascotte pixel de Claude Code, en aplat orange (`#D97757`), dessinée en bandes PNG à échelle entière sans lissage.

**Activation et réglages (carte « terminal » dans Addons → Général)**
- Activation (désactivée par défaut) ; échelle de 2× à 8× (4× par défaut) ; vitesse de marche (calme, normal, actif) ; délai avant sommeil de 1 à 60 minutes (5 par défaut) ; « Invoquer sur cet écran ».
- `Super+Shift+L` bascule Clawd.
- Désactivée : fenêtres, minuteurs et sockets sont déchargés ; seul le socket des hooks reste.

**Interactions**
- Glisser : il suit le pointeur, y compris entre écrans ; au relâchement il tombe sur ce qui est sous le point de chute (sommet d'une fenêtre ou sol de l'écran).
- Clic gauche : petite réaction ; réveille ; ouvre ou ferme le journal des sessions (après 250 ms, pour qu'un double-clic n'ouvre pas le journal).
- Double-clic : ouvre le chat.
- Clic milieu : caresse (petpet) avec une main pendant ~3 s, puis cœurs au clic suivant ; pendant un travail il sursaute puis reprend.
- Clic droit : menu ASCII — `> sleep` / `> wake`, `> revive`, `> dreams`, `> talk`, `> hide`, `> settings` ; Échap ou un clic extérieur le ferme.

**Vie autonome**
- Marche le long du bas de son écran (au-dessus de la barre), clignote, regarde le pointeur, s'assoit, s'endort après le délai configuré.
- Mode performance : pas d'exploration, pas de suivi, rafraîchissement des fenêtres réduit.

**Fenêtres et écrans** (interrupteur « world », `windows`)
- Se perche sur le sommet des fenêtres flottantes, les suit quand elles bougent, marche le long de leur bord visible, hésite en bout de course, saute ou revient.
- Quand la fenêtre disparaît, passe sur un autre espace de travail, est couverte, maximisée ou éloignée : il tombe et atterrit en `oops`.
- Un quart de ses marches explorent : sauter sur une fenêtre proche, observer depuis un bord de fenêtre (`peek`), ou marcher vers le curseur.
- Réactions aux fenêtres : une fenêtre s'ouvre sur son écran → il la regarde ; une fenêtre se ferme près de lui → `startled` ; le focus change → coup d'œil ; changement d'espace de travail → trébuche.
- Suit le curseur sur un autre écran (interrupteur « follow ») quand il est libre.

**Claude Code et Codex**
- Ligne `hooks` de la carte : `[ ] claude · [ ] codex · [ ] stats`. Rien n'est touché avant un clic.
- Installation depuis le terminal : `scripts/clawd/hooks.py <status|install|uninstall> <claude|codex|statusline>`.
- Chaque installation ajoute un groupe par événement à côté des existants, sauvegarde le fichier daté avant chaque modification, et ne retire que les commandes `clawd-hook.js`.
- Le hook envoie une ligne JSON locale (agent, événement, identifiant de session, outil, répertoire, PID de processus pour retrouver le terminal, cible de l'action, modèle), toujours avec sortie 0 en moins de 500 ms, et ne fait rien si le shell n'est pas lancé.
- Confidentialité : aucun prompt, aucune réponse et aucune entrée complète d'outil ne quitte le hook. La cible est un nom court (nom de fichier, nom du programme d'une commande, motif de recherche, hôte d'une URL, liste de tâches `x/y`). Motifs et requêtes restent en mémoire du shell, jamais sur disque.

**Ce qu'il affiche selon les événements**

| Événement | Clawd |
| --- | --- |
| Prompt soumis | `think`, puis sa boucle de travail ; nouveau verbe de spinner |
| Outil en échec | `oops` puis reprise |
| Demande de permission | `alert` + `⚠ permission · <dossier>` |
| Attente de réponse | `… waiting · <dossier>` pendant 8 s |
| Tour terminé | `happy` + `✓ done · <dossier>` ; `celebrate` (confettis) à partir de 3 min |
| Erreur de tour (API, limite) | `sad` + `✗ error · <dossier>` |
| Début de session | `wave` (sauf après une compaction) |
| Compaction | `compact` |
| Coût qui franchit un palier de 5 $ | `coin` |
| Limite 5 h ou 7 j à 100 % | scène (voir plus bas) |

**Boucles de travail selon l'outil**

| Outil | Boucle (variante `_2` alternée) |
| --- | --- |
| `Read`, `NotebookRead`, `view_image` | lecture (livre / parchemin) |
| `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `apply_patch` | écriture (crayon / feuille avec diff) |
| `Bash`, `exec_command`, `shell`… | terminal / sortie qui défile |
| `Grep`, `Glob`, `LS`, `ToolSearch` | loupe / balayage au sol |
| `WebFetch`, `WebSearch` | globe / antenne à ondes |
| `Task`, `Agent`, `spawn_agent` | mini-Clawd / deux mini-Clawd |
| `TodoWrite`, `update_plan` | liste de tâches / cases cochées |
| Autres (MCP…) | clavier / frappe rapide |

- Les événements d'un sous-agent ne remplacent pas l'outil du fil principal ; après 5 s de calme du fil principal, il joue l'outil du sous-agent.
- Vitesse de frappe selon l'effort : bas ×0,75, moyen ×1, haut ×1,25, très haut et max ×1,5.
- Contexte très chargé (≥ 80 %) ou limite 5 h ≥ 90 % : parfois une pause `sweat`.

**Couleurs d'effort** (interrupteur `colours`, recoloration par shader sur les seuls pixels du corps)

| Claude | Couleur | Codex | Couleur |
| --- | --- | --- | --- |
| low | jaune `#FFC107` | light | blanc |
| medium | vert `#4EBA65` | medium | menthe `#ACFFD8` |
| high | bleu pâle `#B1B9F9` | high | bleu OpenAI `#0093FF` |
| xhigh | violet `#AF87FF` + reflet blanc | extra high | rouge `#FF6363` |
| max | couleurs de Claude Code qui défilent | max | or, reflets, poussière dorée |
| ultracode | bleu ciel `#9BF6FF`, éclairs | ultra | nébuleuse et étoiles filantes |
| 2 sous-agents ou plus | « faux ultracode » en `#EB83FF` | | |

**Pensées (bulle au-dessus de la tête)**
- `✻ Pondering… 1m 05s` : glyphe qui tourne en orange, verbe pris dans les verbes de spinner de Claude Code installé (ou liste générique), temps écoulé depuis le prompt.
- Mode `full` : affiche aussi pendant 2,5 s l'action qui commence (`Edit main.py`, `Bash npm`), et toutes les 14 s, le modèle, l'effort, le contexte, le coût et les limites (couleurs d'alerte en pêche).
- Mode `verbs` (verbes et temps seulement) ou `off`.
- Compte des sous-agents en cours (`2 sous-agents · Haiku 5.5 · ctx 31%`) ; compteur `[n]` quand plusieurs sessions travaillent.

**Journal des sessions** (clic gauche sur Clawd)
- Liste des sessions Claude Code et Codex, les plus récentes d'abord, avec état (●/○), alerte/travail/terminé, dossier, rôle, outil, temps et contexte.
- Cliquer le cercle suit une session ou un sous-agent ; cliquer le reste de la ligne ramène le terminal au premier plan.
- Onglet `☾ dreams` : collection des rêves.

**Bulles** : permission > erreur > terminé/attente > notification/musique ; une bulle de rang inférieur ne remplace jamais une bulle supérieure. Un clic sur une bulle ramène le terminal de la session. Les terminaux derrière tmux ou screen ne sont pas retrouvés.

**Statistiques (ligne `stats`)**
- Fait lancer à la barre de statut de Claude Code le relais `clawd-status.js`, qui envoie modèle, effort, contexte (%, taille de fenêtre), coût, usage 5 h et 7 j.
- Si une barre de statut existait déjà, elle est enveloppée et continue de s'afficher ; la déconnexion la restaure à l'identique.

**Intégration avec le shell** (`ClawdEvents.qml`)
- Titre de la piste en cours (`♪ <titre>`, 28 caractères au maximum).
- Musique Spotify à plus de 90 % de volume : danse (`dance`, `vibe` avec casque, `twirl`, `wiggle`, `breakdance`) au rythme détecté dans les basses ; s'enregistre comme consommateur de Cava.
- Notifications : il marche sous les popups, lève la tête et lit ; les alertes critiques et les minuteurs déclenchent une alerte ; le mode Ne pas déranger n'autorise que les critiques.
- Batterie faible : fatigué ; très faible : réaction urgente ; en charge : applaudit.
- Luminosité ≤ 15 % : somnolent ; son coupé : chut ; lanceur, presse-papiers et menus : il lève la tête.
- Horloge pile à l'heure : saute vers un widget horloge et sonne ; pluie ou neige : humeur `rain` (parapluie) ou `snow` (frissons) ; minuteur actif : coup d'œil vers la barre.
- Il marche aussi sur les widgets du bureau, qui sont des plateformes comme les sommets de fenêtre.

**Chat** (`> talk`, double-clic)
- Terminal à côté de lui ; Entrée envoie, Échap ferme (l'historique reste), un clic extérieur ferme aussi.
- `[look]` ou `/look …` joint une capture de l'écran (JPEG 1280 px, à la demande, supprimée après usage). `[clear]` efface la conversation.
- Chaque message reçoit le contexte du shell (sessions actives, outil, cible nettoyée, quotas, heure, humeur), jamais de commandes ni de chemins.
- Réponses par Codex CLI (abonnement ChatGPT, effort faible), isolées (sandbox lecture seule, outils et navigateur désactivés, environnement filtré, répertoire temporaire supprimé). Historique : 60 messages gardés, 20 envoyés. Budget de 85 s, nouvel essai après 1,5 s si Codex est occupé.
- Il répond dans la langue de l'utilisateur ; l'interface reste en anglais.
- Préparation : `codex login` une fois ; la carte affiche `ChatGPT via Codex · signed in` ou `run codex login`.

**Sommeil et rêves**
- Il s'endort après le délai, en classique ou (une fois sur deux) sous une couverture (`sleep_blanket`).
- Pendant le sommeil, des événements peuvent survenir : se retourner, rêver (un nuage au-dessus de la tête, cliquable), parler en dormant (une phrase dans la bulle de pensée), somnambulisme au sol.
- Rêves : « Rainbow surf » (surf sur une vague de jetons arc-en-ciel) et « Gemini » (cauchemar, sursaut à la fin).
- La collection (`addonsV2ClawdDreams`) garde les 40 derniers rêves ; les rêves jamais faits apparaissent comme `? ???`.
- Réveil après 15 min ou plus : groggy (`wake_groggy`).

**Scènes de quota**
- Limite 5 h à 100 % : scène nucléaire (≈ 20 s) puis il meurt.
- Limite 7 j à 100 % : singularité (≈ 37 s, il meurt) ou surge (≈ 41 s, il survit et recharge la semaine), au hasard.
- Ne se déclenche pas à la première lecture (pas d'explosion pour un état déjà atteint) ; une seule fois par fenêtre.
- Recharge (`recharge`) à la fin de la fenêtre de 5 h ; reset de 7 j silencieux.
- Codex : `scripts/clawd/codex_limits.py` lit les journaux locaux toutes les 30 s ; `codex-resets.com` est interrogé toutes les 60 s (annonces, resets programmés, resets bancaires).
- Plusieurs sources proches (moins de 30 min) ne donnent qu'une seule scène.

**Mort et résurrection**
- Après une scène : grise, sur le dos, croix dans les yeux, fumée. Il ne réagit plus à rien ; ses bulles restent visibles.
- Revient par `> revive`, au démarrage d'une nouvelle session Claude Code ou Codex (sauf compaction), ou au démarrage du shell / à l'activation 3 h ou plus après sa mort. Résurrection d'environ 9 s avec halo de lumière.

**Animations** : 60 bandes plus 32 « actes » d'inactivité (livre, joie, vélo, portage, balai, aviron, pêche, feu de camp, jumelles, photo, sieste), joués rarement au sol, jamais deux fois de suite.

**IPC**
- `clawd toggle`, `appear`, `hide`, `play <nom>` (animations, scènes, rêves), `state` (JSON de débogage).

### 4. Halloween, effets saisonniers

Couche optionnelle, sans changement de fond. Deux interrupteurs indépendants : **Addons → Effets Halloween** (mouvement) et **Thème → Saisonnier · Halloween** (palette « Halloween Night » avec l'illustration de lune).

**Palette et surfaces**
- Surfaces fumées (`#171216`, bordeaux brûlé `#2b2026`), lumières chaudes (braise `#cd7745`, ivoire de bougie `#e9b77c`), lumières froides (clair de lune `#acb3cb`).
- Le thème reste en place quand les effets sont coupés ; la palette normale n'est jamais écrasée.

**Réglages et panneaux**
- Brume directionnelle sur chaque ligne de Settings, sous les contrôles.
- Âtre lumineux en bas des panneaux importants, toiles d'araignée réactives dans le coin de Settings.
- Cadran céleste gravé avec trois points distants et chauves-souris perchées sur l'horloge.
- Les grandes actions (lecture/pause…) ont des silhouettes de chauves-souris (sortie de 1,75 s) ; au survol soutenu, une nouvelle fuite toutes les 4,2 s avec anti-rebond de 1,6 s.
- Halo pulsant sur les boutons contrôles ; énergie sur les actions système ; maintien : énergie de confirmation.

**Musique**
- Couronne de pochette réactive aux basses.
- Reflet de verre sur la pochette à chaque changement de piste.
- Le bouton Lecture/Pause gagne un contour électrique, puis un fleuron élargi.

**Système, réseau, widgets**
- Courants conducteurs autour des profils d'alimentation ; vapeur d'énergie sur les contrôles chargés.
- Réseau : conduits vectoriels réels entre cœur et cartes ; paquets qui voyagent ; Wi-Fi en ondes chaudes, Bluetooth en mouvement froid, Ethernet droit.
- Widgets : halo d'horloge, filaments de jauges, brume météo, ruban musical, reflets mobiles.

**Lanceur, OSD, verrouillage, son**
- Lanceur : chauves-souris et éclairs ramifiés à l'ouverture et à chaque changement de résultats (limite de 380 ms).
- Volume/luminosité : âmes en forme de gouttes (huit pools), mist directionnel dans les lignes, vapeur sonore.
- Verrouillage : voile ajusté à l'authentification et à l'échec ; lumière de focus sur le champ de mot de passe.

**Ouvertures directionnelles et arrière-plan**
- Chaque panneau (Settings, horloge, musique, réseau, son, système, fonds, notifications, lanceur) s'ouvre avec des chauves-souris qui partent du bon bord. Les chauves-souris ont des trajectoires de 2,05 s.
- Des silhouettes traversent le fond de temps en temps (toutes les 3,2 à 8 s), quand leur surface est visible.

**Barre et notifications**
- Chaque module vertical ou horizontal reçoit une braise ; les modules sélectionnés ont une petite chauve-souris pendue. Pas de changement de largeur ni de clics.
- Cartes de notification : deux bougies et une sous-lumière chaude ; les actions et l'expiration restent natives.

**Intro**
- Au démarrage ou à l'activation : intro de 3,9 s (lune éclipsée, éclairs, vol d'oiseaux plus large, vapeur, deux flammes). Annulée à l'arrêt ou en mode performance.

**Mode performance et arrêt**
- Performance : atmosphère immobile, pas de mouvement ambiant ni de rafale.
- Désactivé : tous les effets, boucles et horloges sont déchargés ; le thème sélectionné reste.
- Interrupteur lune : nouvelle lune = désactivé, pleine lune braise = activé, avec clavier et accessibilité.

**Documentation détaillée** : [`docs/halloween.md`](docs/halloween.md).

### 5. AI Tokens, compteur de tokens

Widget natif (type `tokens`, « AI Tokens ») et module de barre.

**Affichage**
- Widget : grand total de tokens (compteur à rouleaux), totaux Codex et Claude, indicateur en direct et état de chaque source. Ajouté depuis l'éditeur de widgets.
- Module de barre : Settings → Barre → Modules → « AI Tokens », à glisser dans une zone. Barre horizontale : total en rouleaux, survol pour voir la répartition Codex / Claude. Barre verticale : total compact (`5.55B`).
- Indicateur en direct : s'allume 8 s après chaque événement de tokens.

**Calcul**
- **Codex** : base = total de vie du compte (`codex app-server` → `account/usage/read`, avec la connexion Codex existante) ; ajout des journaux locaux `~/.codex/sessions` par variation de `total_token_usage` ; les rejeux et les sous-agents dupliqués ne sont comptés qu'une fois.
- **Claude Code** : `~/.claude/projects` (sous-agents compris), dédupliqué par `message.id` + `requestId` ; tokens = entrée + sortie + création de cache + lecture de cache. `stats-cache.json` est volontairement ignoré.
- Si le compte est injoignable : dernière valeur connue conservée, le total ne baisse jamais ; sans aucune base, `0` marqué « no account total » et total marqué partiel.
- L'historique Claude antérieur aux transcriptions conservées par Claude Code n'est pas récupérable ; la carte indique `local since <date>`.

**Collecteur**
- `scripts/tokens/collector.py` (bibliothèque standard seulement), service utilisateur `serpantinum-tokens.service`, installé et activé par `install.py`.
- Base SQLite en mode WAL dans `~/.local/state/serpantinum/tokens/` (dossier 0700) ; `state.json` (0600) lu par le widget.
- Coûts : balayage toutes les 3 s, synchronisation du compte toutes les 10 min (recul jusqu'à 1 h en cas d'échec). Limites systemd : 300 Mo, priorité réduite.
- Base corrompue : renommée `tokens.db.corrupt-<heure>` puis reconstruite à partir des journaux et du compte.
- `state.json` vieux de plus de 150 s : le widget affiche `collector stopped`.
- Commandes : `collector.py status`, `collector.py once`, `systemctl --user status serpantinum-tokens`.

### 6. Réseau et veille

**DNS Mullvad** (Addons → Général et panneau Réseau)
- Bascule DNS-over-TLS vers Mullvad sur la connexion Wi-Fi ou Ethernet active ; le panneau réseau affiche la connexion et son mode.
- Modes détectés : `mullvad`, `home` (DHCP automatique) ou `custom`.
- Vérifie que la résolution fonctionne ; sinon restaure l'ancienne configuration et signale l'erreur.
- Script : `scripts/dns.sh status|toggle|set home|mullvad` (verrou pour éviter les exécutions concurrentes).

**Veille « Codex mode »** (Settings → Inactivité)
- Option supplémentaire : quand « Ne pas déranger » (Keep Awake) est actif, bloque aussi la mise en veille du système et la fermeture du capot.
- Désactivée par défaut ; visible et utilisable seulement sur ordinateur portable (détection UPower).
- Garde la session et le réseau vivants pendant les longues tâches, téléchargements et flux IA.

### 7. Écrans (Monitors)

- Plan des écrans : glisser-déposer, accrochage sur les bords des autres écrans (les écrans ne se chevauchent pas), liste des écrans, sélecteur d'écran.
- Cartes de résolution avec nom usuel (4K UHD, WUXGA, UWQHD, DCI 4K…), triées du plus grand au plus petit ; choisir une résolution choisit automatiquement le taux de rafraîchissement le plus proche.
- Curseur de taux de rafraîchissement, avec les valeurs disponibles.
- Rotation : cadran à 8 positions (0°, 90°, 180°, 270° et leurs versions retournées).
- Position X/Y numérique en pixels logiques.
- Prévisualisation d'un seul écran ; animation des changements.
- « Appliquer » écrit `~/.config/hypr/config/monitors.lua`, recharge Hyprland et restaure le fichier précédent en cas d'erreur. Si les écrans branchés ont changé, il refuse et demande de recharger.

### 8. Raccourcis clavier et disposition (Keybinds)

**Éditeur de raccourcis**
- Liste des liaisons `hl.bind` de `keybinds.lua`, recherche dans les raccourcis et commandes.
- Modification au clic : enregistrement d'une combinaison (appuyer sur les touches, Échap pour valider), type (`bind`), action (`exec` ou autre), commande, bouton d'édition coulissant.
- Ajouter, supprimer, sauvegarder ; refuse les doublons et les commandes vides.
- Les actions Lua, les options et les boucles d'espaces de travail générées sont conservées telles quelles.
- Les modifications extérieures à l'éditeur sont détectées : il faut recharger avant d'enregistrer.
- Espaces de travail : boutons `SUPER + 1` à `SUPER + 0`.

**Disposition clavier** (sélecteur en haut de l'onglet)
- Plusieurs dispositions XKB installées, dans l'ordre choisi ; recherche par langue ou code XKB.
- `Alt+Shift` change de disposition (option `grp:alt_shift_toggle`, activée seulement si plusieurs dispositions sont choisies).
- Retirer une disposition (au moins une doit rester), application immédiate et persistance dans `settings.lua`, en conservant les autres options XKB.
- Rollback si Hyprland signale une erreur.

### 9. Démarrage automatique (Startup)

- Onglet à côté de Keybinds, aussi accessible dans le panneau intégré `Super+Shift+P`.
- Liste de commandes lancées une seule fois au démarrage de la session (`discord`, par exemple).
- Ajouter, modifier, supprimer, rechercher ; même éditeur que Keybinds.
- Persistance dans `~/.config/hypr/config/serpantinum_startup.json`, génération de `serpantinum_startup.lua` (`hl.on("hyprland.start", …)`). Une erreur de configuration restaure les fichiers précédents.

### 10. Souris, curseurs et pavé tactile

Onglet **Addons → Souris** (sous-onglet « Mouse »).

**Thèmes de curseurs**
- Thèmes Xcursor installés, avec tailles de 16 à 128 px.
- Import d'archives de thème (zip, tar.gz) ; le thème importé est conservé localement.
- 31 rôles de pointeur personnalisables : flèche, aide, progression, attente, main, texte, texte vertical, croix, cellule, déplacement, saisie, interdit, copie, alias, redimensionnements (est-ouest, nord-sud, diagonales, bords et coins), zoom avant et arrière, menu contextuel, crayon.
- Formats : PNG, GIF et WebP animés, `.cur` et `.ani` de Windows, Xcursor ; point de clic réglable visuellement.
- Prévisualisation animée de chaque rôle.
- « Normal select » : même curseur pour tous les rôles, sans perdre les personnalisations.
- Réinitialisation d'un rôle, abandon des modifications en attente, export d'une archive réutilisable dans `~/Downloads` (`.tar.gz`).
- Application immédiate pour un thème complet ou la restauration des icônes par défaut ; les autres modifications passent par « Appliquer ».
- Chaque schéma reçoit un nom de thème unique, pour que les applications rechargent les curseurs modifiés.
- Synchronisation : Hyprland (`env.lua`, `hyprctl setcursor`), GTK 2/3/4, Qt/KDE (`kcminputrc`), XWayland (`Xresources`), xsettingsd, D-Bus et systemd, gsettings, Flatpak. Les applications qui dessinent leur propre pointeur gardent le leur.
- Rollback complet en cas d'erreur de configuration Hyprland.
- Redémarrer les applications qui gardent les curseurs en cache.

**Mouse acceleration** (Addons → Souris)
- Bascule l'accélération adaptative (`adaptive`) ou plate (`flat`) de Hyprland, pour les souris uniquement.
- Persistance dans `serpantinum_mouse_acceleration.lua`, appliquée au rechargement de Hyprland.

**Mouse spotlight** (`Super+Shift+M`)
- Halo circulaire animé autour du pointeur, qui converge à l'entrée et s'efface à la sortie ; le reste de chaque écran s'assombrit.
- Clic ou Échap ferme ; le clic de fermeture est consommé.
- Molette : redimensionne le cercle (sauvegardé).
- Réglages : rayon (35 à 350 px, 95 par défaut) et luminosité du fond (0 à 100 %, 35 % par défaut, courbe de Bézier cubique).
- Le suivi du pointeur ne tourne que pendant l'affichage et nécessite une session Hyprland active.
- Raccourci modifiable depuis le bouton « Raccourci » (ouvre Keybinds, recherche `addonMouseSpotlight`).

**Pavé tactile** (Addons → Souris)
- Vitesse du pointeur (curseur de -1 à 1, pas de 0,05).
- « Désactiver le pavé pendant la frappe » : protection native de libinput contre les mouvements et les tapes accidentels.
- « Désactiver les clics pendant la frappe » : garde Lua qui ignore les clics gauche, droit et milieu pendant la frappe et 600 ms après le dernier relâchement ; le mouvement reste possible ; Ctrl, Alt et Super ne sont pas concernés. Le texte n'est ni enregistré ni envoyé.
- Seuls les pavés reconnus par udev sont configurés ; souris et TrackPoints ne sont pas touchés.
- Persistance dans `serpantinum_trackpad.lua` ; sauvegarde et rollback en cas d'erreur.

### 11. Outils du bureau

**Dessin à l'écran** (`Super+Shift+D`)
- Calque d'annotation sur l'écran actif, avec barre d'outils en bas (`P` crayon libre, `C` ellipse, `R` rectangle, `E` gomme par trait).
- Bouton gauche : dessiner ; bouton droit glissé : effacer les traits ; molette : épaisseur du trait.
- `Ctrl+Z` annule, `Ctrl+Maj+Z` rétablit, `Suppr` efface tout, `Échap` ou le raccourci ferme et abandonne la session.
- Listé dans les addons passifs ; raccourci modifiable (`addonDesktopDraw` dans Keybinds).

**Zoom du bureau** (`Super+Shift+Z`)
- Agrandissement en direct autour du pointeur (de 1× à 6×) ; la molette fait glisser le zoom sans faire défiler l'application dessous.
- Les clics passent à travers le zoom.
- `Échap` ou le raccourci restaure le zoom précédent ; le dernier niveau choisi est mémorisé.
- Les réglages de curseur de session sont restaurés à la fermeture ou au rechargement du shell.
- Nécessite Hyprland avec configuration Lua. Raccourci modifiable (`addonDesktopZoom`).

**Sélecteur de couleur** (`Super+Shift+C` ou la pipette des actions rapides)
- Fige l'écran actuel, animation de contour aux couleurs du thème et aperçu HEX compact.
- Un clic déploie les boutons de copie HEX, RGB et HSL ; une animation de confirmation ferme le sélecteur après la copie.
- Échap ferme ; Entrée choisit la couleur et copie le HEX.
- Nécessite `grim` et `wl-copy`.

**Capture figée**
- Capture de l'écran figée (`Super+Shift+S`), recadrée à partir de l'image figée (`crop_frozen_screenshot.py`), avec suppression des fichiers temporaires à la fin.

**Fenêtres et écrans**
- `Super+Tab` : écran suivant, et pointeur au centre de cet écran (`mouse-next-monitor-center.sh`).
- `Alt+Tab` : fenêtre suivante sur l'écran et l'espace de travail courants, mise au premier plan.

### 12. Thème et couleurs

- **Vibrant** : couleurs d'accent réelles prélevées sur le fond d'écran.
- **Vivid** : garde la teinte de Vibrant et augmente saturation et luminosité.
- Les surfaces et le texte gardent la palette du shell pour la lisibilité ; les modèles Matugen synthétiques mettent aussi à jour les couleurs des applications.
- Les tuiles Vibrant et Vivid utilisent les mêmes tuiles, sélection et animations que les thèmes du shell.
- **Éditeur des accents** (Thème, en mode Vibrant ou Vivid) : glisser un point sur le fond d'écran pour choisir d'où est prélevée chaque couleur ; double-clic (ou clic droit sur la pastille) pour la restaurer.
- Choix sauvegardés par fond d'écran dans `~/.local/state/serpantinum/addons_v2_palette_overrides.json`.
- Un fond vidéo sert son image de départ pour Matugen.
- Le mode Matugen suit le générateur natif.

### 13. Fonds Wallpaper Engine (scènes)

Intégration optionnelle décrite en détail dans [`WALLPAPER_ENGINE.md`](WALLPAPER_ENGINE.md).

- Affichage des scènes Wallpaper Engine sur chaque écran via le démon local `we-layerd` et l'application `we-gui` (scènes uniquement, avec les 16 scènes fournies).
- Sélection d'un fond dans le shell libère seulement l'écran concerné ; `output-clear` exclut un écran des fonds globaux.
- Pauses : manuelle, plein écran, maximisation, verrouillage et alimentation de l'écran se combinent ; une reprise automatique garde la pause manuelle.
- Capture audio arrêtée quand aucun fond n'est configuré ou en pause/verrouillage.
- Canal GPU : tampon DMA-BUF partagé avec Qt (pool de trois tampons GBM) ; le verre flou échantillonne la scène en direct.
- Le dernier cadre présenté sert un panneau ouvert pendant une pause.
- Installation : `python3 scripts/install-wallpaper-engine.py --engine <dépôt we-layerd>` ; sauvegardes datées, remplacement atomique, aucun paquet système modifié.
- Service `we-layerd.service`, restauration des affectations au démarrage.
- Contrôle : `we-layerd ctl status|pause|resume`, `we-layerd output-clear <écran>`.
- Hors périmètre actuel : compatibilité universelle avec les scènes du Workshop, marionnettes avancées (morphing), débranchement physique, parité Windows.

### 14. Apparence : Liquid Glass et flou classique

- **Flou classique** : les surfaces des addons suivent le flou et l'opacité natifs, avec un liseré doux au survol et des pulsations sur l'horloge et les copies. Le sélecteur de couleur ne floute que la zone capturée.
- **Liquid Glass** : horloge/calendrier, sélecteur de couleur, barre de dessin, contrôles d'écran, éditeur de raccourcis, réglages de curseur et effets saisonniers suivent le matériau verre natif. Le survol affiche le bord, l'horloge a une lentille teintée par l'heure, et copier une couleur envoie une pulsation.
- Désactiver le flou natif rétablit les remplissages opaques.
- Les couleurs échantillonnées, les curseurs et l'encre du dessin restent exacts.
- **Contour de fenêtre** : voir [Réglages généraux](#1-réglages-généraux-addons--général).

---

## Raccourcis clavier ajoutés

| Raccourci | Action |
| --- | --- |
| `Super+Shift+K` | Afficher / masquer Capri |
| `Ctrl+Alt+C` | Ranger / ressortir Capri (biopuce) |
| `Super+Shift+L` | Afficher / masquer Clawd |
| `Super+Shift+D` | Dessin à l'écran |
| `Super+Shift+Z` | Zoom du bureau |
| `Super+Shift+M` | Mouse spotlight |
| `Super+Shift+C` | Sélecteur de couleur |
| `Super+Shift+S` | Capture d'écran (figée, version corrigée) |
| `Super+Tab` | Écran suivant, pointeur au centre |
| `Alt+Tab` | Fenêtre suivante sur l'écran courant |
| `Alt+Shift` | Disposition clavier suivante (si plusieurs) |
| Molette (zoom ouvert) | Ajuster le zoom |

Tous les raccourcis sont modifiables dans **Keybinds** (rechercher le nom de l'addon, par exemple `capri`, `clawd`, `addonDesktopZoom`). Les modifications de l'utilisateur sont conservées à la réinstallation.

## Commandes IPC

Toutes passent par le shell :

```sh
SHELL_QML=~/.local/share/serpantinum/src/quickshell/Shell.qml
quickshell -p "$SHELL_QML" ipc call capri toggle
quickshell -p "$SHELL_QML" ipc call clawd toggle
quickshell -p "$SHELL_QML" ipc call clawd appear     # « show » est lu par la CLI comme « ipc show »
quickshell -p "$SHELL_QML" ipc call clawd hide
quickshell -p "$SHELL_QML" ipc call clawd play walk  # ok / unknown / off
quickshell -p "$SHELL_QML" ipc call clawd state      # JSON de débogage
quickshell -p "$SHELL_QML" ipc call addonColorPicker toggle
quickshell -p "$SHELL_QML" ipc call addonDesktopDraw toggle
quickshell -p "$SHELL_QML" ipc call addonDesktopZoom toggle
quickshell -p "$SHELL_QML" ipc call addonDesktopZoom zoomIn
quickshell -p "$SHELL_QML" ipc call addonDesktopZoom zoomOut
quickshell -p "$SHELL_QML" ipc call addonMouseSpotlight toggle
```

## Tests et validation

```sh
python3 -m unittest discover -s tests -v                 # une fois Serpantinum installé
python3 -m unittest discover -s tests -p test_tokens.py -v
python3 scripts/clawd/sprites.py --check                  # sprites Clawd à jour
```

- Les tests couvrent l'intégration du thème natif, l'ordre et l'idempotence des onglets, la préservation des actions Lua, les conflits de modification externe, Capri (réglages, chat, hooks, guide, configuration IA), Clawd (états, chat, rêves, couleurs d'effort), les effets saisonniers (cycle de vie Qt), les curseurs, le zoom, la loupe, le pavé tactile, le contour, l'installation et la désinstallation.
- Les validations en session réelle (captures, interactions, journaux) sont décrites dans les documents détaillés.

## Outils de développement

| Script | Rôle |
| --- | --- |
| `scripts/build-capri-assets.py` | Génère les ressources de Capri |
| `scripts/build-capri-sounds.py` | Synthétise les sons de Capri en WAV |
| `scripts/build-seasonal-shaders.py` | Recompile les shaders Halloween (`.qsb`) |
| `scripts/clawd/sprites.py` | Génère les sprites de Clawd depuis les images ASCII (`--check` vérifie) |
| `scripts/clawd/shaders.py` | Recompile les shaders de Clawd |
| `scripts/clawd/codex_limits.py` | Lit les limites Codex dans les journaux locaux |
| `scripts/clawd/verbs.py` | Lit les verbes de spinner de Claude Code installé |
| `scripts/clawd/hooks.py` | Installe / désinstalle les hooks et le relais de statut |
| `scripts/colors.py` | Extrait les couleurs du fond d'écran (Vibrant / Vivid) |
| `scripts/control.py` | Backend des raccourcis, écrans et disposition clavier |
| `scripts/startup.py` | Backend du démarrage automatique |
| `scripts/trackpad.py`, `scripts/mouse_acceleration.py` | Backends du pavé et de l'accélération |
| `scripts/custom_cursor.py`, `scripts/cursor_images.py` | Thèmes de curseurs et conversion d'images |
| `scripts/desktop_zoom.py`, `scripts/mouse_spotlight.py`, `scripts/window_outline.py` | Zoom, spotlight, contour |
| `scripts/crop_frozen_screenshot.py`, `scripts/tokens/collector.py` | Capture figée, collecteur de tokens |
| `scripts/dns.sh` | Bascule DNS Mullvad |
| `native/wallpaper-bridge/` | Pont GPU C++ pour Wallpaper Engine (tests `ctest`) |

## Documentation détaillée

- [`docs/capri.md`](docs/capri.md) — Capri : contrôles, hooks, fournisseurs, validation
- [`docs/clawd.md`](docs/clawd.md) — Clawd : contrôles, sprites, scènes, validation
- [`docs/halloween.md`](docs/halloween.md) — Effets Halloween : conception et validation
- [`docs/tokens.md`](docs/tokens.md) — AI Tokens : sources, calcul, récupération
- [`WALLPAPER_ENGINE.md`](WALLPAPER_ENGINE.md) — Scènes Wallpaper Engine : installation, contrôle, canal GPU
