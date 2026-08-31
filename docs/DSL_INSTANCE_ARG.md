# DSL `instance_arg:` — formalisation de la consommation d'identifiant d'instance

## Contexte et problème

Dans le DSL de plugins CLI, de nombreuses commandes d'instance (show, modify, delete, et leurs variantes) consomment un identifiant positionnel via `options.instance_identifier`. Cet appel peut optionnellement recevoir un bloc `%selector` qui résout un nom en identifiant via l'API.

Jusqu'ici ce pattern est géré de deux façons **ad hoc** :

1. **Méthodes `setup_<foo>_instance`** auto-générées ou écrites manuellement — consomment l'identifiant, l'injectent dans le `ctx` sous une clé nommée, puis transmettent aux enfants. Exemple :
   ```ruby
   define_method(:"setup_admin_#{res}_instance") do |**|
     {res_id: get_resource_id_from_args(aoc_res_path(res))}
   end
   ```

2. **Appels directs dans les handlers lambda** — l'identifiant est consommé en ligne dans le corps du handler. Exemple :
   ```ruby
   handler: lambda{ Result::SingleObject.new(api.read("res/#{options.instance_identifier}")) }
   ```

Ces deux formes sont invisibles dans l'arbre DSL : un `--help` ne mentionne pas qu'un identifiant est attendu, et la cohérence n'est pas vérifiable statiquement.

---

## Solution : attributs `instance_arg:` et `lookup:` sur `CommandSpec`

### Nouveaux attributs

| Attribut | Type | Rôle |
|---|---|---|
| `instance_arg:` | `Symbol \| nil` | Nom de la clé injectée dans le `ctx`. Déclenche la consommation d'un identifiant **avant** le `setup:` et avant la phase B (dispatch). |
| `lookup:` | `Symbol \| nil` | Nom d'une méthode d'instance `(field, value) → id` passée comme bloc `%selector`. Ignoré si `instance_arg:` est `nil`. |

### Comportement dans le dispatcher (`dispatch_from_registry`, Phase A)

```
Phase A.1 — si instance_arg: présent (et pas --help, pas skip_setup)
    → options.instance_identifier(description: instance_arg.to_s) [avec bloc lookup si lookup: présent]
    → ctx = ctx.merge(instance_arg => res_id)
Phase A.2 — si setup: présent
    → ctx = ctx.merge(send(setup, **ctx))
Phase B  — dispatch normal (enfants ou feuille)
```

L'ordre A.1 avant A.2 garantit que le `setup:` peut lire l'identifiant depuis le `ctx` si nécessaire.

### Exemples d'usage

**Nœud intermédiaire (remplace `setup_<foo>_instance`) :**
```ruby
# Avant
command(:show, description: '...', setup: :setup_admin_node_instance)
define_method(:setup_admin_node_instance) {|**| {res_id: get_resource_id_from_args('nodes')}}

# Après
command(:node, description: '...', instance_arg: :res_id)
# le handler reçoit res_id: dans son ctx
```

**Feuille one-liner (remplace le lambda inline) :**
```ruby
# Avant
command :show, handler: lambda{ Result::SingleObject.new(api.read("res/#{options.instance_identifier}")) }

# Après
command :show, instance_arg: :res_id,
  handler: ->(res_id:, **){ Result::SingleObject.new(api.read("res/#{res_id}")) }
```

**Avec `%selector` (lookup par nom) :**
```ruby
# Avant
def setup_admin_nodes_shared_folders(**)
  node_id = options.instance_identifier{ |f, v| @api_v5.lookup_entity_by_field(entity: 'nodes', field: f, value: v)['id'] }
  {sf_entity: "nodes/#{node_id}/shared_folders"}
end

# Après — instance_arg: consomme node_id, setup: construit sf_entity à partir du ctx
command(:nodes, description: '...', instance_arg: :node_id, lookup: :lookup_node_id, setup: :setup_nodes_shared_folders)
def lookup_node_id(f, v) = @api_v5.lookup_entity_by_field(entity: 'nodes', field: f, value: v)['id']
def setup_nodes_shared_folders(node_id:, **) = {sf_entity: "nodes/#{node_id}/shared_folders"}
```

