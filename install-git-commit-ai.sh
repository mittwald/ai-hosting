#!/usr/bin/env bash
set -euo pipefail

HOOK_CONTENT='#!/usr/bin/env bash

MSG_FILE="${1}"
SOURCE="${2}"   # e.g. message, template, merge, commit, squash
SHA="${3}"

MAX_ATTEMPTS=3
TIMEOUT_SECONDS=5
TIMEOUT_INCREASE_PERCENT=50

COMMIT_MSG=""

case "${SOURCE}" in
  message|merge|squash|template|commit) exit 0 ;;
esac

if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN=timeout
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN=gtimeout
else
  TIMEOUT_BIN=""
fi

exitcode=0
attempts=0
success=0
while [ "${attempts}" -lt "${MAX_ATTEMPTS}" ]; do
  attempts=$((attempts + 1))
  echo "> Generating commit message ${attempts}/${MAX_ATTEMPTS} ..." >&2
  if [ -n "${TIMEOUT_BIN}" ]; then
    RUNNER=("${TIMEOUT_BIN}" "${TIMEOUT_SECONDS}")
  else
    RUNNER=()
  fi
  COMMIT_MSG="$("${RUNNER[@]}" cmai --message-only)"; exitcode=$?
  if [ "${exitcode}" -eq 0 ] && [ -n "${COMMIT_MSG}" ]; then
    success=1
    echo "> done" >&2; break
  elif [ "${exitcode}" -eq 124 ]; then
    TIMEOUT_SECONDS=$((TIMEOUT_SECONDS + ((TIMEOUT_SECONDS * TIMEOUT_INCREASE_PERCENT + 99) / 100)))
    echo "> Timeout occurred. Increasing timeout to ${TIMEOUT_SECONDS}s..." >&2
  else
    echo "> cmai failed (exit ${exitcode})" >&2; break
  fi
done
[ "${success}" -ne 1 ] && echo "> Failed to generate commit message" >&2 && exit 0

(printf '\''%s\n'\'' "${COMMIT_MSG}"; cat "${MSG_FILE}") > "${MSG_FILE}.tmp"
mv "${MSG_FILE}.tmp" "${MSG_FILE}"
exit 0
'

VIM_SNIPPET='" abort git commit when quitting with :q or :q!
augroup GitCommitAbort
  autocmd!
  autocmd FileType gitcommit cnoreabbrev <buffer> q! cq
  autocmd FileType gitcommit cnoreabbrev <buffer> q  cq
augroup END'

setup_colors() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_ITALIC=$'\033[3m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
    C_CODE=$'\033[95m'
  else
    C_RESET=''
    C_BOLD=''
    C_ITALIC=''
    C_DIM=''
    C_RED=''
    C_GREEN=''
    C_YELLOW=''
    C_BLUE=''
    C_CYAN=''
    C_CODE=''
  fi
}

setup_colors

code() {
  printf '%s%s%s' "${C_CODE}" "$1" "${C_RESET}"
}

dim_output() {
  sed "s/^/    ${C_DIM}/; s/\$/${C_RESET}/"
}

prompt_step() {
  local step="$1"
  local description="$2"
  local answer
  printf '\n%sStep %s:%s %s\n' "${C_BOLD}${C_CYAN}" "$step" "${C_RESET}" "$description"
  printf '\n  %sRun this step? [Y/n]:%s ' "${C_BOLD}${C_BLUE}" "${C_RESET}"
  read -r answer < /dev/tty || true
  [ -z "${answer:-}" ] && answer='y'
  case "${answer:-}" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

prompt_confirm() {
  local answer
  printf '\n  %sRun this step? [y/N]:%s ' "${C_BOLD}${C_BLUE}" "${C_RESET}"
  read -r answer < /dev/tty || true
  case "${answer:-}" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

is_vim_editor() {
  local editor="${1:-}"
  [ -z "$editor" ] && return 1
  case "$editor" in
    *vim*|*nvim*|*vi) return 0 ;;
    *) return 1 ;;
  esac
}

