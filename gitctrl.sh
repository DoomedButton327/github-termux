#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════╗
# ║   GITCTRL — GitHub CLI for Termux                ║
# ║   Mirrors the GITCTRL mobile app in terminal     ║
# ╚══════════════════════════════════════════════════╝
# Requires: curl, jq, nano (or vi)
# Install deps: pkg install curl jq nano

# ─── COLORS (Deep Space Dev) ────────────────────────
C_RESET='\033[0m'
C_CYAN='\033[0;96m'
C_CYAN_B='\033[1;96m'
C_PURPLE='\033[0;35m'
C_PURPLE_B='\033[1;35m'
C_GREEN='\033[0;92m'
C_GREEN_B='\033[1;92m'
C_RED='\033[0;91m'
C_YELLOW='\033[0;93m'
C_ORANGE='\033[38;5;208m'
C_DIM='\033[0;90m'
C_BOLD='\033[1m'
C_UNDERLINE='\033[4m'

# ─── CONFIG ─────────────────────────────────────────
CONFIG_DIR="$HOME/.gitctrl"
CONFIG_FILE="$CONFIG_DIR/config"
TEMP_FILE="$CONFIG_DIR/.tmpfile"
GH_API="https://api.github.com"

# ─── STATE ──────────────────────────────────────────
TOKEN=""
GH_USER=""
CURRENT_REPO=""        # owner/repo
CURRENT_REPO_NAME=""
CURRENT_BRANCH="main"
REPO_DEFAULT_BRANCH="main"

# ═══════════════════════════════════════════════════
#  UTILS
# ═══════════════════════════════════════════════════
header() {
  clear
  echo -e "${C_CYAN_B}"
  printf "  ╔════════════════════════════════════╗\n"
  printf "  ║   GIT%sCTRL%s  //  Repository Control   ║\n" "$C_PURPLE_B" "$C_CYAN_B"
  printf "  ╚════════════════════════════════════╝%s\n" "$C_RESET"
  if [ -n "$GH_USER" ]; then
    printf "  %suser:%s %s%s%s  %srepo:%s %s%s%s  %sbranch:%s %s%s%s\n" \
      "$C_DIM" "$C_RESET" "$C_GREEN" "$GH_USER" "$C_RESET" \
      "$C_DIM" "$C_RESET" "$C_CYAN" "${CURRENT_REPO_NAME:-none}" "$C_RESET" \
      "$C_DIM" "$C_RESET" "$C_PURPLE" "$CURRENT_BRANCH" "$C_RESET"
  fi
  printf "  %s────────────────────────────────────%s\n" "$C_DIM" "$C_RESET"
  echo ""
}

info()    { echo -e "  ${C_CYAN}◈ $1${C_RESET}"; }
success() { echo -e "  ${C_GREEN}✓ $1${C_RESET}"; }
warn()    { echo -e "  ${C_YELLOW}⚠ $1${C_RESET}"; }
error()   { echo -e "  ${C_RED}✕ $1${C_RESET}"; }
dim()     { echo -e "  ${C_DIM}$1${C_RESET}"; }

prompt() {
  echo -en "  ${C_CYAN}▸${C_RESET} $1: "
}

menu_item() {
  # $1=number, $2=icon, $3=label, $4=color
  local col="${4:-$C_CYAN}"
  printf "  ${C_DIM}[${C_RESET}${col}%-2s${C_DIM}]${C_RESET} %s  %s\n" "$1" "$2" "$3"
}

divider() {
  echo -e "  ${C_DIM}────────────────────────────────────${C_RESET}"
}

press_enter() {
  echo ""
  echo -en "  ${C_DIM}Press Enter to continue…${C_RESET}"
  read -r
}

# ─── GitHub API helpers ──────────────────────────────
gh_get() {
  curl -s -H "Authorization: Bearer $TOKEN" \
       -H "Accept: application/vnd.github+json" \
       -H "X-GitHub-Api-Version: 2022-11-28" \
       "$GH_API$1"
}

gh_post() {
  # $1=path, $2=json body
  curl -s -X POST \
       -H "Authorization: Bearer $TOKEN" \
       -H "Accept: application/vnd.github+json" \
       -H "X-GitHub-Api-Version: 2022-11-28" \
       -H "Content-Type: application/json" \
       -d "$2" \
       "$GH_API$1"
}

gh_put() {
  # $1=path, $2=json body
  curl -s -X PUT \
       -H "Authorization: Bearer $TOKEN" \
       -H "Accept: application/vnd.github+json" \
       -H "X-GitHub-Api-Version: 2022-11-28" \
       -H "Content-Type: application/json" \
       -d "$2" \
       "$GH_API$1"
}

