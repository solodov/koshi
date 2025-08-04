#!/usr/bin/env bash
#
# @flag -d --debug Turn on debug mode
# @option -c --config=$HOME/.config/koshi/config.json <CONFIG>  Path to the config file.
#
# @describe
# Koshi: Give your JJ projects a powerful lift

set -uo pipefail

for dep in jj argc gum aichat gh; do
  if ! command -v "$dep" &>/dev/null; then
    echo "Error: Required dependency '$dep' is not installed or not in PATH." >&2
    exit 1
  fi
done

# @cmd Generate and refine Jujutsu commit descriptions with AI
# @alias ad
#
# @option -r --role <ROLE> Role to use for making description.
# @option -t --ticket <TICKET> Ticket this commit is related to.
# @flag -c --commit Commit in addition to creating the description.
# @flag -p --pull_request Create a pull request.
#
# @describe
#
# Uses a conversational AI to generate and iteratively refine commit
# descriptions for your current Jujutsu commit. AI suggestions are provided
# based on your diffs, and you may interactively improve the description or
# accept as-is.
#
# The tool will:
# • Refuse to proceed if the commit is empty
# • Generate an initial commit description using the diff and an AI assistant
# • Allow you to suggest refinements interactively, or accept the current
#   suggestion
# • Apply the final description to the commit
# • Optionally, ask if you want to hand-edit or create a new commit
#
# WORKFLOW:
# 1. Ensure current commit (@) is not empty
# 2. Generate a proposed commit description using the AI assistant
# 3. Optionally refine the suggestion by entering feedback
# 4. Write the description with 'jj desc'
# 5. Optionally edit the description manually
# 6. Optionally commit the change (with --commit or -c)
# 7. Optionally create/update a pull request (with --pull-request or -p)
#
function ai-desc() {
  [[ -v argc_debug ]] && set -x

  assert_jj_repo
  assert_non_empty_commit

  local role
  if [[ -v argc_role ]]; then
    role="$argc_role"
  else
    role="$(ai_description_role "$PWD")"
    local ret=$?
    (( $ret != 0 )) && exit $ret
  fi

  jj diff --stat
  echo

  local prompt='write description for this change'
  if [[ -v argc_ticket ]]; then
    prompt="$prompt. this change is related to ticket $argc_ticket."
  fi

  local current_description="$(get_description)"
  if [[ -n "$current_description" ]]; then
    prompt="$prompt\n\ncurrent change description:\n$current_description"
  fi

  local description="$(chat 'generating description' $role --empty-session --file='`jj diff --git`' "$prompt")"
  while true; do
    echo -e 'commit description:\n'
    gum format <<< "$description"
    echo
    prompt="$(gum input --placeholder='suggest refinements, empty input to accept')"
    (( $? == 130 )) && exit 130
    [[ -z "$prompt" ]] && break
    description="$(chat 'updating description' $role "$prompt")"
  done

  jj desc --quiet --stdin <<< "$description"

  # This might be useful in some circumstances, but so far it hasn't been very
  # useful. Disabling to simplify the workflow.
  # if confirm 'edit description?' --default=No; then
  #   jj desc
  #   echo
  # fi

  if [[ -v argc_pull_request ]]; then
    create_or_update_pull_request
  fi

  if [[ -v argc_commit ]]; then
    jj new --quiet
  fi
}

# @cmd Create and update GitHub pull requests from Jujutsu commits
#
# @describe
# Integrates Jujutsu with GitHub pull requests, providing a streamlined workflow
# for creating and updating PRs from jj-managed repositories.
#
# The tool will:
# • Validate that the current commit (@) is not empty
# • Open an editor to update the commit description (includes PR template for
#   new PRs)
# • Push the current commit to GitHub using 'jj git push'
# • Create or update a GitHub PR based on the commit
#
# The PR base branch is automatically determined by finding the latest ancestor
# with a bookmark. The first line of the commit description becomes the PR
# title.
#
function pr() {
  [[ -v argc_debug ]] && set -x

  assert_jj_repo
  assert_non_empty_commit
  assert_gh_is_logged_in

  echo -e 'commit description:\n'
  get_description | gum format
  echo
  if confirm 'edit description?' --default=No; then
    jj desc
    echo
  fi

  create_or_update_pull_request
}

