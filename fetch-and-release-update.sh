#!/bin/sh
set -eu

# Global variables
GNUPGHOME=$(mktemp -d)

if [ -z "${repository-}" ]; then
  echo "Repository not defined, please set it first"
  exit 1
fi

if [ -z "${project-}" ]; then
  echo "Project name not defined, please set it first"
  exit 1
fi

if [ -z "${GH_TOKEN-}" ]; then
  echo "GH_TOKEN not defined, please set it for properly working"
  exit 1
fi

if [ -n "${GIT_USERNAME-}" ] && [ -n "${GIT_EMAIL-}" ]; then
  git config --local user.email "$GIT_EMAIL"
  git config --local user.name "$GIT_USERNAME"
  echo "Git username [$GIT_USERNAME] and Git e-mail [$GIT_EMAIL] set"
fi
if [ -n "${GPG_KEY-}" ]; then
  echo "$GPG_KEY" | base64 --decode | gpg --homedir "$GNUPGHOME" --quiet --batch --import
fi
if [ -z "${GPG_NO_SIGN-}" ] && [ -n "${GPG_KEY_ID-}" ]; then
  git config --local commit.gpgsign true
  git config --local user.signingkey "$GPG_KEY_ID"
  git config --local tag.forceSignAnnotated true
  git config --local gpg.program gpg
  echo "Git GPG sign and key ID [$GPG_KEY_ID] are set"
fi

if [ -z "${GPG_NO_SIGN-}" ] && [ -n "${GPG_PASSPHRASE-}" ]; then
  echo "allow-loopback-pinentry" >>"$GNUPGHOME/gpg-agent.conf"
  echo "pinentry-mode loopback" >>"$GNUPGHOME/gpg.conf"
  gpg-connect-agent --homedir "$GNUPGHOME" reloadagent /bye

  echo "" | gpg --homedir "$GNUPGHOME" --quiet --passphrase "$GPG_PASSPHRASE" --batch --pinentry-mode loopback --sign >/dev/null
  echo "Git GPG passphrase set"
fi

TAG=$(curl -s "https://api.github.com/repos/${repository}/releases/latest" | grep 'tag_name' | cut -d ':' -f2 | cut -d '_' -f2 | cut -d '/' -f2 | rev | cut -c3- | rev | tr '"' 'v' | xargs)
echo "Git tag was acqiured"

if git rev-parse "refs/tags/${TAG}" >/dev/null 2>&1; then
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