gh_delete() {
  # $1=path, $2=json body
  curl -s -X DELETE \
       -H "Authorization: Bearer $TOKEN" \
       -H "Accept: application/vnd.github+json" \
       -H "X-GitHub-Api-Version: 2022-11-28" \
       -H "Content-Type: application/json" \
       -d "$2" \
       "$GH_API$1"
}

gh_patch() {
  # $1=path, $2=json body
  curl -s -X PATCH \
       -H "Authorization: Bearer $TOKEN" \
       -H "Accept: application/vnd.github+json" \
       -H "X-GitHub-Api-Version: 2022-11-28" \
       -H "Content-Type: application/json" \
       -d "$2" \
       "$GH_API$1"
}

api_error() {
  # Check if response JSON has a message field (GitHub error)
  echo "$1" | jq -r '.message // empty' 2>/dev/null
}

# ─── Base64 encode/decode ───────────────────────────
b64_encode() { echo -n "$1" | base64 | tr -d '\n'; }
b64_decode() { echo "$1" | base64 -d 2>/dev/null; }

# ═══════════════════════════════════════════════════
#  AUTH
# ═══════════════════════════════════════════════════
setup_config() {
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
}

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    TOKEN="$GITCTRL_TOKEN"
    return 0
  fi
  return 1
}

