#!/usr/bin/env bash
#
# Sometimes it'super funny to make a hacky bash script
# if it does not serve any productive purpose :)
#

USER="${GITHUB_REPOSITORY_OWNER:paescuj}"

SCRIPT_DIR=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
LANGUAGES=''
LICENSES=''

getInfo() {
  declare -n repoInfo="$1"

  local ownerName="${repoInfo[ownerName]}"
  repoInfo[response]=$(curl --silent --header 'Accept: application/vnd.github+json' "https://api.github.com/repos/${ownerName}")
  repoInfo[owner]=${ownerName%/*}
  repoInfo[name]=${ownerName#*/}
  repoInfo[description]=$(echo "${repoInfo[response]}" | jq --raw-output '.description')
}

getBadge() {
  declare -n repoInfo="$1"
  declare type="$2"

  local link="https://github.com/${repoInfo[ownerName]}"

  case "$type" in
    language)
      local alt="Top language of ${repoInfo[name]}"
      local languagesUrl=$(echo "${repoInfo[response]}" | jq --raw-output '.languages_url')
      local languages=$(curl --silent --header 'Accept: application/vnd.github+json' "$languagesUrl")
      local language=$(echo "$languages" | jq --raw-output 'to_entries | .[] | [.key, .value] | join(",")' | awk -F, '{a[$1]=$2; s+=$2} END {for (i in a) {a[i]=a[i]/s*100; if (a[i] > a[m]) m = i}; printf "%s,%.f", m, a[m]}')
      local name=${language%,*}
      local pct=${language#*,}
      if [[ -z $LANGUAGES ]]; then
        LANGUAGES=$(curl --silent https://raw.githubusercontent.com/github/linguist/master/lib/linguist/languages.yml)
      fi
      local color=$(echo "$LANGUAGES" | yq ".${name}.color" )
      local url="https://img.shields.io/static/v1?label=$(printf '%s' "$name" | jq --raw-input --slurp --raw-output @uri)&message=${pct}%25&color=${color:1}"
      ;;
    license)
      local alt="License of ${repoInfo[name]}"
      local licenseInfo=$(curl --silent --header 'Accept: application/vnd.github+json' "https://api.github.com/repos/${repoInfo[ownerName]}/license")
      local name=$(echo "$licenseInfo" | jq --raw-output '.license.spdx_id')
      local link=$(echo "$licenseInfo" | jq --raw-output '.html_url')
      if [[ -z $LANGUAGES ]]; then
        LICENSES=$(curl --silent https://raw.githubusercontent.com/badges/shields/master/services/licenses.js)
      fi
      local color=$(echo "$LICENSES" | sed -n "/${name}/,\$p" |  sed -n "s/.*color: '\(.*\)\x27.*/\1/p" | head -1)
      local url="https://img.shields.io/static/v1?label=License&message=${name}&color=${color}"
      ;;
    stars)
      local alt="Stars of ${repoInfo[name]} on GitHub"
      local stars=$(echo "${repoInfo[response]}" | jq --raw-output '.stargazers_count' | numfmt --to=si --round=nearest)
      local url="https://img.shields.io/static/v1?label=Stars&message=${stars}&color=blue&logo=github"
      ;;
    weekly_downloads)
      local alt="Weekly downloads of ${repoInfo[name]} on NPM"
      local url="https://img.shields.io/npm/dw/${repoInfo[npm]}?label=Downloads&logo=npm"
      link="https://www.npmjs.com/package/${repoInfo[npm]}"
      ;;
    used_by)
      local alt="Dependent repos of ${repoInfo[name]}"
      link="https://github.com/${repoInfo[ownerName]}/network/dependents"
      local dependentsHtml=$(curl --silent "$link")
      local usedBy=$(echo "$dependentsHtml" | tr -d '[:space:]' | sed 's/.*type=REPOSITORY.*svg>\(.*\)Repositories.*/\1/' | tr -d ',' | numfmt --to=si --round=nearest)
      local url="https://img.shields.io/static/v1?label=Used%20by&message=${usedBy}&color=blue&logo=githubactions&logoColor=white"
      ;;
  esac

  printf '[![%s](%s)](%s)' "$alt" "$url" "$link" 
}

getContribution() {
  declare -n repoInfo="$1"

  repoInfo[contributionLink]="https://github.com/${info[ownerName]}/pulls?q=author:${USER}+is:merged"
  repoInfo[contributionCount]=$(curl --silent --header 'Accept: application/vnd.github+json' "https://api.github.com/search/issues?q=repo:${repoInfo[ownerName]}+author:${USER}+is:merged&per_page=1" | jq --raw-output '.total_count')
}

yq --output-format json "${SCRIPT_DIR}/references.yml" | jq --compact-output 'to_entries | .[]' | while read section; do
  title=$(echo "$section" | jq --raw-output '.key')
  printf '\n<details><summary><strong>%s</strong></summary>\n<p><ul>\n' "$title"

  main=$(echo "$section" | jq --compact-output '.value.main | to_entries | .[]')
  while read repo; do
    declare -A info=( [ownerName]=$(echo "$repo" | jq --raw-output '.key') )
    getInfo info
    values=$(echo "$repo" | jq --compact-output '.value')
    badges=$(echo "$values" | jq --compact-output --raw-output '.badges | .[]')
    info[npm]=$(echo "$values" | jq --raw-output --exit-status '.npm // empty' || printf "${info[name]}")

    printf '<table><tr><td width="500px">\n'
    printf '<p>\n\n<a href="%s">%s</a> / <a href="%s"><b>%s</b></a>\n' "https://github.com/${info[owner]}" "${info[owner]}" "https://github.com/${info[ownerName]}" "${info[name]}"

    if [[ $(echo "$section" | jq '.value.options.contribution') = 'true' ]]; then
      getContribution info
      printf '<br><sub>(contributed with <a href="%s">%i merged pull requests</a>)</sub>' "${info[contributionLink]}" "${info[contributionCount]}"
    fi

    printf '\n</p>\n\n'
    printf '> %s\n\n' "${info[description]}"

    while read badge; do
      printf '%s\n' "$(getBadge info "$badge")"
    done <<< "$badges"

    printf '\n</td></tr></table>\n'
    (( count++ ))
  done <<< "$main"

  more=$(echo "$section" | jq --compact-output --raw-output '.value.more | .[]?')
  if [[ ! -z $more ]]; then
    printf '<details><summary><strong>Show me more...</strong></summary>\n<p>\n'

    while read repo; do
      declare -A info=( [ownerName]="$repo" )
      getInfo info

      printf '\n<a href="%s">%s</a> / <a href="%s"><b>%s</b></a>' "https://github.com/${info[owner]}" "${info[owner]}" "https://github.com/${repo}" "${info[name]}"

      if [[ $(echo "$section" | jq '.value.options.contribution') = 'true' ]]; then
        getContribution info
        printf ' <sup>(<a href="%s">%i merged pull requests</a>)</sup>' "${info[contributionLink]}" "${info[contributionCount]}"
      fi

      printf '\n<br>%s\n' "${info[description]}"
    done <<< "$more"

    printf '</p>\n</details>\n'
  fi

  printf '</ul></p>\n</details>\n'
done

printf '\n'
