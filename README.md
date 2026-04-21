# GITCTRL — GitHub CLI for Termux

> A terminal-based GitHub repository manager for Android (Termux).  
> Built to replace the [GITCTRL mobile web app](https://github.com/DoomedButton327) with a native terminal experience.

```
  ╔════════════════════════════════════╗
  ║   GITCTRL  //  Repository Control  ║
  ╚════════════════════════════════════╝
  user: DoomedButton327  repo: my-project  branch: main
  ────────────────────────────────────
```

---

## Features

- **Auth** — Paste your GitHub PAT once, saved securely to `~/.gitctrl/config`
- **Repos** — List, search, and select all your repositories
- **File Browser** — Navigate folders and files just like a file explorer
- **Editor** — Edit any file in `nano`, then commit and push directly to GitHub
- **Create Files** — New file + editor + auto-commit in one flow
- **Delete Files** — Confirms before deleting, commits the removal
- **Rename / Move** — Moves a file to a new path and cleans up the old one
- **Download** — Save any file to `~/storage/downloads/`
- **Branches** — List, switch, and create branches
- **Commit History** — View the last 20 commits with SHA, message, author, and date
- **Create Repo** — Name, description, public/private, auto README toggle
- **Logout** — Deletes your saved token

---

## Requirements

Install these packages in Termux before running:

```bash
pkg update && pkg upgrade -y
pkg install curl jq nano
```

---

## Installation

### Option 1 — Run directly

```bash
bash gitctrl.sh
```

### Option 2 — Global command (run from anywhere)

```bash
cp gitctrl.sh $PREFIX/bin/gitctrl
chmod +x $PREFIX/bin/gitctrl

# Now just type:
gitctrl
```

---

## Setup

1. Go to [github.com/settings/tokens/new](https://github.com/settings/tokens/new)
2. Create a **Classic token** with the `repo` scope
3. Copy the token (starts with `ghp_`)
4. Run `gitctrl` and paste it when prompted

Your token is saved to `~/.gitctrl/config` (chmod 600 — only readable by you).

---

## Usage

```
Main Menu
 [1]  My Repositories
 [2]  Files: <current repo>
 [3]  Branches
 [4]  Commits
 [r]  Refresh Auth
 [x]  Logout
 [q]  Quit
```

### Browsing files

- Enter a number to open a file or enter a folder
- Type `..` to go up to the parent directory
- Type `nf` to create a new file in the current folder

### Editing a file

1. Select a file → choose **Edit in nano**
2. Make your changes in nano, then `Ctrl+X → Y → Enter` to save
3. Enter a commit message when prompted
4. The script pushes the change directly to GitHub

---

## File Structure

```
github-termux/
├── gitctrl.sh      # The main script
└── README.md
```

---

## Notes

- Requires a GitHub **Personal Access Token** with `repo` scope
- Token is stored locally in `~/.gitctrl/config` and never sent anywhere except the GitHub API
- If `curl` throws an SSL error, run `pkg reinstall openssl curl` to fix it
- File downloads go to `~/storage/downloads/` — run `termux-setup-storage` first if that folder doesn't exist

---

## License

MIT — do whatever you want with it.

---

*Made by [@DoomedButton327](https://github.com/DoomedButton327)*
