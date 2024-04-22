#!/bin/sh
set -eu

if [ -z "${repository-}" ]; then
  echo "Repository not defined, please set it first"
  exit 1
fi

if [ -z "${project-}" ]; then
  echo "Project name not defined, please set it first"
  exit 1
fi

if [ -n "${GIT_USERNAME-}" ] && [ -n "${GIT_EMAIL-}" ]; then
  git config --local user.email "$GIT_EMAIL"
  git config --local user.name "$GIT_USERNAME"
  echo "Git username [$GIT_USERNAME] and Git e-mail [$GIT_EMAIL] set"
fi
if [ -n "${GPG_KEY-}" ]; then
  echo "$GPG_KEY" | base64 --decode | gpg --quiet --batch --import
fi
if [ -z "${GPG_NO_SIGN-}" ] && [ -n "${GPG_KEY_ID-}" ]; then
  git config --local commit.gpgsign true
  git config --local user.signingkey "$GPG_KEY_ID"
  git config --local tag.forceSignAnnotated true
  git config --local gpg.program gpg
  echo "Git GPG sign and key ID [$GPG_KEY_ID] are set"
fi

if [ -z "${GPG_NO_SIGN-}" ] && [ -n "${GPG_PASSPHRASE-}" ]; then
  echo "" | gpg --quiet --passphrase "$GPG_PASSPHRASE" --batch --pinentry-mode loopback --sign >/dev/null
  echo "Git GPG passphrase set"
fi

RELEASES=""
if [ -n "${GH_TOKEN-}" ]; then
  RELEASES=$(curl -s -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${repository}/releases")
else
  RELEASES=$(curl -s "https://api.github.com/repos/${repository}/releases")
fi

TAG=$(echo "${RELEASES}" | grep 'tag_name' | xargs -L1 | cut -d ':' -f2 | cut -d '/' -f2 | cut -d '_' -f2 | xargs -L1 | grep -E '^v?[0-9]' | head -1 | tr -d ',')
echo "Git tag was acqiured"

if ! git rev-parse "refs/tags/${TAG}" >/dev/null 2>&1; then
  npm version "$(echo "${TAG}" | tr -d 'v')" -m "Upgrade ${project} to ${TAG}" --sign-git-tag
  echo "Git tag and npm updated"

  git checkout -b remote-upgrade
  git push origin remote-upgrade --force
  gh pr create -B master -H remote-upgrade --title "Upgrade ${project}" --body "Upgrade ${project} to ${TAG}"
  echo "Update PR created"

  git checkout master
  git rebase remote-upgrade
  git push
  git branch -d remote-upgrade
  git push origin --delete remote-upgrade
  echo "PR rebase into master"

  git push --tags
  echo "Tags was pushed"
  gh release create --verify-tag "${TAG}" --notes "Upgrade **${project}** to \`${TAG}\`"
  echo "GitHub release was pushed"
fi
