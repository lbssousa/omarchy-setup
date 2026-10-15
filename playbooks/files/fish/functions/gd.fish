# Managed by omarchy-setup (playbooks/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/worktrees

# Remove worktree and branch from within active worktree directory.
function gd --description 'Remove the current git worktree and its branch'
    if gum confirm "Remove worktree and branch?"
        set -l cwd (pwd)
        set -l worktree (path basename -- $cwd)

        # split on first `--`
        set -l parts (string split -m1 -- -- $worktree)
        set -l root $parts[1]
        set -l branch $parts[-1]

        # Protect against accidentally nuking a non-worktree directory
        if test "$root" != "$worktree"
            cd ../$root
            git worktree remove $cwd --force; or return 1
            git branch -D $branch
        end
    end
end
