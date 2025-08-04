# Koshi

**Koshi** gives your [Jujutsu (jj)](https://github.com/jj-vcs/jj) projects a powerful lift with AI-assisted commit messages, interactive refinement, and a streamlined GitHub Pull Request workflow — all from your terminal.

---

## Features

- **AI-powered commit descriptions**
  Generate and iteratively refine commit messages for your JJ commits using [aichat](https://github.com/sigoden/aichat). Accept or refine suggestions interactively based on your diffs.
- **Tight GitHub integration**
  Effortlessly create and update GitHub PRs from your JJ commits with [`gh`](https://cli.github.com/).
- **Interactive terminal UI**
  Uses [gum](https://github.com/charmbracelet/gum) for beautiful, user-friendly command-line interactions and formatting.
- **Smart reviewer management**
  Select reviewers for PRs interactively; merges suggestions from your config and any previous PR reviewers.

---

## Requirements

- [jj](https://github.com/martinvonz/jj) (Jujutsu)
- [argc](https://github.com/sigoden/argc)
- [gum](https://github.com/charmbracelet/gum)
- [aichat](https://github.com/sigoden/aichat)
- [gh](https://cli.github.com/) (GitHub CLI)
- [jq](https://stedolan.github.io/jq/) (for reviewer selection)

All must be available in your `$PATH`.

---

## Installation

1. Copy `koshi.sh` into a directory in your `$PATH` and make it executable:

   ```sh
   cp koshi.sh ~/bin/koshi
   chmod u+x ~/bin/koshi
   ```

2. Install all dependencies using your system package manager or from their respective repositories.

3. (Optional) Integrate `koshi` with `jj` by adding aliases in your `.jj/config.toml`:

   ```toml
   [aliases]
   ai-desc   = ['util', 'exec', '--', 'koshi', 'ai-desc', '--role', 'code-author']
   ai-commit = ['util', 'exec', '--', 'koshi', 'ai-desc', '--role', 'code-author', '--commit']
   ```

4. (Optional) Set up reviewer configuration in `~/.config/koshi/reviewers.json` to enable default reviewer suggestions:

   ```json
   {
     "$HOME/projects/myproject": ["alice", "bob"],
     "$HOME/projects/another": ["carol"]
   }
   ```

---

## Usage

### Generate/Refine Commit Message with AI

```sh
koshi ai-desc --role "<ROLE>" [--ticket "<TICKET_ID>"] [--commit] [--pull_request]
```

- `--role <ROLE>`: Specify the AI assistant's role (to tailor suggestions).
- `--ticket <TICKET_ID>`: Optionally reference a ticket or issue ID.
- `--commit`: After confirming the description, automatically commit.
- `--pull_request`: Automatically open or update a GitHub pull request after committing.

### Create or Update Pull Request

```sh
koshi pr
```

This command lets you review or edit your commit description, pushes your commit to GitHub, and creates or updates a pull request. When opening or updating a PR, Koshi will prompt you to select reviewers interactively.

Default reviewer suggestions are pulled from your [reviewer configuration](#reviewer-configuration) file (`~/.config/koshi/reviewers.json`) — where you define reviewers for each repository based on its local filesystem path (see [Reviewer Configuration](#reviewer-configuration) below for details)—and merged with any current reviewers on the PR, so you always have an up-to-date and convenient selection.

---

## Reviewer Configuration

To enable default reviewer suggestions for your projects, create the file `~/.config/koshi/reviewers.json` with the following structure:

```json
{
  "$HOME/projects/myproject": ["alice", "bob"],
  "$HOME/projects/another": ["carol"]
}
```

- **Keys**: The _full filesystem path_ to your cloned repository (with `$HOME` as a variable if desired). The current working directory (with `$HOME` expanded) is matched against these keys.
- **Values**: An array of GitHub usernames (reviewer logins) to suggest as default reviewers when opening or updating pull requests in that repo.

Koshi will merge your configured reviewer list with any existing reviewers on the pull request, and
present the combined Set for interactive selection.

---

## Example

```sh
jj new
# ...make code changes...
koshi ai-desc --role backend-engineer --ticket ABC-123 --commit --pull_request
```

Koshi will show the diff, propose a commit message using AI, let you refine it, and (when accepted) commit and create the PR, with interactive reviewer selection.

---

## License

MIT (see LICENSE).
