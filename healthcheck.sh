#!/usr/bin/env bash
set -euo pipefail

: "${COMFY_PORT:=3000}"
: "${SWARMUI_PORT:=7861}"
: "${DL_PORT:=7862}"
: "${SWARMUI_ENABLE:=false}"
: "${SWARMUI_DOWNLOADER_ENABLE:=false}"

curl -fsS "http://127.0.0.1:${COMFY_PORT}/" >/dev/null

if [[ "${SWARMUI_ENABLE,,}" == "true" ]]; then
  curl -fsS "http://127.0.0.1:${SWARMUI_PORT}/" >/dev/null
fi

if [[ "${SWARMUI_DOWNLOADER_ENABLE,,}" == "true" ]]; then
  curl -fsS "http://127.0.0.1:${DL_PORT}/" >/dev/null
fi
