#!/usr/bin/env bash

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

cat data/header.md

jq --compact-output 'to_entries | .[]' data/sections.json | while read section; do
  title=$(echo "$section" | jq --raw-output '.key')
  entries=$(echo "$section" | jq --compact-output '.value | to_entries | .[]')

  printf '\n<details><summary><strong>%s</strong></summary>\n\n---\n\n' "$title"

  while read entry; do
    name=$(echo "$entry" | jq --raw-output '.key')
    repo=$(echo "$entry" | jq --raw-output '.value.repo')
    npm=$(echo "$entry" | jq --raw-output --exit-status '.value.npm // empty' || printf "$name")
    badges=$(echo "$entry" | jq --compact-output --raw-output '.value.badges | .[]')
    description=$(curl --silent --header 'Accept: application/vnd.github+json' "https://api.github.com/repos/${repo}" | jq --raw-output '.description')

    printf '[**%s**](%s)\n\n' "$name" "https://github.com/${repo}"
    printf '> %s\n\n' "$description"

    while read badge; do
      printf '%s\n' "$(getBadge "$name" "$repo" "$npm" "$badge")"
    done <<< "$badges"

    printf '\n---\n\n'
  done <<< "$entries"

  printf '</details>\n\n'
done