to_tilde_path() {
  local p="$1"
  if [ "$p" = "$HOME" ]; then
    printf '~'
  elif [ "${p#"$HOME"/}" != "$p" ]; then
    printf '~/%s' "${p#"$HOME"/}"
  else
    printf '%s' "$p"
  fi
}

resolve_template_dir() {
  local p="$1"
  case "$p" in
    "~") printf '%s\n' "${HOME}" ;;
    "~/"*) printf '%s/%s\n' "${HOME}" "${p#~/}" ;;
    *) printf '%s\n' "$p" ;;
  esac
}

prompt_template_dir() {
  local initial="$1"
  local input=''
  local resolved=''

  while true; do
    if [ -t 0 ] || [ -t 1 ]; then
      printf '  %sTemplate directory:%s ' "${C_BOLD}${C_BLUE}" "${C_RESET}"
      read -r -e -i "${initial}" input < /dev/tty || true
    else
      printf '  %sTemplate directory:%s %s\n' "${C_BOLD}${C_BLUE}" "${C_RESET}" "$(code "${initial}")"
      input="${initial}"
    fi

    [ -z "${input}" ] && input="${initial}"
    resolved="$(resolve_template_dir "${input}")"
    if [ "${resolved#/}" = "${resolved}" ]; then
      echo "  ${C_RED}ERROR:${C_RESET} template directory must be an absolute path."
      if [ -t 0 ] || [ -t 1 ]; then
        continue
      fi
      return 1
    fi

    template_dir="${resolved}"
    return 0
  done
}

if ! command -v uname >/dev/null 2>&1; then
  echo "${C_RED}ERROR:${C_RESET} uname is required but was not found in PATH. Aborting."
  exit 1
fi

if [ "$(uname -s)" != "Linux" ]; then
  echo "${C_RED}This installer only supports Linux. Aborting without changes.${C_RESET}"
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "${C_RED}ERROR:${C_RESET} git is required but was not found in PATH. Aborting."
  exit 1
fi

echo "${C_GREEN}Installer is running on Linux.${C_RESET}"
echo "${C_DIM}All changes will be shown before they are applied.${C_RESET}"

if command -v cmai >/dev/null 2>&1; then
  echo
  echo "${C_BOLD}${C_CYAN}Step 1:${C_RESET} Install $(code "cmai")"
  echo
  echo "  ${C_GREEN}$(code "cmai") is already installed.${C_RESET}"
else
  if prompt_step "1" "Install $(code "cmai")"; then
    if ! command -v mktemp >/dev/null 2>&1; then
      echo "  ${C_RED}ERROR:${C_RESET} mktemp is required to install $(code "cmai")."
      echo "  ${C_RED}Please install $(code "cmai") manually first. Aborting.${C_RESET}"
      exit 1
    fi

    install_tmp_dir="$(mktemp -d)"
    cmai_src_dir="${install_tmp_dir}/cmai"
    install_failed=0

    echo "  ${C_ITALIC}${C_BLUE}>${C_RESET}${C_ITALIC} $(code "git clone https://github.com/mrgoonie/cmai.git ${cmai_src_dir}")${C_RESET}"
    if ! git clone https://github.com/mrgoonie/cmai.git "${cmai_src_dir}" 2>&1 | dim_output; then
      install_failed=1
    fi

    if [ "${install_failed}" -eq 0 ]; then
      echo "  ${C_ITALIC}${C_BLUE}>${C_RESET}${C_ITALIC} $(code "cd ${cmai_src_dir}")${C_RESET}"
      echo "  ${C_ITALIC}${C_BLUE}>${C_RESET}${C_ITALIC} $(code "./install.sh")${C_RESET}"
      if ! (cd "${cmai_src_dir}" && ./install.sh 2>&1) | dim_output; then
        install_failed=1
      fi
    fi

    echo "  ${C_ITALIC}${C_BLUE}>${C_RESET}${C_ITALIC} Removing $(code "${install_tmp_dir}")${C_RESET}"
    rm -rf "${install_tmp_dir}"

    if [ "${install_failed}" -ne 0 ] || ! command -v cmai >/dev/null 2>&1; then
      echo "  ${C_RED}ERROR:${C_RESET} failed to install $(code "cmai")."
      echo "  ${C_RED}Please install it manually first and re-run this script. Aborting.${C_RESET}"
      exit 1
    fi

    echo "  ${C_GREEN}Done.${C_RESET}"
  else
    echo "  ${C_RED}Aborting.${C_RESET}"
    exit 1
  fi
