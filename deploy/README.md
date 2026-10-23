# Deploy: one domain, all in Docker, on the CloudPanel VPS

Everything runs at **https://twv.prowavetech.in**. There is no separate API site.

```
phone / browser ──https──▶ CloudPanel (SSL, reverse proxy site twv.prowavetech.in)
                              │  http://127.0.0.1:8080
                              ▼
                     docker "web" (nginx, deploy/nginx.conf)
                       ├─ /api, /ws, /media, /static, /django-admin, /health ──▶ docker "api" (Django)
                       └─ everything else ──▶ the Flutter web app (index.html)
                     docker: api · worker · beat · db (Postgres) · redis
```

The app is built with `--dart-define=API_URL=https://twv.prowavetech.in`: web and phone talk to the same address.

**App folder on the server: `~/twv`** of the SSH user (`VPS_USER`). We deploy as **root** (same as probid_v2), so it
is **`/root/twv`**. The folder name is set in the workflow (`APP_DIR: twv`), not a secret. The first deploy makes it
and its folders by itself; you only make `backend/.env` (step 6) and, for push, `secrets/` gets the Firebase file.
The frontend (Flutter web build) goes to `~/twv/web/`; nothing goes in the CloudPanel site's `htdocs`.

```
/root/twv/
├─ docker-compose.prod.yml      ← uploaded by every deploy
├─ web/  backend/  deploy/      ← uploaded by every deploy
├─ backend/.env                 ← YOU make it once (never uploaded, never deleted)
└─ secrets/                     ← YOU put firebase-service-account.json here (never uploaded, never deleted)
```

Every push to the **`develop`** branch runs `.github/workflows/deploy-develop.yml`:
1. **test**: backend `pytest` and `flutter analyze`. If this fails, nothing is deployed.
2. **deploy**: `flutter build web`, upload to the server, `docker compose -f docker-compose.prod.yml up -d --build`
   (runs `migrate` and `collectstatic` on start), then a check that `/health/` and the app answer.
   Until the GitHub secrets (step 7) exist, this job skips itself with a warning instead of failing.

The database and the uploads live in Docker volumes on the server; deploys never touch them.

---

## One-time setup (in this order)

### Step 1. DNS
At your domain provider (where `prowavetech.in` is managed) add:

| Type | Name | Value |
|---|---|---|
| A | `twv` | your VPS IP |

Check from your PC: `ping twv.prowavetech.in` shows the VPS IP (can take a few minutes).

### Step 2. CloudPanel site
If the site `twv.prowavetech.in` already exists as a **Reverse Proxy** site, skip to 2.2.
If it exists as another type (Static / PHP), either delete it and make it again as Reverse Proxy, or just do 2.3
(the vhost block below works on any site type).

2.1 CloudPanel → **Sites → Add Site → Create a Reverse Proxy**
   - Domain Name: `twv.prowavetech.in`
   - Reverse Proxy Url: `http://127.0.0.1:8080`
   - Site User: `prowavetech-twv` (CloudPanel needs one; the app does not use it).

2.2 The site → **SSL/TLS → Actions → New Let's Encrypt Certificate → Create and Install** (needs step 1 done).

2.3 The site → **Vhost**. Find the `location / { … }` block and make it exactly this, then **Save**:
```nginx
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
    proxy_request_buffering off;
    client_max_body_size 300M;
}
```
Why: `X-Forwarded-Proto` is a must (without it the API keeps redirecting to https). `Upgrade` / `Connection` =
live notifications. `client_max_body_size` = video uploads (300 MB).

### Step 3. Docker on the server (SSH as **root**, once; skip if probid_v2 already runs Docker here, just install rsync)
From your PC (PowerShell or Git Bash): `ssh root@<VPS IP>`, then:
```bash
curl -fsSL https://get.docker.com | sh          # installs Docker + docker compose
apt-get install -y rsync                         # deploys upload with rsync
docker --version && docker compose version       # both print a version = OK
```

### Step 4. Deploy SSH key (on your Windows PC)
**Already have the probid_v2 deploy key on this server's root?** Then reuse it: its private key is the
`VPS_SSH_KEY` for this repo too, and you can skip to step 6.