---

## État d'avancement

### ✅ Étape 0 — Infrastructure (terminée)

Fichiers modifiés : [`command_spec.rb`](../lib/aspera/cli/command_spec.rb), [`base.rb`](../lib/aspera/cli/plugins/base.rb)

- [x] Ajout de `instance_arg:` et `lookup:` à `CommandSpec` (avec doc RDoc)
- [x] `dispatch_from_registry` : Phase A.1 consomme l'identifiant si `instance_arg:` présent, avant Phase A.2 (`setup:`)
- [x] `validate!` dans `CommandRegistry` : vérifier que `lookup:` n'est pas présent sans `instance_arg:`

---

### ✅ Étape 1 — `orchestrator.rb` (terminée)

**Pattern** : handlers lambdas one-liner où `options.instance_identifier` est inliné directement dans l'interpolation de chaîne, sans aucun bloc lookup.

**Commandes concernées** dans `workflows` et `workorders`/`workstep` :

| Chemin complet | Identifiant actuel | Clé cible |
|---|---|---|
| `workflows status` | `options.instance_identifier` | `wf_id:` |
| `workflows inputs` | `options.instance_identifier` (inline) | `wf_id:` |
| `workflows details` | `options.instance_identifier` (inline) | `wf_id:` |
| `workflows export` | `options.instance_identifier` (inline) | `wf_id:` |
| `workflows workorders` | `options.instance_identifier` (inline) | `wf_id:` |
| `workflows outputs` | `options.instance_identifier` (inline) | `wf_id:` |
| `workflows start` | `options.instance_identifier` dans handler | `wf_id:` |
| `workorders status` | `options.instance_identifier` (inline) | `wo_id:` |
| `workorders cancel` | `options.instance_identifier` (inline) | `wo_id:` |
| `workorders reset` | `options.instance_identifier` (inline) | `wo_id:` |
| `workorders output` | `options.instance_identifier` (inline) | `wo_id:` |
| `workstep status` | `options.instance_identifier` (inline) | `ws_id:` |
| `workstep cancel` | `options.instance_identifier` (inline) | `ws_id:` |

**Approche** : déclarer `instance_arg:` sur le nœud intermédiaire (`workflows`, `workorders`, `workstep`) — les handlers des feuilles reçoivent l'identifiant via `ctx`.

---

### ✅ Étape 2 — `ats.rb` (terminée)

**Pattern** : mélange de one-liners inline et de handlers nommés + un setup `setup_ak_node` qui consomme un identifiant.

**Commandes concernées** :

| Chemin complet | Pattern actuel | Clé cible |
|---|---|---|
| `access_key show` | inline dans lambda | `access_key_id:` |
| `access_key delete` | variable locale dans lambda | `access_key_id:` |
| `access_key modify` | variable locale dans handler nommé | `access_key_id:` |
| `access_key cluster` | variable locale dans handler nommé | `access_key_id:` |
| `access_key entitlement` | variable locale dans handler nommé | `access_key_id:` |
| `access_key node` (setup) | `setup_ak_node` consomme l'id | → remplacer par `instance_arg: :access_key_id` + setup résiduel |
| `api_key show` | inline dans lambda | `api_key_id:` |
| `api_key delete` | variable locale dans lambda | `api_key_id:` |

**Note** : `setup_ak_node` fait plus que consommer l'id (construit un `Node` plugin) — garder le `setup:` mais lui passer `access_key_id:` depuis le `ctx`.

---

### ✅ Étape 3 — `console.rb` (terminée)

**Pattern** : handlers nommés et lambdas dans `transfer current` et `transfer smart`, tous avec `instance_identifier(description: 'transfer ID')`.

**Commandes concernées** :

