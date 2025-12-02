$USR=
$THEME_DIR =/home/$USR/.local/share/themes/
$HOME=/home/$USR
sudo cp /etc/polybar/config.ini ./polybar/ # copy to polybar .ini file
unzip ./theme/Nightfox-Dark-Terafox-B-MB.zip -d /usr/share/themes/ # unzip GTK3 theme file
cp ./theme/settings.ini $HOME/.config/gtk-3.0/settings.ini # copy to GTK3 .ini file
cp ./picom/picom.conf $HOME/.config/picom/picom.conf       # copy picom .conf file
cp ./i3/* $HOME/.config/i3/                               # copy i3 config files
cp ./kitty/* $HOME/.config/kitty/                          # copy kitty config files
cp ./themes/miyabi_bg_1.jpeg $HOME/Pictures/miyabi_bg_1.jpeg