save_config() {
  echo "GITCTRL_TOKEN=\"$TOKEN\"" > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

delete_config() {
  rm -f "$CONFIG_FILE"
  TOKEN=""
  GH_USER=""
  CURRENT_REPO=""
  CURRENT_REPO_NAME=""
}

auth_screen() {
  header
  echo -e "  ${C_CYAN_B}// AUTHENTICATION${C_RESET}"
  echo ""
  echo -e "  You need a GitHub Personal Access Token (PAT)"
  echo -e "  with ${C_CYAN}repo${C_RESET} scope."
  echo ""
  dim "Generate one at: github.com/settings/tokens/new"
  echo ""
  prompt "Paste your token (ghp_...)"
  read -rs TOKEN
  echo ""

  if [ -z "$TOKEN" ]; then
    error "No token entered."
    exit 1
  fi

  info "Connecting to GitHub…"
  local resp
  resp=$(gh_get "/user")
  local msg
  msg=$(api_error "$resp")

  if [ -n "$msg" ]; then
    error "Auth failed: $msg"
    TOKEN=""
    press_enter
    return 1
  fi

  GH_USER=$(echo "$resp" | jq -r '.login')
  save_config
  success "Connected as ${C_GREEN_B}$GH_USER${C_RESET}"
  press_enter
  return 0
}

verify_auth() {
  info "Verifying token…"
  local resp
  resp=$(gh_get "/user")
  local msg
  msg=$(api_error "$resp")
  if [ -n "$msg" ]; then
    error "Token invalid or expired: $msg"
    return 1
  fi
  GH_USER=$(echo "$resp" | jq -r '.login')
  return 0
}

logout() {
  echo ""
  warn "This will delete your saved token."
  prompt "Are you sure? (y/N)"
  read -r confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    delete_config
    success "Logged out."
    press_enter
    main
  fi
}

# ═══════════════════════════════════════════════════
#  REPOS
# ═══════════════════════════════════════════════════
list_repos() {
  header
  echo -e "  ${C_CYAN_B}// MY REPOSITORIES${C_RESET}"
  echo ""
  info "Loading repositories…"

  local page=1
  local all_repos="[]"
  while true; do
    local batch
    batch=$(gh_get "/user/repos?per_page=100&page=$page&sort=pushed")
    local count
    count=$(echo "$batch" | jq 'length')
    if [ "$count" -eq 0 ]; then break; fi
    all_repos=$(echo "$all_repos $batch" | jq -s 'add')
    page=$((page+1))
    if [ "$count" -lt 100 ]; then break; fi
  done

  local total
  total=$(echo "$all_repos" | jq 'length')
  header
  echo -e "  ${C_CYAN_B}// MY REPOSITORIES${C_RESET}  ${C_DIM}(${total} total)${C_RESET}"
  echo ""

  # Print numbered repo list
  local i=1
  while IFS= read -r line; do
    local name visibility lang
    name=$(echo "$line" | jq -r '.name')
    visibility=$(echo "$line" | jq -r 'if .private then "PRIVATE" else "PUBLIC" end')
    lang=$(echo "$line" | jq -r '.language // ""')
    local vcol="${C_GREEN}"
    [ "$visibility" = "PRIVATE" ] && vcol="${C_PURPLE}"
    printf "  ${C_DIM}[${C_RESET}${C_CYAN}%-3s${C_DIM}]${C_RESET} %-35s ${vcol}%-8s${C_RESET} ${C_DIM}%s${C_RESET}\n" \
      "$i" "$name" "$visibility" "$lang"
    i=$((i+1))
  done < <(echo "$all_repos" | jq -c '.[]')

  echo ""
  divider
  menu_item "n" "📦" "New Repository" "$C_CYAN"
  menu_item "q" "←" "Back" "$C_DIM"
  divider
  echo ""
  prompt "Select repo number or action"
  read -r choice

  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    local idx=$((choice-1))
    local repo_json
    repo_json=$(echo "$all_repos" | jq -c ".[$idx]")
    if [ "$repo_json" = "null" ] || [ -z "$repo_json" ]; then
      error "Invalid selection."
      press_enter
      list_repos
      return
    fi
    CURRENT_REPO=$(echo "$repo_json" | jq -r '.full_name')
    CURRENT_REPO_NAME=$(echo "$repo_json" | jq -r '.name')
    REPO_DEFAULT_BRANCH=$(echo "$repo_json" | jq -r '.default_branch')
    CURRENT_BRANCH="$REPO_DEFAULT_BRANCH"
    success "Selected: $CURRENT_REPO  [$CURRENT_BRANCH]"
    press_enter
    repo_menu
  elif [ "$choice" = "n" ]; then
    create_repo
  elif [ "$choice" = "q" ]; then
    main_menu
  else
    error "Invalid choice."
    press_enter
    list_repos
  fi
}

# ═══════════════════════════════════════════════════
#  CREATE REPO
# ═══════════════════════════════════════════════════
create_repo() {
  header
  echo -e "  ${C_CYAN_B}// NEW REPOSITORY${C_RESET}"
  echo ""
  prompt "Repository name"
  read -r repo_name
  [ -z "$repo_name" ] && { warn "Cancelled."; press_enter; list_repos; return; }

  prompt "Description (optional)"
  read -r repo_desc

  prompt "Private? (y/N)"
  read -r is_priv
  local priv="false"
  [[ "$is_priv" =~ ^[Yy]$ ]] && priv="true"

  prompt "Add README? (Y/n)"
  read -r add_readme
  local readme="true"
  [[ "$add_readme" =~ ^[Nn]$ ]] && readme="false"

  echo ""
  info "Creating repository…"
  local body
  body=$(jq -n \
    --arg n "$repo_name" \
    --arg d "$repo_desc" \
    --argjson p "$priv" \
    --argjson r "$readme" \
    '{name:$n, description:$d, private:$p, auto_init:$r}')

  local resp
  resp=$(gh_post "/user/repos" "$body")
  local msg
  msg=$(api_error "$resp")
  if [ -n "$msg" ]; then
    error "Failed: $msg"
    press_enter
    list_repos
    return
  fi

  CURRENT_REPO=$(echo "$resp" | jq -r '.full_name')
  CURRENT_REPO_NAME=$(echo "$resp" | jq -r '.name')
  REPO_DEFAULT_BRANCH=$(echo "$resp" | jq -r '.default_branch')
  CURRENT_BRANCH="$REPO_DEFAULT_BRANCH"
  success "Created: $CURRENT_REPO"
  press_enter
  repo_menu
}

# ═══════════════════════════════════════════════════
#  REPO MENU
# ═══════════════════════════════════════════════════
repo_menu() {
  header
  echo -e "  ${C_CYAN_B}// REPO: ${C_PURPLE_B}$CURRENT_REPO${C_RESET}"
  echo ""
  menu_item "1" "📁" "Browse Files" "$C_CYAN"
  menu_item "2" "⎇ " "Branches" "$C_PURPLE"
  menu_item "3" "🕓" "Commit History" "$C_GREEN"
  menu_item "4" "ℹ " "Repo Info" "$C_YELLOW"
  menu_item "5" "📋" "List Repos" "$C_DIM"
  menu_item "q" "←" "Main Menu" "$C_DIM"
  echo ""
  prompt "Choice"
  read -r choice
  case "$choice" in
    1) browse_files "" ;;
    2) manage_branches ;;
    3) view_commits ;;
    4) repo_info ;;
    5) list_repos ;;
    q) main_menu ;;
    *) repo_menu ;;
  esac
}

