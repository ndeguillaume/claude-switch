# Claude Switch

App menu bar macOS pour basculer le compte actif de Claude Code entre plusieurs profils.

## Authentification : rien à fournir

Aucun mot de passe, aucun token à générer. Le `/login` OAuth de Claude Code (via navigateur) écrit ses tokens dans le Keychain macOS ; Claude Switch ne fait que copier et restaurer cette entrée. « Generic password » est le nom du type d'item Keychain, pas un mot de passe à saisir.

## Comment ça marche

Claude Code stocke le compte actif à deux endroits :

- le Keychain macOS, entrée generic password `Claude Code-credentials` (les tokens OAuth)
- `~/.claude.json`, bloc `oauthAccount` (email, organisation)

Claude Switch garde une copie de chaque compte dans le Keychain sous `ClaudeSwitch.profile.<id>` (id stable par profil : renommer ne casse rien) et les métadonnées dans `~/Library/Application Support/ClaudeSwitch/profiles.json`. Basculer = restaurer la copie du profil cible dans `Claude Code-credentials` et remettre son bloc `oauthAccount` dans `~/.claude.json`. Les tokens ne quittent jamais le Keychain local.

Avant chaque bascule, l'app re-capture automatiquement le profil courant : le CLI claude rafraîchit ses tokens en arrière-plan, et un snapshot périmé rendrait le retour impossible.

## Build

```bash
./build.sh
```

Produit `dist/Claude Switch.app` (signé ad hoc). Lancer avec `open "dist/Claude Switch.app"`.

L'icône (`Resources/AppIcon.icns`) est générée par script : `swift Scripts/generate_icon.swift` la régénère (aperçu dans `Resources/preview.png`), et `build.sh` la recrée automatiquement si elle manque.

## Setup (par compte, une seule fois)

1. Lance `claude`, connecte-toi au compte voulu (`/login` si besoin), quitte claude.
2. Menu bar → **Ajouter un profil…**, donne-lui un nom, puis « Capturer maintenant ». macOS demande l'accès au Keychain : « Toujours autoriser ».
3. Dans `claude` : `/logout` puis `/login` avec le compte suivant, et recommence.

Ensuite, un clic sur un profil dans le menu bascule le compte. La coche indique le compte actif, l'email est affiché à côté de chaque profil capturé. Les sous-menus Renommer / Supprimer / Capturer gèrent les profils (supprimer un profil efface sa copie Keychain, pas le compte Claude).

## Usage de session

Sous chaque profil capturé, le menu affiche l'utilisation de la fenêtre de 5 h en cours et son heure de reset (« Session : 34 % · fin 18:00 »), via l'endpoint OAuth d'usage d'Anthropic, le même que la commande `/usage` du CLI. Rafraîchi à l'ouverture du menu, cache de 60 s. Le token de chaque profil ne quitte la machine que vers `api.anthropic.com`.

Pour le compte actif la valeur est toujours fiable (token rafraîchi par le CLI). Pour un profil inactif depuis longtemps, son token snapshot peut être expiré : le menu affiche alors « usage indisponible ». L'app ne rafraîchit jamais elle-même un token, pour ne pas désynchroniser le snapshot du CLI.

## Limites connues

- La bascule ne s'applique qu'aux nouveaux processus `claude`. Les sessions déjà lancées gardent leur compte (l'app affiche un avertissement si des sessions tournent : une session active peut réécrire ses tokens par-dessus le compte choisi).
- Le binaire est signé ad hoc : après un rebuild, macOS redemandera l'autorisation Keychain (la signature change).
- Si un token expire pendant qu'un profil est inactif trop longtemps et que le refresh échoue au retour, claude demandera un `/login` sur ce compte, puis re-capture le profil.

## Lancement au login

Menu bar → Paramètres… → cocher « Lancer l'app au démarrage » (via `SMAppService`, l'app apparaît dans Réglages Système → Général → Ouverture). L'enregistrement pointe sur l'emplacement actuel du bundle : si tu déplaces l'app, décoche puis recoche la case.

## Version

Le numéro de version vit dans le fichier `VERSION` à la racine (source unique). `build.sh` l'injecte dans `CFBundleShortVersionString`/`CFBundleVersion` de l'Info.plist, et l'app l'affiche dans Paramètres… (« Version 1.0.0 »). Pour publier une nouvelle version : édite `VERSION`, `./build.sh`.

## Langues

Interface localisée en français (défaut) et anglais, sélection automatique selon la langue du système. Les chaînes vivent dans `Sources/*/Resources/{fr,en}.lproj/Localizable.strings` ; ajouter une langue = ajouter un dossier `xx.lproj` dans les deux targets et lister la langue dans `CFBundleLocalizations` (build.sh).

## Tests

```bash
swift test
```

Le cœur (`ClaudeSwitchCore`) est testé avec un Keychain en mémoire et des fichiers de config temporaires. Aucun test ne touche le vrai Keychain ni le vrai `~/.claude.json`.
