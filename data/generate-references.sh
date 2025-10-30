#!/usr/bin/env bash
#
# Script happens...

set -e -o pipefail

readonly _user="${GITHUB_REPOSITORY_OWNER:-paescuj}"
readonly _scriptDir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
readonly _curlArgs=('--fail' '--silent')
_languages=''
_licenses=''

ghApi() {
	# Avoid running into rate limit
	sleep 1
	gh api --header 'Accept: application/vnd.github+json' --header 'X-GitHub-Api-Version: 2022-11-28' "$@"
}

getInfo() {
	declare -n repoInfo="$1"

	local ownerName="${repoInfo[ownerName]}"
	repoInfo[response]=$(ghApi "/repos/${ownerName}")
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
		local languages=$(ghApi "$languagesUrl")
		local language=$(echo "$languages" | jq --raw-output 'to_entries | .[] | [.key, .value] | join(",")' | awk -F, '{a[$1]=$2; s+=$2} END {for (i in a) {a[i]=a[i]/s*100; if (a[i] > a[m]) m = i}; printf "%s,%.f", m, a[m]}')
		local name=${language%,*}
		local pct=${language#*,}
		if [[ -z $_languages ]]; then
			_languages=$(curl "${_curlArgs[@]}" https://raw.githubusercontent.com/github/linguist/master/lib/linguist/languages.yml)
		fi
		local color=$(echo "$_languages" | yq ".${name}.color")
		local url="https://img.shields.io/static/v1?label=$(printf '%s' "$name" | jq --raw-input --slurp --raw-output @uri)&message=${pct}%25&color=${color:1}"
		;;
	license)
		local alt="License of ${repoInfo[name]}"
		local licenseInfo=$(ghApi "/repos/${repoInfo[ownerName]}/license")
		local name=$(echo "$licenseInfo" | jq --raw-output '.license.spdx_id')
		local link=$(echo "$licenseInfo" | jq --raw-output '.html_url')
		if [[ -z $_licenses ]]; then
			_licenses=$(curl "${_curlArgs[@]}" https://raw.githubusercontent.com/badges/shields/master/services/licenses.js)
		fi
		local color=$(echo "$_licenses" | sed -n "/${name}/,\$p" | sed -n "s/.*color: '\(.*\)\x27.*/\1/p" | head -1)
		local url="https://img.shields.io/static/v1?label=License&message=${name}&color=${color}"
		;;
	stars)
		local alt="Stars of ${repoInfo[name]} on GitHub"
		local stars=$(echo "${repoInfo[response]}" | jq --raw-output '.stargazers_count' | numfmt --to=si --round=nearest)
		local url="https://img.shields.io/static/v1?label=Stars&message=${stars}&color=blue&logo=github"
		;;
	weekly_downloads)
		local alt="Weekly downloads of ${repoInfo[name]} on NPM"
		local downloads=$(curl "${_curlArgs[@]}" "https://api.npmjs.org/downloads/point/last-week/${repoInfo[npm]}" | jq '.downloads')
		local count=$(echo "$downloads" | numfmt --to=si --round=nearest)
		[[ $downloads -gt 0 ]] && color='brightgreen' || color='red'
		local url="https://img.shields.io/static/v1?label=Downloads&message=${count}%2Fweek&color=${color}&logo=npm"
		link="https://www.npmjs.com/package/${repoInfo[npm]}"
		;;
	used_by)
		local alt="Dependent repos of ${repoInfo[name]}"
		link="https://github.com/${repoInfo[ownerName]}/network/dependents"
		local dependentsHtml=$(curl "${_curlArgs[@]}" "$link")
		local usedBy=$(echo "$dependentsHtml" | tr -d '[:space:]' | sed 's/.*type=REPOSITORY.*svg>\(.*\)Repositories.*/\1/' | tr -d ',' | numfmt --to=si --round=nearest)
		local url="https://img.shields.io/static/v1?label=Used%20by&message=${usedBy}&color=blue&logo=githubactions&logoColor=white"
		;;
	esac

	printf '[![%s](%s)](%s)' "$alt" "$url" "$link"
}

getContribution() {
	declare -n repoInfo="$1"

	repoInfo[contributionLink]="https://github.com/${info[ownerName]}/pulls?q=author:${_user}"
	repoInfo[contributionCount]=$(ghApi "/search/issues?q=repo:${repoInfo[ownerName]}+author:${_user}+is:pr&per_page=1" | jq --raw-output '.total_count')
}