# ═══════════════════════════════════════════════════
#  REPO INFO
# ═══════════════════════════════════════════════════
repo_info() {
  header
  echo -e "  ${C_CYAN_B}// REPO INFO${C_RESET}"
  echo ""
  info "Loading info…"

  local resp
  resp=$(gh_get "/repos/$CURRENT_REPO")
  local msg
  msg=$(api_error "$resp")
  if [ -n "$msg" ]; then
    error "$msg"; press_enter; repo_menu; return
  fi

  local stars forks size lang vis default_br desc
  stars=$(echo "$resp" | jq -r '.stargazers_count')
  forks=$(echo "$resp" | jq -r '.forks_count')
  size=$(echo "$resp" | jq -r '.size')
  lang=$(echo "$resp" | jq -r '.language // "N/A"')
  vis=$(echo "$resp" | jq -r 'if .private then "PRIVATE" else "PUBLIC" end')
  default_br=$(echo "$resp" | jq -r '.default_branch')
  desc=$(echo "$resp" | jq -r '.description // "(no description)"')

  header
  echo -e "  ${C_CYAN_B}// REPO INFO${C_RESET}"
  echo ""
  echo -e "  ${C_BOLD}$CURRENT_REPO${C_RESET}"
  echo -e "  ${C_DIM}$desc${C_RESET}"
  echo ""
  printf "  ${C_DIM}%-16s${C_RESET} ${C_CYAN}%s${C_RESET}\n" "Visibility:"    "$vis"
  printf "  ${C_DIM}%-16s${C_RESET} ${C_CYAN}%s${C_RESET}\n" "Language:"      "$lang"
  printf "  ${C_DIM}%-16s${C_RESET} ${C_CYAN}%s${C_RESET}\n" "Default Branch:""$default_br"
  printf "  ${C_DIM}%-16s${C_RESET} ${C_YELLOW}★ %s${C_RESET}\n" "Stars:"     "$stars"
  printf "  ${C_DIM}%-16s${C_RESET} ${C_GREEN}%s${C_RESET}\n" "Forks:"        "$forks"
  printf "  ${C_DIM}%-16s${C_RESET} ${C_DIM}%s KB${C_RESET}\n" "Size:"        "$size"
  echo ""
  press_enter
  repo_menu
}

# ═══════════════════════════════════════════════════
#  BRANCHES
# ═══════════════════════════════════════════════════
manage_branches() {
  header
  echo -e "  ${C_CYAN_B}// BRANCHES${C_RESET}  ${C_DIM}(current: ${C_PURPLE}$CURRENT_BRANCH${C_DIM})${C_RESET}"
  echo ""
  info "Loading branches…"

  local resp
  resp=$(gh_get "/repos/$CURRENT_REPO/branches?per_page=100")

  header
  echo -e "  ${C_CYAN_B}// BRANCHES${C_RESET}  ${C_DIM}(current: ${C_PURPLE}$CURRENT_BRANCH${C_DIM})${C_RESET}"
  echo ""

  local i=1
  local branches=()
  while IFS= read -r name; do
    branches+=("$name")
    local marker=""
    [ "$name" = "$CURRENT_BRANCH" ] && marker=" ${C_GREEN}✓${C_RESET}"
    printf "  ${C_DIM}[${C_RESET}${C_CYAN}%-3s${C_DIM}]${C_RESET} ⎇  %s%b\n" "$i" "$name" "$marker"
    i=$((i+1))
  done < <(echo "$resp" | jq -r '.[].name')

  echo ""
  divider
  menu_item "n" "+" "Create New Branch" "$C_CYAN"
  menu_item "q" "←" "Back" "$C_DIM"
  divider
  echo ""
  prompt "Select branch number or action"
  read -r choice

  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    local idx=$((choice-1))
    local selected="${branches[$idx]}"
    if [ -z "$selected" ]; then
      error "Invalid selection."; press_enter; manage_branches; return
    fi
    CURRENT_BRANCH="$selected"
    success "Switched to branch: $CURRENT_BRANCH"
    press_enter
    repo_menu
  elif [ "$choice" = "n" ]; then
    create_branch "$resp"
  elif [ "$choice" = "q" ]; then
    repo_menu
  else
    manage_branches
  fi
}

create_branch() {
  echo ""
  prompt "New branch name"
  read -r new_branch
  [ -z "$new_branch" ] && { warn "Cancelled."; press_enter; manage_branches; return; }

  # Get SHA of current branch HEAD
  local sha
  sha=$(gh_get "/repos/$CURRENT_REPO/git/ref/heads/$CURRENT_BRANCH" | jq -r '.object.sha')
  if [ -z "$sha" ] || [ "$sha" = "null" ]; then
    error "Could not get branch SHA."; press_enter; manage_branches; return
  fi

  local body
  body=$(jq -n --arg r "refs/heads/$new_branch" --arg s "$sha" '{ref:$r, sha:$s}')
  local resp
  resp=$(gh_post "/repos/$CURRENT_REPO/git/refs" "$body")
  local msg
  msg=$(api_error "$resp")
  if [ -n "$msg" ]; then
    error "Failed: $msg"; press_enter; manage_branches; return
  fi

  CURRENT_BRANCH="$new_branch"
  success "Created and switched to: $new_branch"
  press_enter
  manage_branches
}

