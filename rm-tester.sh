# #!/usr/bin/env bash

sudo rm -rf /home/tester/ 
sudo killall -u tester
sudo loginctl terminate-user tester
sudo userdel tester