# セットアップガイド：OpenShift Pipelines & GitOps ハンズオン

## 前提条件

- OpenShift Container Platform へのアクセス（`oc` CLI ログイン済み）
- OpenShift Pipelines Operator がインストール済み
- OpenShift GitOps Operator がインストール済み
- Git リポジトリが 3 つ用意されていること
  - **Backend リポジトリ** — Java Spring Boot ソースコード
  - **Frontend リポジトリ** — Nuxt.js ソースコード
  - **Manifest リポジトリ** — Kustomize マニフェスト一式

---

## リポジトリ構成の概要

```
本リポジトリ
├── pipelines/           … Pipeline リソース（プラットフォームチーム管理）
├── setup/               … Namespace / Secret / PaC Repository
├── argocd/              … Argo CD Application
├── manifest/            … マニフェストリポジトリの内容
│   ├── base/            …   共通マニフェスト
│   └── envs/dev/        …   dev 環境オーバーレイ
├── backend-app/.tekton/ … Backend PipelineRun（アプリチームが配置）
└── frontend-app/.tekton/… Frontend PipelineRun（アプリチームが配置）
```

### 責任範囲

| 担当 | 管理対象 |
|------|----------|
| **プラットフォームチーム** | `pipelines/`, `setup/`, `argocd/`, `manifest/` |
| **アプリチーム** | 各ソースリポジトリの `.tekton/pipeline-run.yaml` |

---

## Step 1. Namespace の作成

```bash
oc apply -f setup/namespace.yaml
```

`dev-handson` Namespace が作成されます。

---

## Step 2. SSH 鍵の生成と登録

パイプラインの Git 操作（clone / push）には SSH 鍵を使用します。
このハンズオンでは、全リポジトリを横断でアクセスできる **1 つの SSH 鍵ペア** を使用します。

> **本番環境について:** 実環境では GitHub Apps 等を利用してリポジトリごとに適切な権限管理を行ってください。

### 2-1. 鍵ペアの生成

> **鍵の形式について:** Tekton の git-clone タスクが使用するコンテナの libcrypto バージョンによっては、OpenSSH 新形式 (ed25519 等) の秘密鍵を読み込めない場合があります (`Load key: error in libcrypto`)。互換性を確保するため **RSA + PEM 形式** で生成してください。

```bash
ssh-keygen -t rsa -b 4096 -m PEM -f ./dev-handson-git-key -N "" -C "dev-handson"
```

### 2-2. 公開鍵を Git アカウントに登録

生成した公開鍵を **ユーザーアカウントの SSH keys** に登録します。
これにより、アカウントがアクセスできる全リポジトリで鍵が利用可能になります。

