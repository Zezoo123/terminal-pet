#!/bin/bash
# GitHub traffic for this repo (owner-only data, last 14 days). Needs `gh auth login`.
set -e
repo=${1:-Zezoo123/terminal-pet}
printf 'stars      %s\n' "$(gh api "repos/$repo" --jq .stargazers_count)"
printf 'views      %s\n' "$(gh api "repos/$repo/traffic/views" --jq '"\(.count) (\(.uniques) unique)"')"
printf 'clones     %s   (CI and Homebrew installs count here)\n' "$(gh api "repos/$repo/traffic/clones" --jq '"\(.count) (\(.uniques) unique)"')"
echo 'referrers'
gh api "repos/$repo/traffic/popular/referrers" --jq '.[] | "  \(.referrer)\t\(.count) views, \(.uniques) unique"' | column -t -s $'\t'
echo 'views by day'
gh api "repos/$repo/traffic/views" --jq '.views[] | "  \(.timestamp[:10])\t\(.count) views, \(.uniques) unique"' | column -t -s $'\t'
