# ~/.local/bin
fish_add_path $HOME/.local/bin

# opencode
fish_add_path $HOME/.opencode/bin

# fnm
fish_add_path $HOME/.local/share/fnm

if type -q fnm
    fnm env --use-on-cd --shell fish | source
end

# zoxide
if type -q zoxide
    zoxide init fish | source
end
