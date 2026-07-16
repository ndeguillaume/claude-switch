# Claude Switch

App menu bar macOS pour basculer le compte actif de Claude Code entre plusieurs profils.

## Authentification : rien à fournir

Aucun mot de passe, aucun token à générer. Le `/login` OAuth de Claude Code (via navigateur) écrit ses tokens dans le Keychain macOS ; Claude Switch ne fait que copier et restaurer cette entrée. « Generic password » est le nom du type d'item Keychain, pas un mot de passe à saisir.

## Comment ça marche

Claude Code stocke le compte actif à deux endroits :

- le Keychain macOS, entrée generic password `Claude Code-credentials` (les tokens OAuth)
- `~/.claude.json`, bloc `oauthAccount` (email, organisation)

Claude Switch garde une copie de chaque compte dans le Keychain sous `ClaudeSwitch.profile.<id>` (id stable par profil : renommer ne casse rien) et les métadonnées dans `~/Library/Application Support/ClaudeSwitch/profiles.json`. Basculer = restaurer la copie du profil cible dans `Claude Code-credentials` et remettre son bloc `oauthAccount` dans `~/.claude.json`. Les tokens ne quittent jamais le Keychain local.

Tous les accès Keychain passent par `/usr/bin/security` (le binaire système, même approche que [CCSwitcher](https://github.com/XueshiQiao/CCSwitcher)), pas par Security.framework. Le CLI `claude` utilise lui aussi `security` : les items créés portent une ACL qui fait confiance à ce binaire Apple, dont la signature ne change jamais. Résultat : aucune boîte de dialogue Keychain, même après un rebuild de l'app (la signature ad hoc de l'app n'entre plus en jeu). Chaque écriture recrée l'item (delete + add) pour repartir d'une ACL propre. Toutes les opérations épinglent le compte à l'utilisateur macOS courant (`-a $(whoami)`), exactement comme le fait `claude` en lisant `Claude Code-credentials` : écrire l'item live sous un autre compte le rendrait invisible pour claude, qui redemanderait un `/login`. Seul compromis : pendant l'écriture, le token apparaît brièvement dans les arguments du process `security` (visible via `ps` par un process local) ; `security(1)` n'offre pas d'alternative via stdin pour `add-generic-password`.

Avant chaque bascule, l'app re-capture automatiquement le profil courant : le CLI claude rafraîchit ses tokens en arrière-plan, et un snapshot périmé rendrait le retour impossible.

## Build

```bash
./build.sh
```

Produit `dist/Claude Switch.app` (signé ad hoc). Lancer avec `open "dist/Claude Switch.app"`.

L'icône (`Resources/AppIcon.icns`) est générée par script : `swift Scripts/generate_icon.swift` la régénère (aperçu dans `Resources/preview.png`), et `build.sh` la recrée automatiquement si elle manque.

## Setup (par compte, une seule fois)

1. Lance `claude`, connecte-toi au compte voulu (`/login` si besoin), quitte claude.
2. Menu bar → **Ajouter un profil…**, donne-lui un nom, puis « Capturer maintenant ».
3. Dans `claude` : `/logout` puis `/login` avec le compte suivant, et recommence.

Ensuite, un clic sur un profil dans le menu bascule le compte. La coche indique le compte actif, l'email est affiché à côté de chaque profil capturé. Les sous-menus Renommer / Supprimer / Capturer gèrent les profils (supprimer un profil efface sa copie Keychain, pas le compte Claude).

## Limites connues

- La bascule ne s'applique qu'aux nouveaux processus `claude`. Les sessions déjà lancées gardent leur compte (l'app affiche un avertissement si des sessions tournent : une session active peut réécrire ses tokens par-dessus le compte choisi).
- Les profils capturés avec une version antérieure (accès via Security.framework) portent une ACL liée à l'ancienne signature : macOS demandera le mot de passe une fois à la première lecture via `security`. Re-capturer chaque profil (ou répondre au prompt une fois) règle le cas définitivement.
- Si un token expire pendant qu'un profil est inactif trop longtemps et que le refresh échoue au retour, claude demandera un `/login` sur ce compte, puis re-capture le profil.
- Capturer pendant que claude n'a pas de session valide (juste après `/logout`, ou en plein refresh) écrirait un credential à `accessToken` vide, qui forcerait un `/login` à la bascule. L'app refuse désormais de capturer un token vide (erreur « pas de compte actif ») et de basculer sur un profil au token vide (invite à re-capturer), ce qui empêche d'empoisonner une copie de profil.

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