fi

echo
echo "${C_BOLD}${C_CYAN}Step 2:${C_RESET} Configure API key for $(code "cmai")"
echo
cmai_api_key=''
if [ -n "${MITTWALD_AI_API_KEY:-}" ]; then
  echo "  ${C_GREEN}Found key in $(code "MITTWALD_AI_API_KEY").${C_RESET}"
  use_env_api_key='y'
  if [ -t 0 ] || [ -t 1 ]; then
    printf '  %sUse key from MITTWALD_AI_API_KEY [Y/n]:%s ' "${C_BOLD}${C_BLUE}" "${C_RESET}"
    read -r use_env_api_key < /dev/tty || true
    [ -z "${use_env_api_key:-}" ] && use_env_api_key='y'
  else
    printf '  %sUse key from MITTWALD_AI_API_KEY [Y/n]:%s Y\n' "${C_BOLD}${C_BLUE}" "${C_RESET}"
  fi
  case "${use_env_api_key:-}" in
    y|Y|yes|YES)
      cmai_api_key="${MITTWALD_AI_API_KEY}"
      ;;
    *)
      if [ -t 0 ] || [ -t 1 ]; then
        printf '  %sAPI key (optional):%s ' "${C_BOLD}${C_BLUE}" "${C_RESET}"
        read -r cmai_api_key < /dev/tty || true
      else
        printf '  %sAPI key (optional):%s\n' "${C_BOLD}${C_BLUE}" "${C_RESET}"
        cmai_api_key=''
      fi
      ;;
  esac
else
  if [ -t 0 ] || [ -t 1 ]; then
    printf '  %sAPI key (optional):%s ' "${C_BOLD}${C_BLUE}" "${C_RESET}"
    read -r cmai_api_key < /dev/tty || true
  else
    printf '  %sAPI key (optional):%s\n' "${C_BOLD}${C_BLUE}" "${C_RESET}"
    cmai_api_key=''
  fi
fi

if prompt_step "3" "Configure $(code "cmai") to use mittwald AI"; then
  cmai_cmd=(cmai --use-custom "https://llm.aihosting.mittwald.de/v1" --model "gpt-oss-120b")
  if [ -n "${cmai_api_key}" ]; then
    cmai_cmd+=(--api-key "${cmai_api_key}")
    preview_cmd='cmai --use-custom "https://llm.aihosting.mittwald.de/v1"
         --model      "gpt-oss-120b"
         --api-key    "<redacted>"
         --print-config'
    echo "  ${C_ITALIC}${C_BLUE}>${C_RESET}${C_ITALIC} $(code "${preview_cmd}")${C_RESET}"
  else
    echo "  ${C_YELLOW}No API key set. You can enter the API key later in ${C_CODE}cmai${C_RESET}${C_YELLOW} config.${C_RESET}"
    preview_cmd='cmai --use-custom "https://llm.aihosting.mittwald.de/v1"
         --model      "gpt-oss-120b"
         --print-config'
    echo "  ${C_ITALIC}${C_BLUE}>${C_RESET}${C_ITALIC} $(code "${preview_cmd}")${C_RESET}"
  fi
  cmai_cmd+=(--print-config)
  if ! "${cmai_cmd[@]}" 2>&1 | dim_output; then
    echo "  ${C_RED}ERROR:${C_RESET} failed to configure $(code "cmai"). Aborting."
    exit 1
  fi
  echo "  ${C_GREEN}Done.${C_RESET}"
else
  echo "  ${C_RED}Aborting.${C_RESET}"
  exit 1
fi