# ═══════════════════════════════════════════════════
#  FILE BROWSER
# ═══════════════════════════════════════════════════
browse_files() {
  local current_path="$1"
  header
  echo -e "  ${C_CYAN_B}// FILES${C_RESET}  ${C_DIM}branch: ${C_PURPLE}$CURRENT_BRANCH${C_RESET}"
  echo -e "  ${C_DIM}path: /${current_path}${C_RESET}"
  echo ""
  info "Loading file tree…"

  local api_path="/repos/$CURRENT_REPO/contents/${current_path}?ref=$CURRENT_BRANCH"
  local resp
  resp=$(gh_get "$api_path")

  local err
  err=$(api_error "$resp")
  if [ -n "$err" ]; then
    error "$err"; press_enter; repo_menu; return
  fi

  header
  echo -e "  ${C_CYAN_B}// FILES${C_RESET}  ${C_DIM}branch: ${C_PURPLE}$CURRENT_BRANCH${C_RESET}"
  echo -e "  ${C_DIM}path: /${current_path}${C_RESET}"
  echo ""

  # Sort: dirs first, then files
  local sorted
  sorted=$(echo "$resp" | jq -c '[.[] | select(.type=="dir")] + [.[] | select(.type=="file")]')

  local i=1
  local names=()
  local types=()
  local paths=()
  local shas=()

  while IFS=$'\t' read -r name type path sha; do
    names+=("$name")
    types+=("$type")
    paths+=("$path")
    shas+=("$sha")
    local icon="📄"
    [ "$type" = "dir" ] && icon="📁"
    local col="$C_RESET"
    [ "$type" = "dir" ] && col="$C_CYAN"
    printf "  ${C_DIM}[${C_RESET}${C_CYAN}%-3s${C_DIM}]${C_RESET} %s  ${col}%s${C_RESET}\n" "$i" "$icon" "$name"
    i=$((i+1))
  done < <(echo "$sorted" | jq -r '.[] | [.name, .type, .path, (.sha // "")] | @tsv')

  echo ""
  divider
  if [ -n "$current_path" ]; then
    menu_item ".." "←" "Parent Directory" "$C_DIM"
  fi
  menu_item "nf" "+" "New File Here" "$C_CYAN"
  menu_item "q"  "←" "Repo Menu" "$C_DIM"
  divider
  echo ""
  prompt "Select item number or action"
  read -r choice

  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    local idx=$((choice-1))
    if [ $idx -lt 0 ] || [ $idx -ge ${#names[@]} ]; then
      error "Invalid."; press_enter; browse_files "$current_path"; return
    fi
    local sel_name="${names[$idx]}"
    local sel_type="${types[$idx]}"
    local sel_path="${paths[$idx]}"
    local sel_sha="${shas[$idx]}"
    if [ "$sel_type" = "dir" ]; then
      browse_files "$sel_path"
    else
      file_menu "$sel_path" "$sel_sha" "$current_path"
    fi
  elif [ "$choice" = ".." ]; then
    local parent
    parent=$(dirname "$current_path")
    [ "$parent" = "." ] && parent=""
    browse_files "$parent"
  elif [ "$choice" = "nf" ]; then
    create_file_interactive "$current_path"
  elif [ "$choice" = "q" ]; then
    repo_menu
  else
    browse_files "$current_path"
  fi
}

# ═══════════════════════════════════════════════════
#  FILE MENU
# ═══════════════════════════════════════════════════
file_menu() {
  local file_path="$1"
  local file_sha="$2"
  local parent_path="$3"
  local file_name
  file_name=$(basename "$file_path")

  header
  echo -e "  ${C_CYAN_B}// FILE${C_RESET}  ${C_CYAN}$file_name${C_RESET}"
  echo -e "  ${C_DIM}$file_path${C_RESET}"
  echo ""
  menu_item "1" "✏" "Edit in nano"      "$C_CYAN"
  menu_item "2" "👁" "View Content"      "$C_GREEN"
  menu_item "3" "⬇" "Download to Termux" "$C_PURPLE"
  menu_item "4" "✏" "Rename / Move"     "$C_YELLOW"
  menu_item "5" "🗑" "Delete File"       "$C_RED"
  menu_item "q" "←" "Back"              "$C_DIM"
  echo ""
  prompt "Choice"
  read -r choice
  case "$choice" in
    1) edit_file "$file_path" "$file_sha" "$parent_path" ;;
    2) view_file "$file_path" "$file_sha" "$parent_path" ;;
    3) download_file "$file_path" "$file_sha" "$parent_path" ;;
    4) rename_file "$file_path" "$file_sha" "$parent_path" ;;
    5) delete_file "$file_path" "$file_sha" "$parent_path" ;;
    q) browse_files "$parent_path" ;;
    *) file_menu "$file_path" "$file_sha" "$parent_path" ;;
  esac
}

