# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/worktrees

# Create a new worktree and branch from within current git directory.
function ga --description 'New git worktree and branch next to the current repository'
    if test -z "$argv[1]"
        echo "Usage: ga [branch name]"
        return 1
    end

    set -l branch $argv[1]
    set -l base (path basename -- $PWD)
    set -l slug (string replace -a / - -- $branch)
    set -l wt_path "../$base--$slug"

    git worktree add -b $branch $wt_path; or return 1
    mise trust $wt_path
    cd $wt_path; or return 1
end
