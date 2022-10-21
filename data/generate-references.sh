#!/usr/bin/env bash

SCRIPT_DIR=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)

getBadge() {
  declare name="$1" repo="$2" npm="$3" type="$4"

  local link="https://github.com/${repo}"

  case "$type" in
    language)
      local alt="Top language of ${name}"
      local url="https://img.shields.io/github/languages/top/${repo}"
      ;;
    license)
      local alt="License of ${name}"
      local url="https://img.shields.io/github/license/${repo}?label=License"
      ;;
    stars)
      local alt="Stars of ${name} on GitHub"
      local url="https://img.shields.io/github/stars/${repo}?label=Stars&logo=github"
      ;;
    downloads)
      local alt="Weekly downloads of ${name} on NPM"
      local url="https://img.shields.io/npm/dw/${npm}?label=Downloads&logo=npm"
      link="https://www.npmjs.com/package/${npm}"
      ;;
    dependent_repos)
      local alt="Dependent repos of ${name}"
      local url="https://img.shields.io/librariesio/dependent-repos/npm/${npm}?label=Dependent%20Repos"
  esac

  printf '[![%s](%s)](%s)' "$alt" "$url" "$link" 
}

jq --compact-output 'to_entries | .[]' "${SCRIPT_DIR}/sections.json" | while read section; do
  title=$(echo "$section" | jq --raw-output '.key')
  entries=$(echo "$section" | jq --compact-output '.value | .[]')

  printf '\n<details><summary><strong>%s</strong></summary>\n<p>\n' "$title"

  while read entry; do
    printf '<table><tr><td width="550px">\n'
    repo=$(echo "$entry" | jq --raw-output '.repo')
    owner=${repo%/*}
    name=${repo#*/}
    npm=$(echo "$entry" | jq --raw-output --exit-status '.npm // empty' || printf "$name")
    badges=$(echo "$entry" | jq --compact-output --raw-output '.badges | .[]')
    description=$(curl --silent --header 'Accept: application/vnd.github+json' "https://api.github.com/repos/${repo}" | jq --raw-output '.description')

    printf '<p>\n\n[%s](%s) / [**%s**](%s)\n\n</p>\n\n' "$owner" "https://github.com/${owner}" "$name" "https://github.com/${repo}"
    printf '> %s\n\n' "$description"

    while read badge; do
      printf '%s\n' "$(getBadge "$name" "$repo" "$npm" "$badge")"
    done <<< "$badges"

    printf '\n</td></tr></table>\n'
  done <<< "$entries"

  printf '</p>\n</details>\n\n'
done
