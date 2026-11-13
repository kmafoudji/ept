# Installer une instance de test avec des conteneurs

Ce guide installe ePT sur une machine de test avec Docker ou Podman. Tous les
emails partent dans une boîte de test (Mailpit), et l'application est
accessible en HTTP. **Ne l'utilisez pas en production.**

Testé avec ePT `7.7.0-1` sur Ubuntu 26.04, Podman 5.7 en mode utilisateur
(sans sudo), à côté d'une autre application conteneurisée.

## Avant de commencer

| Élément | Minimum |
| --- | --- |
| Processeurs | 2 |
| Mémoire | 3 Go, avec au moins 2 Go de swap |
| Disque | 20 Go libres |
| Outils | `git`, puis `docker compose` ou `podman-compose` |

Si la machine héberge déjà des conteneurs lancés avec `sudo podman`,
n'installez pas Docker à côté : ses règles de pare-feu peuvent couper le
réseau des conteneurs Podman. Utilisez `podman-compose` sans sudo.

## 1. Récupérer une version figée

```bash
git clone https://github.com/<compte>/ept.git && cd ept
git checkout v7.7.0-2      # la dernière version publiée (voir CHANGELOG.md)
```

## 2. Configurer

```bash
cp .env.example .env
```

Dans `.env`, modifiez au minimum :

```ini
APP_PORT=8090
APP_DOMAIN=http://<IP-de-la-machine>:8090/
DB_PASSWORD=<mot de passe long>
MYSQL_ROOT_PASSWORD=<le même>
EPT_MAIL_TRAP_DSN=smtp://mailpit:1025
EPT_INSECURE_HTTP=1
```

- `EPT_MAIL_TRAP_DSN` envoie **tous** les emails dans Mailpit.
- `EPT_INSECURE_HTTP=1` permet la connexion en `http://`. Sans cette ligne, le
  captcha est toujours refusé, car le cookie de session est réservé au HTTPS.

Avec Podman, indiquez le registre des images courtes :

```bash
mkdir -p ~/.config/containers
printf 'unqualified-search-registries = ["docker.io"]\n' > ~/.config/containers/registries.conf
```

Pour réduire la mémoire de MySQL sur une petite machine, créez
`docker-compose.override.yml` :

```yaml
services:
  ept-db:
    command: >
      --character-set-server=utf8mb4 --collation-server=utf8mb4_0900_ai_ci
      --sql-mode= --innodb-strict-mode=0 --max-connect-errors=10000
      --default-authentication-plugin=mysql_native_password
      --innodb-buffer-pool-size=256M --performance-schema=OFF
```

## 3. Construire et démarrer

```bash
podman-compose --profile mailtrap up --build -d     # ou : docker compose --profile mailtrap up --build -d
```

La première construction prend 15 à 30 minutes sur 2 processeurs.

Vérifiez :

```bash
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
podman logs --tail 30 ept_ept_1
```

Le journal de démarrage doit se terminer par `Apache ... resuming normal
operations`, sans « Halting further migrations ».

## 4. Créer l'administrateur

```bash
podman exec -it -u www-data ept_ept_1 php bin/seed-admin.php
```

## 5. Ouvrir les ports

Avec `ufw`, ouvrez les ports au seul réseau local :

```bash
sudo ufw allow from 192.168.1.0/24 to any port 8090 proto tcp comment 'ePT'
sudo ufw allow from 192.168.1.0/24 to any port 8025 proto tcp comment 'Mailpit'
```

| Quoi | Adresse |
| --- | --- |
| Administration | `http://<IP>:8090/admin` |
| Espace participant | `http://<IP>:8090/` |
| Emails envoyés (Mailpit) | `http://<IP>:8025` |

## 6. Vérifier que tout fonctionne

1. **Tâches planifiées** : `podman exec ept_ept_1 tail -5 /var/www/ept/logs/cron.log` ne doit contenir aucune erreur « not found ».
2. **Emails** : faites un « mot de passe oublié » côté participant. L'email doit arriver dans Mailpit en moins de 2 minutes.
3. **Horloge** : `date` sur la machine doit donner l'heure réelle. Les dates limites des envois en dépendent. Sur une machine virtuelle avec chrony, ajoutez `makestep 1 -1` dans `/etc/chrony/conf.d/` pour rattraper les retards après une mise en veille.

## Problèmes connus avec Podman sans sudo (Ubuntu 26.04)

| Symptôme | Cause | Contournement |
| --- | --- | --- |
| `podman-compose down` bloque, conteneur en « Stopping » | AppArmor refuse les signaux d'arrêt de Podman | `PID=$(podman inspect -f '{{.State.Pid}}' <conteneur>)` puis `podman unshare kill -9 $PID` (ou `sudo kill -9 $PID`), puis `podman rm -f --depend <conteneur>` |
| `ept-db` reste « unhealthy » et `ept` ne démarre pas | Contrôle de santé ancien, avant `7.7.0-1` | Mettre à jour, ou `podman start ept_ept_1` |
| Pages inaccessibles depuis le réseau | Pare-feu `ufw` | Étape 5 |

## Passer à une nouvelle version

Les données de la base sont conservées.

```bash
git fetch --tags
git checkout v7.7.0-2
podman-compose --profile mailtrap up --build -d
```

Le pied de page de l'application affiche la version en service. Si le
conteneur reste bloqué à l'arrêt, voir les problèmes connus ci-dessous.

## Réinitialiser la base de test

```bash
podman exec ept_ept-db_1 sh -c 'mysql -h127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE ept;"'
podman exec -i ept_ept-db_1 sh -c 'mysql -h127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD"' < sql/init.sql
podman exec -u www-data ept_ept_1 php bin/migrate.php -y
podman exec -u www-data ept_ept_1 php bin/run-once.php
podman exec -it -u www-data ept_ept_1 php bin/seed-admin.php
```

Depuis `7.7.0-1`, `init.sql` est complet : la migration se fait sans option
particulière. Sur une version antérieure, il fallait `migrate.php -y -v 7.3.1`.