| Chemin complet | Pattern actuel | Clé cible |
|---|---|---|
| `transfer current show` | lambda inline | `transfer_id:` |
| `transfer current files` | handler nommé | `transfer_id:` |
| `transfer current start/pause/cancel/resume/rerun/change_rate/change_policy/move_forwards/move_back` | handlers générés (`define_method`) | `transfer_id:` |

**Approche** : `instance_arg: :transfer_id` sur le nœud `transfer current`.

---

### ✅ Étape 4 — `node.rb` (terminée)

**Pattern** : plusieurs groupes distincts, certains avec bloc lookup.

**Commandes concernées** :

| Chemin complet | Pattern actuel | Bloc lookup ? | Clé cible |
|---|---|---|---|
| `access_keys do permission show` | inline dans lambda | non | `perm_id:` |
| `access_keys do permission modify` | inline dans lambda | non | `perm_id:` |
| `watch_folder modify` | handler nommé | non | `res_id:` |
| `watch_folder delete` | handler nommé | non | `res_id:` |
| `async show` | handler nommé | `async_lookup` | `async_id:` |
| `async delete` | handler nommé | `async_lookup` | `async_id:` |
| `async bandwidth` | handler nommé | `async_lookup` | `async_id:` |
| `async files` | handler nommé | `async_lookup` | `async_id:` |
| `async counters` | handler nommé | `async_lookup` | `async_id:` |
| `ssync start` | handlers générés | `ssync_lookup` | `ssync_id:` |
| `ssync stop` | handlers générés | `ssync_lookup` | `ssync_id:` |
| `ssync bandwidth/counters/files/state/summary` | handlers générés | `ssync_lookup` | `ssync_id:` |

**Note** : les blocs lookup (`async_lookup`, `ssync_lookup`) sont déjà des méthodes d'instance → compatible avec `lookup: :async_lookup`.

---

### ✅ Étape 5 — `faspex5.rb` (terminée)

**Pattern** : handlers nommés + setups intermédiaires avec bloc lookup API.

**Commandes concernées** :

| Chemin complet | Pattern actuel | Bloc lookup ? | Clé cible |
|---|---|---|---|
| `invitations resend` | inline dans lambda | non | `invitation_id:` |
| `admin accounts reset_password` | handler nommé | `res_lookup_id` | `contact_id:` |
| `admin nodes browse` | handler nommé | API lookup | `node_id:` |
| `admin nodes shared_folders` (setup) | `setup_admin_nodes_shared_folders` | API lookup | `node_id:` → `sf_entity:` via setup résiduel |
| `admin nodes shared_folders user` (setup) | `setup_admin_nodes_shared_folders_user` | API lookup | `sf_id:` → `user_path:` via setup résiduel |
| `admin shared_inboxes` (setup) | `setup_admin_shared_inboxes_instance` | API lookup | `res_instance_path:` |
| `admin workgroups` (setup) | `setup_admin_workgroups_instance` | API lookup | `res_instance_path:` |
| `packages` (plusieurs handlers) | `options.instance_identifier` dans handler | non | `package_id:` |
| `shared_folders` (browse) | handler nommé | API lookup | `sf_id:` |

---

### ✅ Étape 6 — `aoc.rb` (terminée)

**Pattern** : `setup_admin_<res>_instance` auto-générés par `define_method` + handlers lambdas inline + setups spéciaux.

**Sous-étape 6a — `setup_admin_<res>_instance` auto-générés**

Le bloc suivant (ligne ~1277) génère une méthode de setup pour chaque ressource non-singleton :
```ruby
ADMIN_OBJECTS.reject{|r| ADMIN_OBJECT_CONFIG.dig(r, :singleton)}.each do |res|
  define_method(:"setup_admin_#{res}_instance") do |**|
    {res_id: get_resource_id_from_args(aoc_res_path(res))}
  end
end
```
Ces méthodes sont référencées depuis le DSL via `setup: :"setup_admin_#{res}_instance"`.