existing_template_dir="$(git config --global --get init.templatedir || true)"
echo
echo "${C_BOLD}${C_CYAN}Step 4:${C_RESET} Configure template directory"
echo
if [ -n "${existing_template_dir}" ]; then
  default_template_dir="${existing_template_dir}"
  use_configured_template_dir='y'
  printf '  %sTemplate directory:%s %s\n' "${C_BOLD}" "${C_RESET}" "$(code "${default_template_dir}")"
  if [ -t 0 ] || [ -t 1 ]; then
    printf '  %sUse configured directory [Y/n]:%s ' "${C_BOLD}${C_BLUE}" "${C_RESET}"
    read -r use_configured_template_dir < /dev/tty || true
    [ -z "${use_configured_template_dir:-}" ] && use_configured_template_dir='y'
  else
    printf '  %sUse configured directory [Y/n]:%s Y\n' "${C_BOLD}${C_BLUE}" "${C_RESET}"
  fi
  case "${use_configured_template_dir}" in
    y|Y|yes|YES)
      resolved_default_template_dir="$(resolve_template_dir "${default_template_dir}")"
      if [ "${resolved_default_template_dir#/}" = "${resolved_default_template_dir}" ]; then
        echo "  ${C_RED}ERROR:${C_RESET} configured template directory must be an absolute path."
        if ! prompt_template_dir "${HOME}/.git-templates"; then
          echo "  ${C_RED}Aborting.${C_RESET}"
          exit 1
        fi
        echo
        echo "  ${C_YELLOW}${C_BOLD}WARNING:${C_RESET}${C_YELLOW} template directory is not configured globally.${C_RESET}"
        echo "  ${C_YELLOW}The template will not be found automatically.${C_RESET}"
      else
        template_dir="${resolved_default_template_dir}"
      fi
      ;;
    *)
      if ! prompt_template_dir "${default_template_dir}"; then
        echo "  ${C_RED}Aborting.${C_RESET}"
        exit 1
      fi
      if [ "${template_dir}" != "${existing_template_dir}" ]; then
          echo
          echo "  ${C_YELLOW}${C_BOLD}WARNING:${C_RESET}${C_YELLOW} template directory is not configured globally.${C_RESET}"
          echo "  ${C_YELLOW}The template will not be found automatically.${C_RESET}"
      fi
      ;;
  esac
else
  default_template_dir="${HOME}/.git-templates"
  if ! prompt_template_dir "${default_template_dir}"; then
    echo "  ${C_RED}Aborting.${C_RESET}"
    exit 1
  fi
fi

if [ -z "${template_dir:-}" ]; then
  template_dir="${default_template_dir}"
fi

template_dir="$(resolve_template_dir "${template_dir}")"

HOOK_DIR="${template_dir}/hooks"
HOOK_PATH="${HOOK_DIR}/prepare-commit-msg"
DISPLAY_TEMPLATE_DIR="$(to_tilde_path "${template_dir}")"
DISPLAY_HOOK_PATH="${DISPLAY_TEMPLATE_DIR}/hooks/prepare-commit-msg"
DISPLAY_VIMRC='~/.vimrc'

if [ -z "${existing_template_dir}" ]; then
  echo "  ${C_ITALIC}${C_BLUE}>${C_RESET}${C_ITALIC} Creating $(code "${template_dir}")${C_RESET}"
  if ! mkdir -p "${template_dir}"; then
    echo "  ${C_RED}ERROR:${C_RESET} failed to create $(code "${template_dir}"). Aborting."
    exit 1
  fi
  echo "  ${C_ITALIC}${C_BLUE}>${C_RESET}${C_ITALIC} $(code "git config --global init.templatedir '${template_dir}'")${C_RESET}"
  git config --global init.templatedir "${template_dir}"
fi