yq --output-format json "${_scriptDir}/references.yaml" | jq --compact-output 'to_entries | .[]' | while read section; do
	title=$(echo "$section" | jq --raw-output '.key')
	printf '\n<details><summary><strong>%s</strong></summary>\n<p><ul>\n' "$title"

	main=$(echo "$section" | jq --compact-output '.value.main | to_entries | .[]')
	while read repo; do
		declare -A info=([ownerName]=$(echo "$repo" | jq --raw-output '.key'))
		getInfo info
		values=$(echo "$repo" | jq --compact-output '.value')
		badges=$(echo "$values" | jq --compact-output --raw-output '.badges | .[]?')
		info[npm]=$(echo "$values" | jq --raw-output --exit-status '.npm // empty' || printf "${info[name]}")

		printf '<table><tr><td width="500px">\n'
		printf '<p>\n\n<a href="%s">%s</a> / <a href="%s"><b>%s</b></a>\n' "https://github.com/${info[owner]}" "${info[owner]}" "https://github.com/${info[ownerName]}" "${info[name]}"

		if [[ $(echo "$section" | jq '.value.options.contribution') = 'true' ]]; then
			getContribution info
			printf '<br><sub>(contributed with <a href="%s">%i %s</a>)</sub>' "${info[contributionLink]}" "${info[contributionCount]}" "pull request$([ "${info[contributionCount]}" -ne 1 ] && echo s)"
		fi

		printf '\n</p>\n\n'
		printf '> %s\n\n' "${info[description]}"

		if [[ -n $badges ]]; then
			while read badge; do
				printf '%s\n' "$(getBadge info "$badge")"
			done <<<"$badges"
			printf '\n'
		fi

		printf '</td></tr></table>\n'
	done <<<"$main"

	more=$(echo "$section" | jq --compact-output '.value.more // [] | to_entries | .[]')
	if [[ -n $more ]]; then
		contribution=$(echo "$section" | jq '.value.options.contribution')
		moreEnriched='[]'
		while read repo; do
			declare -A info=([ownerName]="$(echo "$repo" | jq --raw-output '.value')")
			getInfo info
			if [[ $contribution = 'true' ]]; then
				getContribution info
			fi
			repoInfo=$(echo "$repo" | jq --compact-output '. + {info: {}}')
			for key in "${!info[@]}"; do
				repoInfo=$(echo "$repoInfo" | jq --compact-output --arg key "$key" --arg value "${info[$key]}" '.info += {($key): $value}')
			done
			moreEnriched=$(echo "$moreEnriched" | jq --compact-output --argjson repoInfo "$repoInfo" '. + [$repoInfo]')
		done <<<"$more"
		if [[ $contribution = 'true' ]]; then
			repos=$(echo "$moreEnriched" | jq --compact-output 'sort_by(.info.contributionCount | tonumber) | reverse | .[]')
		else
			repos=$(echo "$moreEnriched" | jq --compact-output '.[]')
		fi

		printf '<details><summary><strong>Show me more...</strong></summary>\n<p>\n'

		while read -r repo; do
			ownerName=$(echo "$repo" | jq --raw-output '.info.ownerName')
			owner=$(echo "$repo" | jq --raw-output '.info.owner')
			name=$(echo "$repo" | jq --raw-output '.info.name')
			description=$(echo "$repo" | jq --raw-output '.info.description')

			printf '\n<a href="%s">%s</a> / <a href="%s"><b>%s</b></a>' "https://github.com/${owner}" "$owner" "https://github.com/${ownerName}" "$name"

			if [[ $contribution = 'true' ]]; then
				contributionLink=$(echo "$repo" | jq --raw-output '.info.contributionLink')
				contributionCount=$(echo "$repo" | jq --raw-output '.info.contributionCount')
				printf ' <sup>(<a href="%s">%i&nbsp;%s</a>)</sup>' "$contributionLink" "$contributionCount" "pull request$([ "$contributionCount" -ne 1 ] && echo s)"
			fi

			printf '\n<br>%s\n' "$description"
		done <<<"$repos"

		printf '</p>\n</details>\n'
	fi

	printf '</ul></p>\n</details>\n'
done

printf '\n'
