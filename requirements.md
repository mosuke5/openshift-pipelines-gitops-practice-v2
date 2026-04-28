# 要求仕様書：OpenShift Pipelines & GitOps ハンズオン構成作成

## 1. 目的
OpenShift Pipelines (Tekton) と OpenShift GitOps (Argo CD) を活用した、モダンなCI/CDパイプラインの構築手順およびソースコード一式を作成する。フロントエンドとバックエンドが連携するマイクロサービス形式のデプロイフローを、Pipeline as Code (PaC) を用いて実現する。

---

## 2. システムアーキテクチャ


### 構成コンポーネント
* **Platform:** Red Hat OpenShift Container Platform (OpenShift Pipelines / GitOps 導入済み)
* **CI:** OpenShift Pipelines (Tekton) + Pipeline as Code
* **CD:** OpenShift GitOps (Argo CD)
* **Registry:** OpenShift Internal Registry (または Quay/Docker Hub)
* **Repositories (Git):**
    1.  **Backend Repo:** Java Spring Boot ソースコード
    2.  **Frontend Repo:** Nuxt.js ソースコード
    3.  **Manifest Repo:** 両アプリケーションのKubernetesマニフェスト (Kustomize構成)

---

## 3. 詳細要件

### A. CI パイプライン (Tekton)
* **トリガーメカニズム:**
    * **Pipeline as Code (PaC)** を利用。各ソースリポジトリの `.tekton` ディレクトリ内に `PipelineRun` 定義を配置する。
    * GitHub/GitLab/Bitbucket等のWebhookを受け、プルリクエストやプッシュ時に起動。
* **パイプラインステップ:**
    1.  **git-clone:** ソースコードの取得 (`git-clone` 使用)
    2.  **unit-test:** Maven (Backend) / npm (Frontend) によるテスト実行
    3.  **build-image:** **s2i** を利用したコンテナビルド。タグには **Gitのコミットハッシュ** を使用 
    4.  **update-manifest:** マニフェストレポジトリ内の対象イメージタグ（Kustomizeの `images` セクション等）を、ビルドしたハッシュ値に書き換えて `git push` する。
* **制約事項:** 可能な限り OpenShift が提供するデフォルトの `Task` を使用すること。

### B. CD デプロイ (Argo CD)
* **同期方法:** **Auto Sync** を有効化。
* **構成:**
    * `Application` リソースを1つ作成し、マニフェストレポジトリを監視。
    * Backend と Frontend のデプロイメントを包含する。
* **名前空間:** `hands-on-ci-cd` (仮) などの単一Namespaceへのデプロイ。

### C. リポジトリ構成案
* **Source Repos:**
    * `.tekton/` ディレクトリ配下に `pipeline-run.yaml` を配置。
* **Manifest Repo:**
    * `/envs/dev/` 配下に `kustomization.yaml` を配置。
    * `deployment.yaml`, `service.yaml`, `route.yaml` を定義。
    * マニフェストはKustomizeで管理

### 命名
このハンズオンは、プラットフォームを開発する側ではなく、アプリケーション開発者向けです。
Namespace名などに、わかりやすく `dev-handson-` とつけてください。

### プリセットで用意されているTekton Task
```
$ oc get task -n openshift-pipelines
NAME                        AGE
argocd-task-sync-and-wait   4d1h
buildah                     4d1h
buildah-1-21-0              10d
buildah-1-22-0              4d1h
buildah-ns                  4d1h
buildah-ns-1-21-0           10d
buildah-ns-1-22-0           4d1h
git-cli                     4d1h
git-cli-1-21-0              10d
git-cli-1-22-0              4d1h
git-clone                   4d1h
git-clone-1-21-0            10d
git-clone-1-22-0            4d1h
helm-upgrade-from-repo      4d1h
helm-upgrade-from-source    4d1h
jib-maven                   4d1h
kn                          4d1h
kn-1-21-0                   10d
kn-1-22-0                   4d1h
kn-apply                    4d1h
kn-apply-1-21-0             10d
kn-apply-1-22-0             4d1h
kubeconfig-creator          4d1h
maven                       4d1h
maven-1-21-0                10d
maven-1-22-0                4d1h
opc                         4d1h
opc-1-21-0                  10d
opc-1-22-0                  4d1h
openshift-client            4d1h
openshift-client-1-21-0     10d
openshift-client-1-22-0     4d1h
pull-request                4d1h
s2i-dotnet                  4d1h
s2i-dotnet-1-21-0           10d
s2i-dotnet-1-22-0           4d1h
s2i-go                      4d1h
s2i-go-1-21-0               10d
s2i-go-1-22-0               4d1h
s2i-java                    4d1h
s2i-java-1-21-0             10d
s2i-java-1-22-0             4d1h
s2i-nodejs                  4d1h
s2i-nodejs-1-21-0           10d
s2i-nodejs-1-22-0           4d1h
s2i-perl                    4d1h
s2i-perl-1-21-0             10d
s2i-perl-1-22-0             4d1h
s2i-php                     4d1h
s2i-php-1-21-0              10d
s2i-php-1-22-0              4d1h
s2i-python                  4d1h
s2i-python-1-21-0           10d
s2i-python-1-22-0           4d1h
s2i-ruby                    4d1h
s2i-ruby-1-21-0             10d
s2i-ruby-1-22-0             4d1h
skopeo-copy                 4d1h
skopeo-copy-1-21-0          10d
skopeo-copy-1-22-0          4d1h
tkn                         4d1h
tkn-1-21-0                  10d
tkn-1-22-0                  4d1h
trigger-jenkins-job         4d1h
```