Otherwise make a new one. This key lets GitHub log in to the server as root. Open **PowerShell**:
```powershell
mkdir "$env:USERPROFILE\.ssh" -Force
ssh-keygen -t ed25519 -C "github-deploy-twv" -f "$env:USERPROFILE\.ssh\twv_deploy"
```
(Run it in **PowerShell**, not CMD. In Git Bash use `mkdir -p ~/.ssh && ssh-keygen -t ed25519 -C "github-deploy-twv" -f ~/.ssh/twv_deploy`.)
Press **Enter twice** when it asks for a passphrase (no passphrase; GitHub can't type one).
It makes two files in `C:\Users\<you>\.ssh\`:
- `twv_deploy` = **private** key → goes to GitHub only (step 7). Never share it anywhere else.
- `twv_deploy.pub` = **public** key → goes on the server (step 5).

Show the public key: `Get-Content $HOME\.ssh\twv_deploy.pub` (one line starting `ssh-ed25519 …`). Copy it.

### Step 5. Put the public key on the server
Log in as root the way you do today (`ssh root@<VPS IP>`), then (paste your `ssh-ed25519 …` line between the quotes):
```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA...your line... github-deploy-twv" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit
```
Test from the PC; it must log in **without asking a password**:
```powershell
ssh -i $HOME\.ssh\twv_deploy root@<VPS IP> "docker ps"
```

### Step 6. The server `.env` (once)
```bash
ssh root@<VPS IP>
mkdir -p ~/twv/backend ~/twv/secrets            # = /root/twv
nano ~/twv/backend/.env        # paste deploy/env.example from the repo, fill every <…>, Ctrl+O Enter, Ctrl+X
chmod 600 ~/twv/backend/.env
```
What to fill:
- `SECRET_KEY`: run `python3 -c "import secrets; print(secrets.token_urlsafe(50))"` on the server, paste the output.
- `POSTGRES_PASSWORD` and the same password inside `DATABASE_URL` (letters and numbers only, no `@ : /`).
- Gmail: Google account → Security → turn on **2-Step Verification** → search "**App passwords**" → make one
  ("Train With Vimal") → 16 letters → `EMAIL_HOST_PASSWORD` (no spaces). `EMAIL_HOST_USER` and
  `DEFAULT_FROM_EMAIL` = that Gmail.
- Leave `PUSH_PROVIDER=console` until the Firebase file is in place (Firebase section below).

### Step 7. GitHub secrets
GitHub → repo `train-with-vimal` → **Settings → Secrets and variables → Actions → New repository secret**, one by one:

| Name | Value |
|---|---|
| `VPS_HOST` | VPS IP |
| `VPS_USER` | `root` |
| `VPS_SSH_KEY` | the whole **private** key: PowerShell `Get-Content $HOME\.ssh\twv_deploy -Raw \| Set-Clipboard`, then paste (from `-----BEGIN` to `END … KEY-----`) |
| `VPS_PORT` | only if SSH is not on port 22 |
| `FIREBASE_JSON` | optional: content of `app/firebase.json` (web push on the live site, see Firebase below) |

### Step 8. First deploy
GitHub → **Actions → Deploy develop → Run workflow** (branch `develop`), or push anything to `develop`.
Wait for both jobs to go green (about 10 minutes the first time: it builds the Docker images). Then once, on the
server:
```bash
ssh root@<VPS IP>
cd ~/twv
docker compose -f docker-compose.prod.yml exec api python manage.py seed_defaults      # not seed_demo
docker compose -f docker-compose.prod.yml exec api python manage.py createsuperuser    # Vimal's admin login
```
Open https://twv.prowavetech.in and log in. From now on: merge `working` → `develop`, push, done.

---

## Firebase (push notifications)
Firebase project "Train With Vimal" exists with apps for package / bundle id **`com.trainwithvimal.app`** (the app
uses the same id). Server and app (Android + web) are built (D-56); iPhone waits for the Apple account.

1. **App keys:** fill `app/firebase.json` on your PC exactly as in the root `README.md` → "Push notifications on
   your PC" (web Config values, VAPID key, Android keys from `google-services.json`).
2. **Same keys for the live site:** GitHub → Settings → Secrets → Actions → New secret **`FIREBASE_JSON`** = the
   whole content of `app/firebase.json`. Every deploy then builds the web app with push on. (APK: build with
   `--dart-define-from-file=firebase.json`.)
3. iPhone only: Apple Developer account → **Certificates, IDs & Profiles → Keys → +** → tick **Apple Push
   Notifications service (APNs)** → download the `.p8` file (once only). Firebase → **Cloud Messaging → Apple app
   configuration → APNs Authentication Key → Upload**, with its Key ID and your Team ID.
4. Server key: **Project settings → Service accounts → Generate new private key** → a `.json` file.
   Upload it to the `secrets` folder from your PC (rename to `firebase-service-account.json`):
   ```powershell
   scp .\firebase-service-account.json root@<VPS IP>:twv/secrets/
   ```
   Then in `~/twv/backend/.env`:
   ```
   PUSH_PROVIDER=fcm
   FCM_PROJECT_ID=<Project ID, from Project settings → General>
   FCM_SERVICE_ACCOUNT_FILE=/app/secrets/firebase-service-account.json
   ```
   `/app/secrets/` is the same `secrets` folder as seen inside Docker (`./secrets:/app/secrets` in the compose
   file), so this path stays as written. Apply: `cd ~/twv && docker compose -f docker-compose.prod.yml up -d`.
None of these files go into git (`.gitignore` blocks `firebase.json`, `google-services.json`,
`GoogleService-Info.plist`, `secrets/` and every `*service-account*.json`).

---

## Handy commands (on the server, in `~/twv`)
- Logs: `docker compose -f docker-compose.prod.yml logs -f api` (or `web`, `worker`, `beat`)
- Restart one part: `docker compose -f docker-compose.prod.yml restart api`
- After changing `.env`: `docker compose -f docker-compose.prod.yml up -d`
- Database backup: `docker compose -f docker-compose.prod.yml exec db pg_dump -U twv twv > twv-$(date +%F).sql`
- Uploads backup: `docker run --rm -v twv_media:/m -v $PWD:/b alpine tar czf /b/media-$(date +%F).tgz -C /m .`

## Phone app (APK)
```bash
cd app
flutter build apk --release --dart-define=API_URL=https://twv.prowavetech.in --dart-define-from-file=firebase.json
# → app/build/app/outputs/flutter-apk/app-release.apk
```

## App icon and splash
Made from `app/assets/brand/` (Gautam's 500 x 500 logo). After changing those files:
`cd app && dart run flutter_launcher_icons && dart run flutter_native_splash:create`.
