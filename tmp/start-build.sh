#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# =============================================
# 設定 — 環境に合わせて変更してください
# =============================================
NAMESPACE="dev-handson"
PIPELINE_NAME="dev-handson-backend-pipeline"

REPO_URL="git@github.com:<org>/<backend-repo>.git"
MANIFEST_REPO_URL="git@github.com:<org>/<manifest-repo>.git"

SSH_SECRET="git-ssh-key"
VCT_FILE="${SCRIPT_DIR}/vct.yaml"

# =============================================
# revision の決定
#   引数があればそれを使い、なければ現在の HEAD を使用
# =============================================
if [[ $# -ge 1 ]]; then
  REVISION="$1"
else
  REVISION="$(git rev-parse --short HEAD)"
  echo "revision が未指定のため HEAD を使用します: ${REVISION}"
fi

# =============================================
# Pipeline 実行
# =============================================
echo "==> Pipeline を開始します"
echo "    namespace : ${NAMESPACE}"
echo "    pipeline  : ${PIPELINE_NAME}"
echo "    revision  : ${REVISION}"
echo ""

tkn pipeline start "${PIPELINE_NAME}" \
  -n "${NAMESPACE}" \
  -p repo-url="${REPO_URL}" \
  -p revision="${REVISION}" \
  -p manifest-repo-url="${MANIFEST_REPO_URL}" \
  -w name=shared-workspace,volumeClaimTemplateFile="${VCT_FILE}" \
  -w name=git-ssh-key,secret="${SSH_SECRET}" \
  -w name=maven-settings,emptyDir="" \
  --showlog