if [ -f "${HOOK_PATH}" ]; then
  printf '\n%sStep %s:%s %s\n' "${C_BOLD}${C_CYAN}" "5" "${C_RESET}" "Write $(code "${DISPLAY_HOOK_PATH}")"
  echo
  echo "  ${C_YELLOW}${C_BOLD}WARNING:${C_RESET}${C_YELLOW} ${C_CODE}${HOOK_PATH}${C_RESET}${C_YELLOW} already exists.${C_RESET}"
  printf '\n  %sOverwrite? [Y/n]:%s ' "${C_BOLD}${C_BLUE}" "${C_RESET}"
  read -r overwrite_answer < /dev/tty || true
  [ -z "${overwrite_answer:-}" ] && overwrite_answer='y'
  case "${overwrite_answer:-}" in
    y|Y|yes|YES)
      mkdir -p "${HOOK_DIR}"
      echo "  ${C_ITALIC}${C_BLUE}>${C_RESET}${C_ITALIC} Installing $(code "${HOOK_PATH}")${C_RESET}"
      printf '%s\n' "${HOOK_CONTENT}" > "${HOOK_PATH}"
      chmod +x "${HOOK_PATH}"
      echo "  ${C_GREEN}Done.${C_RESET}"
      ;;
    *)
      echo "  ${C_RED}Aborting.${C_RESET}"
      exit 1
      ;;
  esac
else
  if prompt_step "5" "Write $(code "${DISPLAY_HOOK_PATH}")"; then
    mkdir -p "${HOOK_DIR}"
    echo "  ${C_ITALIC}${C_BLUE}>${C_RESET}${C_ITALIC} Installing $(code "${HOOK_PATH}")${C_RESET}"
    printf '%s\n' "${HOOK_CONTENT}" > "${HOOK_PATH}"
    chmod +x "${HOOK_PATH}"
    echo "  ${C_GREEN}Done.${C_RESET}"
  else
    echo "  ${C_RED}Aborting.${C_RESET}"
    exit 1
  fi
fi

editor_value="${EDITOR:-}"
if [ -z "${editor_value}" ]; then
  editor_value="$(git config --global core.editor || true)"
fi

if is_vim_editor "${editor_value}"; then
  echo
  echo "${C_BOLD}${C_CYAN}Step 6:${C_RESET} Append snippet to $(code "${DISPLAY_VIMRC}") to abort commit on :q! (only for Vim users)"
  echo
  echo "  Will append the following to $(code "${HOME}/.vimrc"):"
  echo
  while IFS= read -r line; do
    printf '  %s%s%s%s\n' "${C_ITALIC}" "${C_CODE}" "$line" "${C_RESET}"
  done <<< "${VIM_SNIPPET}"
  echo
  echo "  ${C_YELLOW}${C_BOLD}INFO:${C_RESET}${C_YELLOW} This helps prevent accidentally committing a generated message.${C_RESET}"
  if prompt_confirm; then
    vimrc_path="${HOME}/.vimrc"
    if [ ! -f "${vimrc_path}" ]; then
      echo "  ${C_ITALIC}${C_BLUE}>${C_RESET}${C_ITALIC} Creating $(code "${vimrc_path}")${C_RESET}"
      touch "${vimrc_path}"
    fi
    if grep -q 'augroup GitCommitAbort' "${vimrc_path}"; then
      echo "  ${C_YELLOW}Snippet already present in $(code "${vimrc_path}"); no change made.${C_RESET}"
    else
      echo "  ${C_ITALIC}${C_BLUE}>${C_RESET}${C_ITALIC} Appending snippet to $(code "${vimrc_path}")${C_RESET}"
      printf '%s\n' "${VIM_SNIPPET}" >> "${vimrc_path}"
      echo "  ${C_GREEN}Done.${C_RESET}"
    fi
  else
    echo "  ${C_YELLOW}Skipped by user.${C_RESET}"
  fi
else
  echo
  echo "  ${C_YELLOW}Editor does not look like Vim (${C_CODE}EDITOR${C_RESET}${C_YELLOW}/${C_CODE}core.editor=${editor_value:-unset}${C_RESET}${C_YELLOW}).${C_RESET}"
  echo
  echo "  ${C_YELLOW}${C_BOLD}BE CAREFUL when using other editors:${C_RESET}"
  echo "  ${C_YELLOW}IF you intent to abort the commit, first comment out the${C_RESET}"
  echo "  ${C_YELLOW}generated commit message, otherwise the commit WILL proceed.${C_RESET}"
fi

echo
echo "${C_BOLD}${C_CYAN}Step 7:${C_RESET} Manual action required"
echo
echo "  ${C_BOLD}Run $(code "git init") in each repository where you want this hook template to apply.${C_RESET}"
echo