# ═══════════════════════════════════════════════════
#  VIEW FILE
# ═══════════════════════════════════════════════════
view_file() {
  local file_path="$1"
  local file_sha="$2"
  local parent_path="$3"

  info "Loading $file_path…"
  local resp
  resp=$(gh_get "/repos/$CURRENT_REPO/contents/$file_path?ref=$CURRENT_BRANCH")
  local err
  err=$(api_error "$resp")
  if [ -n "$err" ]; then
    error "$err"; press_enter; file_menu "$file_path" "$file_sha" "$parent_path"; return
  fi

  local content_b64
  content_b64=$(echo "$resp" | jq -r '.content' | tr -d '\n ')
  local content
  content=$(echo "$content_b64" | base64 -d 2>/dev/null)

  header
  echo -e "  ${C_CYAN_B}// VIEW: ${C_CYAN}$(basename "$file_path")${C_RESET}"
  divider
  echo ""
  echo "$content" | head -100
  echo ""
  divider
  press_enter
  file_menu "$file_path" "$file_sha" "$parent_path"
}

# ═══════════════════════════════════════════════════
#  EDIT FILE
# ═══════════════════════════════════════════════════
edit_file() {
  local file_path="$1"
  local file_sha="$2"
  local parent_path="$3"

  info "Fetching $file_path…"
  local resp
  resp=$(gh_get "/repos/$CURRENT_REPO/contents/$file_path?ref=$CURRENT_BRANCH")
  local err
  err=$(api_error "$resp")
  if [ -n "$err" ]; then
    error "$err"; press_enter; file_menu "$file_path" "$file_sha" "$parent_path"; return
  fi

  # Get the real SHA from the response
  local real_sha
  real_sha=$(echo "$resp" | jq -r '.sha')

  local content_b64
  content_b64=$(echo "$resp" | jq -r '.content' | tr -d '\n ')
  echo "$content_b64" | base64 -d > "$TEMP_FILE" 2>/dev/null

  # Open in nano
  nano "$TEMP_FILE"

  header
  echo -e "  ${C_CYAN_B}// COMMIT: ${C_CYAN}$(basename "$file_path")${C_RESET}"
  echo ""
  prompt "Commit message (Enter to skip save)"
  read -r commit_msg
  if [ -z "$commit_msg" ]; then
    warn "Edit cancelled — no commit."
    rm -f "$TEMP_FILE"
    press_enter
    file_menu "$file_path" "$real_sha" "$parent_path"
    return
  fi

  info "Pushing changes…"
  local new_content_b64
  new_content_b64=$(base64 < "$TEMP_FILE" | tr -d '\n')
  rm -f "$TEMP_FILE"

  local body
  body=$(jq -n \
    --arg m "$commit_msg" \
    --arg c "$new_content_b64" \
    --arg s "$real_sha" \
    --arg b "$CURRENT_BRANCH" \
    '{message:$m, content:$c, sha:$s, branch:$b}')

  local put_resp
  put_resp=$(gh_put "/repos/$CURRENT_REPO/contents/$file_path" "$body")
  local put_err
  put_err=$(api_error "$put_resp")
  if [ -n "$put_err" ]; then
    error "Push failed: $put_err"
  else
    local new_sha
    new_sha=$(echo "$put_resp" | jq -r '.content.sha')
    success "Committed: $commit_msg"
    file_sha="$new_sha"
  fi
  press_enter
  file_menu "$file_path" "$file_sha" "$parent_path"
}

# ═══════════════════════════════════════════════════
#  DOWNLOAD FILE
# ═══════════════════════════════════════════════════
download_file() {
  local file_path="$1"
  local file_sha="$2"
  local parent_path="$3"
  local file_name
  file_name=$(basename "$file_path")

  info "Downloading $file_name…"
  local resp
  resp=$(gh_get "/repos/$CURRENT_REPO/contents/$file_path?ref=$CURRENT_BRANCH")
  local err
  err=$(api_error "$resp")
  if [ -n "$err" ]; then
    error "$err"; press_enter; file_menu "$file_path" "$file_sha" "$parent_path"; return
  fi

  local content_b64
  content_b64=$(echo "$resp" | jq -r '.content' | tr -d '\n ')

  local dest="$HOME/storage/downloads/$file_name"
  # Fallback if storage not setup
  if [ ! -d "$HOME/storage/downloads" ]; then
    dest="$HOME/$file_name"
  fi

  echo "$content_b64" | base64 -d > "$dest" 2>/dev/null
  success "Saved to: $dest"
  press_enter
  file_menu "$file_path" "$file_sha" "$parent_path"
}

