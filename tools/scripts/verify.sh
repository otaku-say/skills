#!/bin/sh
set -eu

ROOT="${HOME:?请先设置 HOME}/.local/share/ish-toolbox/tools"

fail() {
  printf '校验失败：%s\n' "$1" >&2
  exit 1
}

[ "$#" -le 1 ] || fail "用法：sh $0 [工具目录]"
[ "$#" -eq 0 ] || ROOT="$1"
[ -d "$ROOT" ] || fail "找不到工具目录：$ROOT"

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v busybox >/dev/null 2>&1; then
    busybox sha256sum "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    fail "校验需要 sha256sum、BusyBox 或 openssl"
  fi
}

verify_manifest() {
  manifest="$1"
  while read -r expected relative extra || [ -n "${expected:-}" ]; do
    [ -n "${expected:-}" ] || continue
    [ -z "${extra:-}" ] || fail "校验清单格式无效：$manifest"
    file="$ROOT/$relative"
    [ -f "$file" ] || fail "文件缺失：$relative"
    actual="$(hash_file "$file")"
    [ "$actual" = "$expected" ] || fail "SHA256 不匹配：$relative"
  done < "$manifest"
}

for arch in amd64 arm64; do
  verify_manifest "$ROOT/SHA256SUMS.$arch"
done
verify_manifest "$ROOT/DOCS.sha256"

count=0
for tool_dir in "$ROOT"/*; do
  [ -d "$tool_dir" ] || continue
  tool="$(basename "$tool_dir")"
  case "$tool" in scripts|references) continue ;; esac
  [ -f "$tool_dir/USAGE.md" ] || fail "$tool 缺少 USAGE.md"
  for arch in amd64 arm64; do
    binary="$tool_dir/$arch/$tool"
    [ -f "$binary" ] && [ -x "$binary" ] || fail "$tool 缺少可执行的 $arch 二进制"
  done
  count=$((count + 1))
done

printf '校验通过：%s 个工具、两个架构二进制和全部说明文档。\n' "$count"
