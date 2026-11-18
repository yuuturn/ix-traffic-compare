#!/bin/bash
# /usr/local/bin/fetch-ix-traffic.sh
# 各IXのトラフィックグラフ画像を取得し、タイムスタンプ付きで保存する
# 実行環境: Ubuntu 24.04 LTS

set -euo pipefail

BASE_DIR="/var/www/ix-traffic"
IMG_DIR="${BASE_DIR}/images"
MANIFEST="${BASE_DIR}/manifest.json"
TIMESTAMP=$(date +"%Y%m%d_%H%M")
LOG_TAG="ix-traffic-fetch"

# User-Agent（礼儀として設定）
UA="ix-traffic-archiver/1.0"

# 取得先定義: "ディレクトリ名|URL"
SOURCES=(
  "jpnap_tokyo|https://www.jpnap.net/assets/traffic/jpnap_tokyo_day.png"
  "jpnap_osaka|https://www.jpnap.net/assets/traffic/jpnap_osaka_day.png"
  "jpix_tokyo|https://jpixtrafficgraph.s3.ap-northeast-1.amazonaws.com/TOTAL.In.png"
  "jpix_osaka|https://jpixtrafficgraph.s3.ap-northeast-1.amazonaws.com/TOTAL-OSK.In.png"
  "bbix_tokyo|https://www.bbix.net/bbix_traffic/TK_d.png"
  "bbix_osaka|https://www.bbix.net/bbix_traffic/OS_d.png"
)

FAIL_COUNT=0

for entry in "${SOURCES[@]}"; do
  IFS='|' read -r dir url <<< "${entry}"
  DEST="${IMG_DIR}/${dir}/${TIMESTAMP}.png"

  if wget -q --timeout=30 --tries=2 -U "${UA}" -O "${DEST}" "${url}"; then
    # ファイルサイズが0ならエラー扱い
    if [ ! -s "${DEST}" ]; then
      logger -t "${LOG_TAG}" "WARN: Empty file for ${dir}, removing ${DEST}"
      rm -f "${DEST}"
      ((FAIL_COUNT++))
    fi
  else
    logger -t "${LOG_TAG}" "ERROR: Failed to fetch ${dir} from ${url}"
    rm -f "${DEST}"  # 不完全ファイル除去
    ((FAIL_COUNT++))
  fi
done

# --- manifest.json 生成 ---
# 保存済みの全タイムスタンプを走査してJSON化
# JSから利用するため、IX名とタイムスタンプ一覧を出力

generate_manifest() {
  echo '{'

  local first_ix=true
  for entry in "${SOURCES[@]}"; do
    IFS='|' read -r dir _ <<< "${entry}"
    local ix_dir="${IMG_DIR}/${dir}"

    if [ "${first_ix}" = true ]; then
      first_ix=false
    else
      echo ','
    fi

    printf '  "%s": [' "${dir}"

    local first_ts=true
    # ファイル名からタイムスタンプ抽出（ソート済み）
    for f in $(find "${ix_dir}" -name '*.png' -printf '%f\n' 2>/dev/null | sort); do
      ts="${f%.png}"
      if [ "${first_ts}" = true ]; then
        first_ts=false
      else
        printf ','
      fi
      printf '"%s"' "${ts}"
    done

    printf ']'
  done

  echo ''
  echo '}'
}

generate_manifest > "${MANIFEST}.tmp"
mv "${MANIFEST}.tmp" "${MANIFEST}"
chown www-data:www-data "${MANIFEST}"

if [ "${FAIL_COUNT}" -gt 0 ]; then
  logger -t "${LOG_TAG}" "Completed with ${FAIL_COUNT} failure(s) at ${TIMESTAMP}"
else
  logger -t "${LOG_TAG}" "OK: All images fetched at ${TIMESTAMP}"
fi

exit 0
