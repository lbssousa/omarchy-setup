# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/completions
#
# `omarchy a b <Tab>` offers the next word of the omarchy-a-b-* commands
# next to the omarchy binary; past a full command name, it reads that
# command's `# omarchy:args=` line. Nothing to offer falls back to files,
# like bash's `complete -o default`.
#
# Not ported: bash also hides the omarchy-* binaries from first-word
# completion (`complete -I -X 'omarchy-*'`); fish has no way to filter
# command-name completions.

# Every word that may come next, before filtering by what's typed.
function __omarchy_complete_candidates
    set -l omarchy_path (command -v omarchy); or return 0
    set -l bin_dir (path dirname -- (path resolve -- $omarchy_path))
    test -d $bin_dir; or return 0

    # words[1] is "omarchy"; cword is the index of the word being completed
    # in bash's terms (COMP_CWORD), args the words already typed after it.
    set -l words (commandline -opc)
    set -l cword (count $words)
    set -l args $words[2..]

    set -l prefix omarchy
    for part in $args
        if test -z "$part"; or string match -q -- '-*' $part
            continue
        end
        set prefix $prefix-$part
    end

    set -l candidates
    for file in $bin_dir/$prefix-*
        test -f $file -a -x $file; or continue
        set -l rest (string sub -s (math (string length -- $prefix) + 2) -- (path basename -- $file))
        set -l next (string split -m1 -- - $rest)[1]
        if test -n "$next"; and not contains -- $next $candidates
            set -a candidates $next
        end
    end

    test $cword -eq 1; and set -a candidates commands

    if test "$words[2]" = commands; and test $cword -ge 2
        set -a candidates --all --json --markdown --check
    end

    if test (count $candidates) -eq 0
        # The longest command named by the words typed so far.
        set -l command_path
        set -l first_arg_index
        for n in (seq (math $cword - 1) -1 0)
            set -l command_prefix omarchy
            if test $n -gt 0
                for part in $args[1..$n]
                    if test -z "$part"; or string match -q -- '-*' $part
                        continue
                    end
                    set command_prefix $command_prefix-$part
                end
            end
            if test -x $bin_dir/$command_prefix
                set command_path $bin_dir/$command_prefix
                set first_arg_index (math $n + 1)
                break
            end
        end

        if test -n "$command_path"
            set -l spec_line (grep -m 1 '^# omarchy:args=' $command_path 2>/dev/null)
            set spec_line (string replace -r -- '^.*?omarchy:args=' '' "$spec_line")
            set -l current_arg_index (math $cword - $first_arg_index)

            for alt in (string split -- ' | ' $spec_line)
                set -l spec (string match -ra -- '\S+' $alt)
                set -l match true

                # The words already typed must fit this alternative.
                for j in (seq 0 (math $current_arg_index - 1))
                    set -l token $spec[(math $j + 1)]
                    set -l actual $words[(math $first_arg_index + $j + 1)]
                    if test -z "$token"
                        set match false
                        break
                    end

                    if string match -q -- '<*>' $token; or string match -q -- '[*]' $token
                        set -l value (string replace -r -- '^[<\[]' '' $token | string replace -r -- '[>\]]$' '')
                        if string match -q -- '*|*' $value
                            contains -- "$actual" (string split -- '|' $value); or set match false
                        end
                    else if test "$token" != "$actual"
                        set match false
                    end
                end

                test $match = true; or continue

                set -l token $spec[(math $current_arg_index + 1)]
                test -n "$token"; or continue

                if string match -q -- '<*>' $token; or string match -q -- '[*]' $token
                    set -l value (string replace -r -- '^[<\[]' '' $token | string replace -r -- '[>\]]$' '')
                    if string match -q -- '*|*' $value
                        for choice in (string split -n -- '|' $value)
                            contains -- $choice $candidates; or set -a candidates $choice
                        end
                    end
                else
                    contains -- $token $candidates; or set -a candidates $token
                end
            end
        end
    end

    # (printf would print an empty line for an empty list.)
    string join \n -- $candidates
end

# True when some candidate starts with the word being typed (what bash's
# compgen -W keeps); otherwise files are completed instead.
function __omarchy_complete_has
    set -l cur "$(commandline -ct)"
    set -l len (string length -- $cur)
    for candidate in (__omarchy_complete_candidates)
        test "$(string sub -l $len -- $candidate)" = "$cur"; and return 0
    end
    return 1
end

complete -c omarchy -f -n __omarchy_complete_has -a '(__omarchy_complete_candidates)'
complete -c omarchy -F -n 'not __omarchy_complete_has'
