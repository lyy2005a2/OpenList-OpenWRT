#!/bin/bash

# 仓库配置
SOURCE_REPO="OpenListTeam/OpenList-OpenWRT"
DEST_REPO="lyy2005a2/OpenList-OpenWRT"

# 检查依赖
check_command() {
    command -v "$1" >/dev/null 2>&1 || { echo "错误：请安装 $1"; exit 1; }
}
check_command git
check_command gh

# 跳过登录检查（直接强制执行，适用于已登录但识别异常的情况）
echo "跳过登录检查（假设已登录）..."

# 临时目录（拉取源仓库标签）
TEMP_DIR=$(mktemp -d)
echo "临时目录：$TEMP_DIR"

# 克隆源仓库（仅标签，静默模式）
echo "拉取源仓库标签..."
if ! git clone --bare --depth 1 "https://github.com/$SOURCE_REPO.git" "$TEMP_DIR" >/dev/null 2>&1; then
    echo "克隆源仓库失败，请检查网络或权限"
    rm -rf "$TEMP_DIR"
    exit 1
fi
cd "$TEMP_DIR" || { echo "无法进入临时目录"; rm -rf "$TEMP_DIR"; exit 1; }

# 获取源仓库所有 Release 标签
tags=$(gh release list --repo "$SOURCE_REPO" --json tagName --jq '.[].tagName' 2>/dev/null)
if [ -z "$tags" ]; then
    echo "源仓库没有找到 Release"
    rm -rf "$TEMP_DIR"
    exit 0
fi

# 拉取源仓库标签到本地临时仓库
git fetch --tags >/dev/null 2>&1
cd - >/dev/null || exit

# 处理每个标签
echo "$tags" | while IFS= read -r tag; do
    [ -z "$tag" ] && continue
    echo "===== 处理标签: $tag ====="

    # 拉取本地缺失的标签
    if ! git show-ref --verify --quiet "refs/tags/$tag"; then
        echo "本地缺失标签 $tag，从源仓库拉取..."
        if ! git fetch "$TEMP_DIR" "refs/tags/$tag:refs/tags/$tag" >/dev/null 2>&1; then
            echo "标签 $tag 拉取失败，跳过"
            continue
        fi
    fi

    # 检查目标仓库是否已存在该 Release
    if gh release view "$tag" --repo "$DEST_REPO" >/dev/null 2>&1; then
        echo "Release $tag 已存在，同步资产..."
        temp_assets=$(mktemp -d)
        gh release download "$tag" --repo "$SOURCE_REPO" --dir "$temp_assets" --skip-existing >/dev/null 2>&1
        if [ -n "$(ls -A "$temp_assets")" ]; then
            gh release upload "$tag" --repo "$DEST_REPO" "$temp_assets"/* --clobber >/dev/null 2>&1
            echo "资产同步完成"
        else
            echo "无新资产需要同步"
        fi
        rm -rf "$temp_assets"
        continue
    fi

    # 创建 Release（含标题、描述、预发布状态）
    echo "在目标仓库创建 Release: $tag"
    title=$(gh release view "$tag" --repo "$SOURCE_REPO" --json name --jq '.name' 2>/dev/null)
    body=$(gh release view "$tag" --repo "$SOURCE_REPO" --json body --jq '.body' 2>/dev/null)
    prerelease=$(gh release view "$tag" --repo "$SOURCE_REPO" --json prerelease --jq '.prerelease' 2>/dev/null)

    # 执行创建命令
    gh release create "$tag" \
        --repo "$DEST_REPO" \
        --title "${title:-Release $tag}" \
        --notes "${body:-自动同步自 $SOURCE_REPO}" \
        $([ "$prerelease" = "true" ] && echo "--prerelease") >/dev/null 2>&1

    # 同步资产
    temp_assets=$(mktemp -d)
    gh release download "$tag" --repo "$SOURCE_REPO" --dir "$temp_assets" --skip-existing >/dev/null 2>&1
    if [ -n "$(ls -A "$temp_assets")" ]; then
        gh release upload "$tag" --repo "$DEST_REPO" "$temp_assets"/* >/dev/null 2>&1
        echo "资产上传完成"
    else
        echo "该 Release 无资产"
    fi
    rm -rf "$temp_assets"
done

# 清理临时文件
rm -rf "$TEMP_DIR"
echo "===== 所有操作完成 ====="