**GitHub の場合:**
1. [Settings > SSH and GPG keys](https://github.com/settings/keys) を開く
2. **New SSH key** をクリック
3. Title に `dev-handson` 等を入力
4. 公開鍵の内容を貼り付けて保存

```bash
cat dev-handson-git-key.pub
```

### 2-3. Secret の作成

`oc` コマンドで Secret を作成します。`known_hosts` は `ssh-keyscan` で自動取得します。

```bash
ssh-keyscan github.com > /tmp/known_hosts 2>/dev/null

oc create secret generic git-ssh-key \
  -n dev-handson \
  --from-file=id_rsa=./dev-handson-git-key \
  --from-file=known_hosts=/tmp/known_hosts \
  --dry-run=client -o yaml | oc apply -f -
```

> **スクリプトを使う場合:** `tmp/create-ssh-secret.sh` を利用すると上記の手順を自動化できます。
>
> ```bash
> ./tmp/create-ssh-secret.sh ./dev-handson-git-key
> ```

> **GitHub 以外を使用する場合:** `ssh-keyscan` のホスト名を変更してください。
>
> ```bash
> ssh-keyscan gitlab.example.com > /tmp/known_hosts 2>/dev/null
> ```

### 2-4. 生成した鍵ファイルの削除

Secret 作成後、ローカルの秘密鍵は削除します。

```bash
rm -f dev-handson-git-key dev-handson-git-key.pub
```

---

## Step 3. PaC 用トークン Secret の作成

Pipeline as Code は Webhook の受信やコミットステータスの更新に Git プロバイダの API を使用します。
これには SSH 鍵ではなく **Personal Access Token (PAT)** が必要です。

`setup/pac-token-secret.yaml` のプレースホルダーを編集します。

| プレースホルダー | 設定値 |
|------------------|--------|
| `<YOUR_GIT_PERSONAL_ACCESS_TOKEN>` | PAT（`repo` スコープ） |

```bash
oc apply -f setup/pac-token-secret.yaml
```

---

## Step 4. Pipeline リソースのデプロイ（プラットフォームチーム）

プラットフォームチームが管理する Pipeline 定義をクラスタに適用します。

```bash
oc apply -f pipelines/dev-handson-backend-pipeline.yaml
oc apply -f pipelines/dev-handson-frontend-pipeline.yaml
```

確認:

```bash
oc get pipeline -n dev-handson
```

```
NAME                              AGE
dev-handson-backend-pipeline      10s
dev-handson-frontend-pipeline     10s
```

---

## Step 5. Pipeline as Code (PaC) Repository の登録

PaC が Webhook イベントを受けてパイプラインを起動できるよう、Repository リソースを作成します。

`setup/pac-repository-backend.yaml` と `setup/pac-repository-frontend.yaml` のリポジトリ URL を編集します。

| プレースホルダー | 設定値 |
|------------------|--------|
| `YOUR_ORG/backend-app` | Backend リポジトリの HTTPS URL |
| `YOUR_ORG/frontend-app` | Frontend リポジトリの HTTPS URL |

> **注意:** PaC Repository CR の `spec.url` は API アクセス用のため **HTTPS 形式** で指定します。

```bash
oc apply -f setup/pac-repository-backend.yaml
oc apply -f setup/pac-repository-frontend.yaml
```

確認:

```bash
oc get repository -n dev-handson
```

---

## Step 6. ソースリポジトリに PipelineRun を配置（アプリチーム）

各ソースリポジトリのルートに `.tekton/pipeline-run.yaml` を配置します。

### Backend リポジトリ

`backend-app/.tekton/pipeline-run.yaml` をコピーし、SSH URL を編集します。

| プレースホルダー | 設定値 |
|------------------|--------|
| `YOUR_ORG/backend-app.git` | Backend リポジトリの SSH URL |
| `YOUR_ORG/manifest-repo.git` | Manifest リポジトリの SSH URL |

```
backend-repo/
├── .tekton/
│   └── pipeline-run.yaml   ← このファイルを配置
├── pom.xml
└── src/
```

### Frontend リポジトリ

`frontend-app/.tekton/pipeline-run.yaml` を同様に配置します。

> **アプリチームが変更する箇所は SSH URL のパラメータのみです。**
> Pipeline のロジック自体はプラットフォームチーム側で管理されています。

---

## Step 7. マニフェストリポジトリの準備

`manifest/` ディレクトリの内容をマニフェストリポジトリに push します。

```bash
cd manifest/
git init
git remote add origin git@github.com:YOUR_ORG/manifest-repo.git
git add -A
git commit -m "Initial manifest"
git push -u origin main
```

マニフェストリポジトリの構造:

```
manifest-repo/
├── base/
│   ├── kustomization.yaml
│   ├── backend/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── route.yaml
│   └── frontend/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── route.yaml
└── envs/
    └── dev/
        └── kustomization.yaml   ← CI がイメージタグを自動更新
```

---

## Step 8. Argo CD Application の作成

`argocd/application.yaml` のリポジトリ URL を編集します。

| プレースホルダー | 設定値 |
|------------------|--------|
| `YOUR_ORG/manifest-repo.git` | Manifest リポジトリの HTTPS URL |

```bash
oc apply -f argocd/application.yaml
```

確認:

```bash
oc get application -n openshift-gitops
```

> Argo CD は `envs/dev/` を監視し、Auto Sync (prune + selfHeal) で `dev-handson` Namespace にデプロイします。

---

## 動作確認

### CLI からパイプラインを手動実行する

PaC (Webhook) によるトリガーの前に、`tkn` CLI でパイプラインを直接実行して動作を確認できます。

`tmp/start-build.sh` 内のリポジトリ URL を環境に合わせて編集してください。

| 変数 | 設定値 |
|------|--------|
| `REPO_URL` | Backend リポジトリの SSH URL |
| `MANIFEST_REPO_URL` | Manifest リポジトリの SSH URL |

```bash
# コミットハッシュを指定して実行
./tmp/start-build.sh <commit-hash>

# 引数を省略すると現在の git HEAD (short hash) を使用
./tmp/start-build.sh
```

ログがリアルタイムで表示されます。失敗した場合は個別タスクのログを確認してください:

```bash
tkn pipelinerun logs -n dev-handson --last
```

### CI パイプラインの確認 (PaC 経由)

Backend または Frontend リポジトリの `main` ブランチに push すると、パイプラインが自動起動します。

```bash
oc get pipelinerun -n dev-handson -w
```

パイプラインのフロー:

```
fetch-source ─→ unit-test ─→ build-image ─┐
                                           ├─→ update-manifest
fetch-manifest ────────────────────────────┘
```

1. **fetch-source** — ソースコードを SSH で clone
2. **unit-test** — テスト実行（Maven / npm）
3. **build-image** — S2I でコンテナイメージをビルド（タグ = コミットハッシュ）
4. **fetch-manifest** — マニフェストリポジトリを SSH で clone（1-3 と並行実行）
5. **update-manifest** — `kustomization.yaml` のイメージタグを更新して SSH で push

### CD デプロイの確認

パイプラインがマニフェストリポジトリを更新すると、Argo CD が自動的に同期します。

```bash
oc get pods -n dev-handson
```

デプロイされたアプリケーションの Route を確認:

```bash
oc get route -n dev-handson
```

---

## 認証方式の概要

```
┌───────────────────────────────────────────────────────────────┐
│  PaC (Webhook / API)                                          │
│    └─ Personal Access Token (pac-token-secret)                │
│       → コミットステータスの更新、Webhook の受信              │
│                                                               │
│  Pipeline (git clone / push)                                  │
│    └─ SSH 鍵 (git-ssh-key-secret) ← 1 つの鍵で全リポジトリ   │
│       → ソースリポ clone / マニフェストリポ clone・push       │
└───────────────────────────────────────────────────────────────┘
```

| 用途 | 認証方式 | Secret 名 |
|------|----------|-----------|
| PaC Webhook / API | Personal Access Token | `dev-handson-pac-token` |
| 全リポジトリの clone / push | SSH 鍵 | `dev-handson-git-ssh-key` |

> **実環境では** GitHub Apps やリポジトリごとの Deploy Key を使用し、最小権限の原則に従ってください。

---

## プレースホルダー一覧

| プレースホルダー | ファイル | 説明 |
|------------------|----------|------|
| SSH 秘密鍵ファイルパス | `tmp/create-ssh-secret.sh` の第 1 引数 | SSH 秘密鍵 (RSA PEM 形式) |
| `REPO_URL` | `tmp/start-build.sh` | Backend リポジトリの SSH URL |
| `MANIFEST_REPO_URL` | `tmp/start-build.sh` | Manifest リポジトリの SSH URL |
| `<YOUR_GIT_PERSONAL_ACCESS_TOKEN>` | `setup/pac-token-secret.yaml` | PaC 用 PAT |
| `YOUR_ORG/backend-app` | `setup/pac-repository-backend.yaml` | Backend リポジトリ URL (HTTPS) |
| `YOUR_ORG/frontend-app` | `setup/pac-repository-frontend.yaml` | Frontend リポジトリ URL (HTTPS) |
| `YOUR_ORG/backend-app.git` | `backend-app/.tekton/pipeline-run.yaml` | Backend リポジトリ URL (SSH) |
| `YOUR_ORG/frontend-app.git` | `frontend-app/.tekton/pipeline-run.yaml` | Frontend リポジトリ URL (SSH) |
| `YOUR_ORG/manifest-repo.git` | `*/.tekton/pipeline-run.yaml`, `argocd/application.yaml` | Manifest リポジトリ URL |