# Prompt the user for confirmation using gum.
# Returns 0 for yes, 1 for no, and exits with 130 on interrupt (Ctrl-C).
function confirm() {
  gum confirm "$@"
  case $? in
    0)
      return 0
      ;;
    1)
      return 1
      ;;
    130)
      exit 130
      ;;
  esac
}

# Retrieves the current bookmark for the working commit. If none exists,
# creates a new bookmark using the template from jj config and returns its name.
function get_bookmark() {
  local bookmark="$(jj log --color never --no-graph -T bookmarks -r @ | sed -e 's/\*//')"
  if [[ -z "$bookmark" ]]; then
    bookmark="$(jj log --color never --no-graph -T "$(jj config get templates.git_push_bookmark)" -r @)"
    gum log -l info "creating new bookmark $bookmark"
    jj bookmark create "$bookmark" -r @ --quiet
  else
    gum log -l info "using existing bookmark $bookmark"
  fi
  echo "$bookmark"
}

# Returns the name of the most recent ancestor commit with a bookmark.
function get_parent() {
  jj log \
     --color never \
     --no-graph \
     --limit 1 \
     -T bookmarks \
     -r 'latest(ancestors(@-) & bookmarks())'
}

# Returns the commit description of the current (working) commit.
function get_description() {
  jj log --no-graph -T description -r @
}

# Starts an aichat session with the given title and role.
# All additional arguments are forwarded to aichat.
function chat() {
  local title="$1"; shift
  local role="$1"; shift
  gum spin --title="$title" -- \
      aichat --session="$role" --save-session --role="$role" "$@"
}

# Checks that the current directory is a jj repository; exits with error if not.
function assert_jj_repo() {
  if ! jj root &> /dev/null; then
    gum log -l error 'must be used inside jj repo'
    exit 1
  fi
}

# Checks that current commit has changes; exits when commit is empty.
function assert_non_empty_commit() {
  [[ "$(jj log -r @ --no-graph -T empty)" == 'true' ]] && exit 0
}

# Checks that commit description has at least 3 lines; exits with error if not.
function assert_non_empty_description() {
  if (( $(get_description | wc -l) < 3 )); then
    gum log -l error 'description must have at lest 3 lines'
    exit 1
  fi
}

# Checks that GitHub CLI is authorized; exits with error if not.
function assert_gh_is_logged_in() {
  if ! gh auth status &> /dev/null; then
    gum log -l error 'gh is not authorized, run "gh auth login"'
    exit 1
  fi
}

# Creates a new pull request or updates the existing one for the current
# bookmark.
function create_or_update_pull_request() {
  assert_gh_is_logged_in
  assert_non_empty_description

  # Bookmark is fetched before push so that new/existing bookmark state can be
  # determined sinse 'jj git push' will create a new bookmark.
  local bookmark="$(get_bookmark)"

  # Before pull request can be created a commit must be pushed to github.
  gum spin --title='pushing bookmark' -- jj git push -c @ --quiet
  echo

  local parent="$(get_parent)"
  local pr="$(gh pr list -H "$bookmark" --json number | jq -r '.[0].number')"
  if [[ "$pr" == 'null' ]]; then
    local reviewers=()
    for i in $(select_pull_request_reviewers ''); do
      reviewers+=('--reviewer' "$i")
    done
    if confirm 'create pr?' --default=No; then
      gum log -l info "creating new pull request with parent $parent"
      echo
      gh pr create \
         --base "$parent" \
         --head "$bookmark" \
         ${reviewers[@]} \
         --title "$(get_description | head -n 1)" \
         --body-file - < <(get_description | tail -n +3)
      echo
    fi
  elif confirm 'update pr?' --default=Yes; then
    gum log -l info "updating pull request $pr for branch $bookmark"
    echo
    gh pr edit "$pr" \
       --base "$parent" \
       --title "$(get_description | head -n 1)" \
       --body-file - < <(get_description | tail -n +3)
    echo
    update_pull_request_reviewers "$pr"
  fi
}

