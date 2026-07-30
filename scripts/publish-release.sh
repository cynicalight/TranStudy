#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

usage() {
  echo "usage: $0 [--yes] VERSION /path/to/release-notes.md" >&2
}

assume_yes=false
if [[ "${1:-}" == "--yes" ]]; then
  assume_yes=true
  shift
fi

if [[ $# -ne 2 ]]; then
  usage
  exit 64
fi

version=$1
release_notes_input=$2
tag="v$version"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must use semantic version form, for example 1.0.0" >&2
  exit 64
fi

if [[ ! -f "$release_notes_input" ]]; then
  echo "release notes file does not exist: $release_notes_input" >&2
  exit 66
fi

release_notes_dir=$(cd "$(dirname "$release_notes_input")" && pwd)
release_notes_file="$release_notes_dir/$(basename "$release_notes_input")"

if grep -F "Describe the user-visible changes" "$release_notes_file" >/dev/null ||
  grep -F "# TranStudy VERSION" "$release_notes_file" >/dev/null
then
  echo "release notes still contain template placeholders: $release_notes_file" >&2
  exit 65
fi

for command_name in git gh xcodegen xcodebuild hdiutil codesign shasum perl; do
  if ! command -v "$command_name" >/dev/null; then
    echo "required command is unavailable: $command_name" >&2
    exit 69
  fi
done

if [[ -n "$(git status --porcelain)" ]]; then
  echo "publishing requires a clean Git worktree" >&2
  exit 65
fi

branch=$(git branch --show-current)
if [[ -z "$branch" ]]; then
  echo "publishing from a detached HEAD is not supported" >&2
  exit 65
fi

gh auth status >/dev/null
default_branch=$(gh repo view --json defaultBranchRef --jq \
  '.defaultBranchRef.name')
if [[ "$branch" != "$default_branch" ]]; then
  echo "publishing must run from the default branch '$default_branch', found '$branch'" >&2
  exit 65
fi

upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' \
  2>/dev/null || true)
if [[ -z "$upstream" ]]; then
  echo "the current branch has no upstream" >&2
  exit 65
fi

git fetch origin "$branch" --quiet
if ! git merge-base --is-ancestor "$upstream" HEAD; then
  echo "the current branch is behind or has diverged from $upstream" >&2
  exit 65
fi

if git show-ref --verify --quiet "refs/tags/$tag"; then
  echo "local tag already exists: $tag" >&2
  exit 73
fi

if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
  echo "remote tag already exists: $tag" >&2
  exit 73
fi

if gh release view "$tag" >/dev/null 2>&1; then
  echo "GitHub Release already exists: $tag" >&2
  exit 73
fi

release_root="$repo_root/build/releases/$version"
if [[ -e "$release_root" ]]; then
  echo "release output already exists: $release_root" >&2
  exit 73
fi

project_file="$repo_root/project.yml"
marketing_version_count=$(grep -cE \
  '^[[:space:]]+MARKETING_VERSION:[[:space:]]+' "$project_file")
build_number_count=$(grep -cE \
  '^[[:space:]]+CURRENT_PROJECT_VERSION:[[:space:]]+' "$project_file")
if [[ "$marketing_version_count" -ne 1 || "$build_number_count" -ne 1 ]]; then
  echo "project.yml must contain exactly one app marketing version and build number" >&2
  exit 65
fi

current_version=$(awk \
  '$1 == "MARKETING_VERSION:" { print $2 }' "$project_file")
current_build_number=$(awk \
  '$1 == "CURRENT_PROJECT_VERSION:" { print $2 }' "$project_file")
if [[ ! "$current_build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "CURRENT_PROJECT_VERSION must be a positive integer" >&2
  exit 65
fi

build_number=$current_build_number
if [[ "$version" != "$current_version" ]]; then
  build_number=$((current_build_number + 1))
fi

echo "Release plan:"
echo "  branch: $branch"
echo "  version: $current_version -> $version"
echo "  build: $current_build_number -> $build_number"
echo "  tag: $tag"
echo "  notes: $release_notes_file"
echo "  action: commit version changes, build DMG, push, and publish GitHub Release"

if [[ "$assume_yes" != true ]]; then
  read -r -p "Continue? [y/N] " confirmation
  if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
    echo "Release cancelled."
    exit 0
  fi
fi

NEW_MARKETING_VERSION="$version" \
NEW_BUILD_NUMBER="$build_number" \
perl -0pi -e \
  's/^(\s*MARKETING_VERSION:\s*).*$/$1$ENV{NEW_MARKETING_VERSION}/m; s/^(\s*CURRENT_PROJECT_VERSION:\s*).*$/$1$ENV{NEW_BUILD_NUMBER}/m' \
  "$project_file"

xcodegen generate

updated_version=$(awk \
  '$1 == "MARKETING_VERSION:" { print $2 }' "$project_file")
updated_build_number=$(awk \
  '$1 == "CURRENT_PROJECT_VERSION:" { print $2 }' "$project_file")
if [[ "$updated_version" != "$version" ||
  "$updated_build_number" != "$build_number" ]]
then
  echo "failed to update project version" >&2
  exit 65
fi

git diff --check
git add project.yml TranStudy.xcodeproj
if ! git diff --cached --quiet; then
  git commit -m "chore: prepare $tag"
fi

release_commit=$(git rev-parse HEAD)

VERSION="$version" \
BUILD_NUMBER="$build_number" \
RELEASE_NOTES_FILE="$release_notes_file" \
"$repo_root/scripts/release.sh"

dmg_path="$release_root/TranStudy-$version.dmg"
checksum_path="$dmg_path.sha256"
appcast_path="$release_root/appcast.xml"
generated_notes_path="$release_root/TranStudy-$version.md"

(cd "$release_root" && shasum -a 256 -c "$(basename "$checksum_path")")
hdiutil verify "$dmg_path"

echo "Pushing $release_commit to origin/$branch and publishing $tag..."
git push origin "$branch"

if ! gh release create "$tag" \
  "$dmg_path" \
  "$checksum_path" \
  "$appcast_path" \
  --target "$release_commit" \
  --title "TranStudy $version" \
  --notes-file "$generated_notes_path" \
  --latest \
  --fail-on-no-commits
then
  echo "The release commit was pushed, but GitHub Release creation failed." >&2
  echo "The verified artifacts remain in $release_root for a manual retry." >&2
  exit 70
fi

git fetch --tags origin --quiet
echo "Published GitHub Release $tag."
