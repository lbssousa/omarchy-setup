# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/worktrees

# Remove worktree and branch from within active worktree directory.
function gd --description 'Remove the current git worktree and its branch'
    if gum confirm "Remove worktree and branch?"
        set -l cwd $PWD
        set -l worktree (path basename -- $cwd)

        # split on first `--`
        set -l root (string split -m1 -- -- $worktree)[1]

        # Protect against accidentally nuking a non-worktree directory
        if test "$root" != "$worktree"
            # The directory name has "/" turned into "-" (ga), so ask git.
            set -l branch (git branch --show-current 2>/dev/null)
            cd ../$root; or return 1
            git worktree remove $cwd --force; or return 1
            if test -n "$branch"
                git branch -D $branch
            end
        end
    end
end