# ═══════════════════════════════════════════════════
#  CREATE FILE
# ═══════════════════════════════════════════════════
create_file_interactive() {
  local parent_path="$1"
  header
  echo -e "  ${C_CYAN_B}// NEW FILE${C_RESET}"
  echo -e "  ${C_DIM}in: /${parent_path}${C_RESET}"
  echo ""

  prompt "Filename (e.g. notes.md or src/app.js)"
  read -r file_name
  [ -z "$file_name" ] && { warn "Cancelled."; press_enter; browse_files "$parent_path"; return; }

  local full_path
  if [ -n "$parent_path" ]; then
    full_path="$parent_path/$file_name"
  else
    full_path="$file_name"
  fi

  echo ""
  info "Opening editor for initial content…"
  echo -e "  ${C_DIM}(Save and exit nano to continue, or Ctrl+X to skip content)${C_RESET}"
  press_enter

  > "$TEMP_FILE"
  nano "$TEMP_FILE"

  prompt "Commit message"
  read -r commit_msg
  [ -z "$commit_msg" ] && commit_msg="feat: add $file_name"

  info "Creating $full_path…"
  local content_b64
  content_b64=$(base64 < "$TEMP_FILE" | tr -d '\n')
  rm -f "$TEMP_FILE"

  local body
  body=$(jq -n \
    --arg m "$commit_msg" \
    --arg c "$content_b64" \
    --arg b "$CURRENT_BRANCH" \
    '{message:$m, content:$c, branch:$b}')

  local resp
  resp=$(gh_put "/repos/$CURRENT_REPO/contents/$full_path" "$body")
  local err
  err=$(api_error "$resp")
  if [ -n "$err" ]; then
    error "Failed: $err"
  else
    success "Created: $full_path"
  fi
  press_enter
  browse_files "$parent_path"
}

# ═══════════════════════════════════════════════════
#  DELETE FILE
# ═══════════════════════════════════════════════════
delete_file() {
  local file_path="$1"
  local file_sha="$2"
  local parent_path="$3"

  echo ""
  warn "Delete: $file_path"
  prompt "Confirm? (y/N)"
  read -r confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    warn "Cancelled."
    press_enter
    file_menu "$file_path" "$file_sha" "$parent_path"
    return
  fi

  prompt "Commit message"
  read -r commit_msg
  [ -z "$commit_msg" ] && commit_msg="chore: delete $file_path"

  info "Deleting…"
  local body
  body=$(jq -n \
    --arg m "$commit_msg" \
    --arg s "$file_sha" \
    --arg b "$CURRENT_BRANCH" \
    '{message:$m, sha:$s, branch:$b}')

  local resp
  resp=$(gh_delete "/repos/$CURRENT_REPO/contents/$file_path" "$body")

  # 204 = success, no body. curl -s returns empty string.
  local err
  err=$(echo "$resp" | jq -r '.message // empty' 2>/dev/null)
  if [ -n "$err" ]; then
    error "Failed: $err"
    press_enter
    file_menu "$file_path" "$file_sha" "$parent_path"
  else
    success "Deleted: $file_path"
    press_enter
    browse_files "$parent_path"
  fi
}

# ═══════════════════════════════════════════════════
#  RENAME / MOVE FILE
# ═══════════════════════════════════════════════════
rename_file() {
  local file_path="$1"
  local file_sha="$2"
  local parent_path="$3"

  header
  echo -e "  ${C_CYAN_B}// RENAME / MOVE${C_RESET}"
  echo -e "  ${C_DIM}current: $file_path${C_RESET}"
  echo ""
  prompt "New path (e.g. src/newname.js)"
  read -r new_path
  [ -z "$new_path" ] && { warn "Cancelled."; press_enter; file_menu "$file_path" "$file_sha" "$parent_path"; return; }

  prompt "Commit message"
  read -r commit_msg
  [ -z "$commit_msg" ] && commit_msg="refactor: rename $file_path to $new_path"

  info "Fetching file content…"
  local resp
  resp=$(gh_get "/repos/$CURRENT_REPO/contents/$file_path?ref=$CURRENT_BRANCH")
  local err
  err=$(api_error "$resp")
  if [ -n "$err" ]; then
    error "$err"; press_enter; file_menu "$file_path" "$file_sha" "$parent_path"; return
  fi

  local content_b64
  content_b64=$(echo "$resp" | jq -r '.content' | tr -d '\n ')
  local real_sha
  real_sha=$(echo "$resp" | jq -r '.sha')

  # Create at new path
  info "Creating at new path…"
  local create_body
  create_body=$(jq -n \
    --arg m "$commit_msg" \
    --arg c "$content_b64" \
    --arg b "$CURRENT_BRANCH" \
    '{message:$m, content:$c, branch:$b}')
  local create_resp
  create_resp=$(gh_put "/repos/$CURRENT_REPO/contents/$new_path" "$create_body")
  local create_err
  create_err=$(api_error "$create_resp")
  if [ -n "$create_err" ]; then
    error "Create failed: $create_err"; press_enter; file_menu "$file_path" "$file_sha" "$parent_path"; return
  fi

  # Delete old path
  info "Removing old file…"
  local del_body
  del_body=$(jq -n \
    --arg m "chore: remove old $file_path after rename" \
    --arg s "$real_sha" \
    --arg b "$CURRENT_BRANCH" \
    '{message:$m, sha:$s, branch:$b}')
  gh_delete "/repos/$CURRENT_REPO/contents/$file_path" "$del_body" > /dev/null

  success "Moved: $file_path → $new_path"
  press_enter
  browse_files "$parent_path"
}