# Adds reviewers selected by the user from a list merging config and current PR
# reviewers.
function set_pull_request_reviewers() {
  local pr="$1"; shift
  local add=()
  for i in $(select_pull_request_reviewers "$pr"); do
    add+=('--add-reviewer' "$i")
  done
  if (( ${#add[*]} > 0 )); then
    gh pr edit "$pr" ${add[@]} > /dev/null
  fi
}

# Synchronizes PR reviewers to match user selection from a merged config and
# current list.
function update_pull_request_reviewers() {
  local pr="$1"; shift
  local sel=($(select_pull_request_reviewers "$pr"))
  local cur=($(gh pr view "$pr" --json reviewRequests --jq '.reviewRequests[].login'))
  local remove=()
  for i in $(set_diff "${cur[*]}" "${sel[*]}"); do
    remove+=('--remove-reviewer' "$i")
  done
  if (( ${#remove[*]} > 0 )); then
    gum spin --title='removing reviewers' -- \
        gh pr edit "$pr" ${remove[@]} > /dev/null
  fi
  local add=()
  for i in $(set_diff "${sel[*]}" "${cur[*]}"); do
    add+=('--add-reviewer' "$i")
  done
  if (( ${#add[*]} > 0 )); then
    gum spin --title='adding reviewers' -- \
        gh pr edit "$pr" ${add[@]} > /dev/null
  fi
}

# Prompts the user to select reviewers from a merged list of config and current
# PR reviewers.
function select_pull_request_reviewers() {
  local pr="$1"; shift
  local all=($(jq -r --arg pwd "${PWD/#$HOME/\$HOME}" '(.project_settings[$pwd].reviewers // [])[]' "$(config)"))

  local cur=()
  if [[ -n "$pr" ]]; then
    cur=($(gh pr view "$pr" --json reviewRequests --jq '.reviewRequests[].login'))
    all=($(set_union "${all[*]}" "${cur[*]}"))
  fi
  if (( ${#all[*]} == 0 )); then
    gum log -l warn 'unable to determine pull request reviewers'
    echo >&2
    return 0
  fi
  gum choose \
      --header='select reviewers:' \
      --ordered \
      --limit=3 \
      --height=${#all[*]} \
      --selected="$(echo ${cur[*]} | tr ' ' ,)" ${all[@]}
  # This is Ctrl-C
  (( $? == 130 )) && exit 130
}

# Determines the AI description role for a given directory path.
# Looks up the role in the config file, first checking for a project-specific
# role at .project_settings[$pwd].ai_description_role, then falling back to the
# top-level .ai_description_role if not found. Returns 1 if no role is
# configured.
function ai_description_role() {
  local pwd="${1/#$HOME/\$HOME}"
  local role="$(cat "$(config)" | jq -r --arg pwd "$pwd" '
    # First try to get project-specific role
    if .project_settings[$pwd].ai_description_role then
      .project_settings[$pwd].ai_description_role
    # Fall back to top-level ai_description_role
    elif .ai_description_role then
      .ai_description_role
    else
      null
    end')"
  if [[ -z "$role" ]]; then
    echo "Cannot determine AI description role for '$pwd'" >&2
    return 1
  fi
  echo "$role"
}

# Returns the expanded config file path from the --config option.
# Expands $HOME in the path and exits with error if the file doesn't exist.
function config() {
  local p="${argc_config/\$HOME/$HOME}"
  if [[ ! -f "$p" ]]; then
    echo "Config file '$p' is not found" >&2
    exit 1
  fi
  echo "$p"
}

# Prints the union of two sets; elements cannot contain spaces.
function set_union() {
  declare -A seen
  for i in $1 $2; do
    seen["$i"]=1
  done
  local merged=("${!seen[@]}")
  printf "%s\n" "${merged[@]}"
}

# Prints elements in the first set that are not in the second; elements cannot
# contain spaces.
function set_diff() {
  declare -A in2
  for i in $2; do
    in2["$i"]=1
  done
  local diff=()
  for i in $1; do
    [[ ${in2["$i"]+_} ]] || diff+=("$i")
  done
  printf "%s\n" "${diff[@]}"
}

eval "$(argc --argc-eval "$0" "$@")"
