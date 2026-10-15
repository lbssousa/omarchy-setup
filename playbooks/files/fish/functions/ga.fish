# Managed by omarchy-setup (playbooks/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/worktrees

# Create a new worktree and branch from within current git directory.
function ga --description 'New git worktree and branch next to the current repository'
    if test -z "$argv[1]"
        echo "Usage: ga [branch name]"
        return 1
    end

    set -l branch $argv[1]
    set -l base (path basename -- $PWD)
    set -l wt_path "../$base--$branch"

    git worktree add -b $branch $wt_path
    mise trust $wt_path
    cd $wt_path
end