# ═══════════════════════════════════════════════════
#  COMMITS
# ═══════════════════════════════════════════════════
view_commits() {
  header
  echo -e "  ${C_CYAN_B}// COMMIT HISTORY${C_RESET}  ${C_DIM}branch: ${C_PURPLE}$CURRENT_BRANCH${C_RESET}"
  echo ""
  info "Loading commits…"

  local resp
  resp=$(gh_get "/repos/$CURRENT_REPO/commits?sha=$CURRENT_BRANCH&per_page=20")
  local err
  err=$(api_error "$resp")
  if [ -n "$err" ]; then
    error "$err"; press_enter; repo_menu; return
  fi

  header
  echo -e "  ${C_CYAN_B}// COMMIT HISTORY${C_RESET}  ${C_DIM}branch: ${C_PURPLE}$CURRENT_BRANCH${C_RESET}"
  echo ""

  local count
  count=$(echo "$resp" | jq 'length')
  if [ "$count" -eq 0 ]; then
    warn "No commits found."
  else
    while IFS=$'\t' read -r sha msg author date; do
      local short_sha="${sha:0:7}"
      local short_msg="${msg:0:55}"
      printf "  ${C_CYAN}%s${C_RESET}  %s\n" "$short_sha" "$short_msg"
      printf "  ${C_DIM}%s · %s${C_RESET}\n" "$author" "$date"
      echo ""
    done < <(echo "$resp" | jq -r '.[] | [.sha, (.commit.message|split("\n")[0]), .commit.author.name, .commit.author.date] | @tsv')
  fi

  press_enter
  repo_menu
}

# ═══════════════════════════════════════════════════
#  MAIN MENU
# ═══════════════════════════════════════════════════
main_menu() {
  header
  echo -e "  ${C_CYAN_B}// MAIN MENU${C_RESET}"
  echo ""
  menu_item "1" "⊞" "My Repositories" "$C_CYAN"
  if [ -n "$CURRENT_REPO" ]; then
    menu_item "2" "📁" "Files: $CURRENT_REPO_NAME" "$C_CYAN"
    menu_item "3" "⎇ " "Branches" "$C_PURPLE"
    menu_item "4" "🕓" "Commits" "$C_GREEN"
  fi
  divider
  menu_item "r" "⟳" "Refresh Auth" "$C_DIM"
  menu_item "x" "⏻" "Logout" "$C_RED"
  menu_item "q" "✕" "Quit" "$C_DIM"
  echo ""
  prompt "Choice"
  read -r choice
  case "$choice" in
    1) list_repos ;;
    2) [ -n "$CURRENT_REPO" ] && browse_files "" || main_menu ;;
    3) [ -n "$CURRENT_REPO" ] && manage_branches || main_menu ;;
    4) [ -n "$CURRENT_REPO" ] && view_commits || main_menu ;;
    r) verify_auth && success "Auth OK: $GH_USER" ; press_enter; main_menu ;;
    x) logout ;;
    q) echo -e "\n  ${C_DIM}Goodbye.${C_RESET}\n"; exit 0 ;;
    *) main_menu ;;
  esac
}

# ═══════════════════════════════════════════════════
#  DEPENDENCY CHECK
# ═══════════════════════════════════════════════════
check_deps() {
  local missing=()
  for cmd in curl jq nano base64; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo -e "${C_RED}Missing dependencies: ${missing[*]}${C_RESET}"
    echo -e "${C_DIM}Install with:  pkg install ${missing[*]}${C_RESET}"
    exit 1
  fi
}

# ═══════════════════════════════════════════════════
#  ENTRY POINT
# ═══════════════════════════════════════════════════
main() {
  check_deps
  setup_config

  if load_config && [ -n "$TOKEN" ]; then
    if verify_auth; then
      main_menu
    else
      warn "Saved token failed. Please log in again."
      delete_config
      press_enter
      auth_screen && main_menu
    fi
  else
    auth_screen && main_menu
  fi
}

main
