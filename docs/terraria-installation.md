# Terraria Dedicated Server Installation

This guide installs the official Terraria dedicated server on a Debian/Ubuntu VM.

Current official server package referenced here: **Terraria 1.4.5.8**.

## 1. Connect to the VM

In Google Cloud Console:

**Compute Engine → VM instances → your VM → SSH**

You can also use `gcloud compute ssh` if you prefer the command line.

## 2. Install basic tools

```bash
sudo apt update
sudo apt install -y wget unzip
```

## 3. Create a dedicated Terraria user

Using a separate Linux user keeps the server files and world files isolated.

```bash
sudo useradd   --create-home   --home-dir /home/terraria   --shell /bin/bash   terraria
```

If the user already exists, skip this step.

## 4. Create the server directory

```bash
sudo mkdir -p /opt/terraria
sudo chown terraria:terraria /opt/terraria
```

Switch to the Terraria user:

```bash
sudo -iu terraria
```

## 5. Download the official server files

```bash
cd /opt/terraria

wget   https://terraria.org/api/download/pc-dedicated-server/terraria-server-1458.zip
```

Extract them:

```bash
unzip terraria-server-1458.zip
```

The Linux server files will be under:

```text
/opt/terraria/1458/Linux/
```

## 6. Make the server executable

```bash
cd /opt/terraria/1458/Linux
chmod +x TerrariaServer*
```

For a 64-bit Google Compute Engine VM, the main binary is:

```text
TerrariaServer.bin.x86_64
```

## 7. Start the server for the first time

```bash
./TerrariaServer.bin.x86_64
```

The server will open its interactive setup and let you select or create a world.

Terraria uses TCP port:

```text
7777
```

Make sure your Google Cloud firewall allows TCP 7777 to the VM.

## 8. World save location

When the server runs as the `terraria` Linux user, the normal Linux world directory is:

```text
/home/terraria/.local/share/Terraria/Worlds/
```

A world might therefore be:

```text
/home/terraria/.local/share/Terraria/Worlds/MyWorld.wld
```

This path is important for the backup configuration later.

Example:

```text
TERRARIA_WORLD_PATH=/home/terraria/.local/share/Terraria/Worlds/MyWorld.wld
```

## 9. Server configuration file

Terraria can be started with a config file:

```bash
./TerrariaServer.bin.x86_64 -config serverconfig.txt
```

Common settings include:

```text
world=/home/terraria/.local/share/Terraria/Worlds/MyWorld.wld
port=7777
maxplayers=8
password=
```

Do not put a real server password in Git.

## 10. Useful server commands

While the server console is running:

```text
save
```

Saves the world.

```text
exit
```

Saves the world and shuts down the server.

```text
exit-nosave
```

Shuts down without saving.

Use `save` before backups and `exit` for a normal shutdown.

## 11. What comes next

After the first manual launch works, the next steps are:

1. create `serverconfig.txt`
2. run Terraria through systemd
3. connect the existing 10-minute GitHub Release backup timer
4. set the real `TERRARIA_WORLD_PATH`
5. add a save hook so backups call `save` before copying the world
6. test start, save, backup, restore, and shutdown

## Official references

Official Terraria Wiki server guide:

https://terraria.wiki.gg/wiki/Server

Official setup guide:

https://terraria.wiki.gg/wiki/Guide:Setting_up_a_Terraria_server

Official dedicated server download used above:

https://terraria.org/api/download/pc-dedicated-server/terraria-server-1458.zip
