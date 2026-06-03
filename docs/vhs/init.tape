Require conformist
Require nano

Set Shell zsh
Set FontSize 14

Set Theme "Catppuccin Mocha"

Set Width 720
Set Height 360
Set Padding 20

Hide
Type "TEMP_DIR=$(mktemp -d) && cd $TEMP_DIR && clear"
Enter

Show
Type "conformist --init"
Enter
Sleep 2s

Type "nano conformist.toml"
Enter
Sleep 5s

Ctrl+x

Hide
Type "cd && rm -rf $TEMP_DIR"