**Migration** : remplacer par `instance_arg: :res_id` sur chaque nœud de ressource dans la boucle DSL.  
`get_resource_id_from_args` encapsule `instance_identifier` + lookup par nom → à décomposer en `instance_arg:` + `lookup:` ciblé par ressource, ou garder via un `lookup: :lookup_aoc_res` générique.

**Sous-étape 6b — handlers inline divers**

| Chemin complet | Clé cible |
|---|---|
| `packages show` | `package_id:` |
| `packages delete` | `package_id:` |
| `packages modify` | `package_id:` |
| `packages receive` (partiel) | `package_id:` |
| `packages bearer_token_node/node_info/browse/find` (générés) | `package_id:` |
| `automation workflows launch` | `wf_id:` |
| `admin application instance <type> show` | `res_id:` |
| `admin application instance <type> modify` | `res_id:` |
| `admin application membership show` | `res_id:` |
| `admin application membership delete` | `res_id:` |
| `packages shared_inboxes show` | via `get_resource_path_from_args` |

**Sous-étape 6c — setups spéciaux avec logique supplémentaire**

Ces setups font *plus* que consommer un identifiant — ils restent des méthodes `setup:` mais reçoivent l'identifiant depuis le `ctx` :

| Setup actuel | Ce qui reste après migration |
|---|---|
| `setup_admin_workspace_dropbox` | `instance_arg: :res_id` sur `workspace`, setup résiduel trivial ou supprimé |
| `setup_admin_workspace_shared_folder` | `instance_arg: :res_id` sur `workspace`, setup résiduel pour charger les `shared_folders` |
| `setup_admin_workspace_shared_folder_instance` | `instance_arg: :sf_id` sur `shared_folder`, setup résiduel pour résoudre `sf_item` |
| `setup_packages_short_link` | `instance_arg:` sur `shared_inboxes` + setup résiduel |

---

## Règles invariantes

1. `instance_arg:` est consommé **avant** `setup:` (Phase A.1 < A.2) — le setup peut donc lire la clé injectée.
2. `lookup:` sans `instance_arg:` est invalide → `validate!` doit le détecter.
3. `instance_arg:` est compatible avec des nœuds intermédiaires **et** des feuilles.
4. `skip_setup: true` inhibe également `instance_arg:` (même sémantique que pour `setup:`).
5. `--help` inhibe `instance_arg:` (pas d'appel réseau pour résoudre un sélecteur).

---

## Fichiers impactés

| Fichier | Rôle |
|---|---|
| [`lib/aspera/cli/command_spec.rb`](../lib/aspera/cli/command_spec.rb) | Déclaration des attributs `instance_arg:` et `lookup:` |
| [`lib/aspera/cli/command_registry.rb`](../lib/aspera/cli/command_registry.rb) | `validate!` : vérifier `lookup:` sans `instance_arg:` |
| [`lib/aspera/cli/plugins/base.rb`](../lib/aspera/cli/plugins/base.rb) | `dispatch_from_registry` Phase A.1 |
| [`lib/aspera/cli/plugins/orchestrator.rb`](../lib/aspera/cli/plugins/orchestrator.rb) | Étape 1 |
| [`lib/aspera/cli/plugins/ats.rb`](../lib/aspera/cli/plugins/ats.rb) | Étape 2 |
| [`lib/aspera/cli/plugins/console.rb`](../lib/aspera/cli/plugins/console.rb) | Étape 3 |
| [`lib/aspera/cli/plugins/node.rb`](../lib/aspera/cli/plugins/node.rb) | Étape 4 |
| [`lib/aspera/cli/plugins/faspex5.rb`](../lib/aspera/cli/plugins/faspex5.rb) | Étape 5 |
| [`lib/aspera/cli/plugins/aoc.rb`](../lib/aspera/cli/plugins/aoc.rb) | Étape 6 |
| [`spec/`](../spec/) | Tests à mettre à jour / ajouter |
