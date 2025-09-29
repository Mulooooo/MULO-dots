import subprocess
import sys
import shutil
import os

def run_command(command, sudo=False):
    if sudo:
        command = ['sudo'] + command
    try:
        subprocess.run(command, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error: {e}")
        sys.exit(1)

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))

    konsoleDir = os.path.expanduser('~/.local/share/konsole')
    awesomeDir = os.path.expanduser('~/.config/awesomewm/')
    polybarDir = os.path.abspath('/etc/polybar/')
    picomDir = os.path.expanduser('~/.config/picom/')
    backgroundDir = os.path.expanduser('~/Pictures/Wallpapers/')

    konsoleCfg = os.path.join(script_dir, 'konsole')
    awesomeCfg = os.path.join(script_dir, 'awesome')
    polybarCfg = os.path.join(script_dir, 'polybar')
    picomCfg = os.path.join(script_dir, 'picom')
    backgroundCfg = os.path.join(script_dir, 'backgrounds')

    print("Updating package lists...")
    run_command(['apt', 'update'], sudo=True)

    print("Installing Awesome WM...")
    run_command(['apt', 'install', '-y', 'awesome'], sudo=True)

    if os.path.exists(awesomeDir):
        shutil.rmtree(awesomeDir)
    shutil.copytree(awesomeCfg, awesomeDir)

    print("Awesome WM installation complete!")
    print("Log out and select 'Awesome' from your login manager session menu.")
 
    print("Installing Polybar...")
    run_command(['apt', 'install', '-y', 'polybar'], sudo=True)

    if os.path.exists(polybarDir):
        shutil.rmtree(polybarDir)
    shutil.copytree(polybarCfg, polybarDir)

    print("Installing Picom...")
    run_command(['apt', 'install', '-y', 'picom'], sudo=True)

    if os.path.exists(picomDir):
        shutil.rmtree(picomDir)
    shutil.copytree(picomCfg, picomDir)

    print("installing Konsole...")
    run_command(['apt', 'install', '-y', 'konsole'], sudo=True)

    if os.path.exists(konsoleDir):
        shutil.rmtree(konsoleDir)
    shutil.copytree(konsoleCfg, konsoleDir)

    if os.path.exists(backgroundDir):
        shutil.rmtree(backgroundDir)
    shutil.copytree(backgroundCfg, backgroundDir)

if __name__ == "__main__":
    main()