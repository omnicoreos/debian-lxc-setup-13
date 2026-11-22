# Debian LXC Setup (13)

Prepara un contenedor **Debian 13 (trixie) LXC de Proxmox** recién creado para trabajar
como `debian`, con sudo sin contraseña y la opción de instalar Codex y Claude Code.

> Para Ubuntu usa [omnicoreos/ubuntu-lxc-setup-26](https://github.com/omnicoreos/ubuntu-lxc-setup-26)
> (26.04) u [omnicoreos/ubuntu-lxc-setup](https://github.com/omnicoreos/ubuntu-lxc-setup) (24.04).
> Este script comprueba la versión y se niega a correr en otra que no sea Debian 13.

## Plantilla en Proxmox

Si la plantilla de Debian 13 no aparece, actualiza el catálogo en el nodo:

```bash
pveam update
pveam available --section system | grep debian-13
```

## Ejecutar con un comando

Entra como **root** en la consola del contenedor o por SSH con terminal y pega:

```bash
bash -o pipefail -c 'wget -qO- https://raw.githubusercontent.com/omnicoreos/debian-lxc-setup-13/main/debian-lxc-setup.sh | bash'
```

Sólo necesita Bash y `wget`. El script actualiza los índices de APT e instala
`curl` por sí mismo. No necesitas Git, una cuenta de GitHub ni un token. Con SSH,
usa `ssh -t root@IP_DEL_CONTENEDOR`. Si la plantilla no trae `wget`, instálalo
antes con `apt-get update && apt-get install -y wget`.

Si prefieres descargar y revisar el archivo antes de ejecutarlo:

```bash
wget https://raw.githubusercontent.com/omnicoreos/debian-lxc-setup-13/main/debian-lxc-setup.sh
less debian-lxc-setup.sh
bash debian-lxc-setup.sh
```

## Qué hace

1. Actualiza los índices y paquetes de Debian 13 con `apt-get upgrade
   --with-new-pkgs`, sin recomendaciones y conservando configuraciones locales.
   Permite dependencias necesarias nuevas, sin eliminar paquetes. No cambia de
   versión de Debian ni añade escritorio o metapaquetes.
2. Instala `sudo`, `curl`, `ca-certificates`, `git`, `nano`, `libpam-systemd` y
   `dbus-user-session` para disponer de herramientas básicas y sesión de usuario.
3. Crea `debian` con `/home/debian`, Bash y los grupos `sudo` y `adm`. Si la cuenta
   no tiene una contraseña utilizable, pide elegirla para iniciar sesión.
4. Configura sudo sin contraseña para `debian` y comprueba la regla con `visudo`.
5. Si root tiene claves públicas autorizadas en `/root/.ssh/authorized_keys`,
   las añade a `/home/debian/.ssh/authorized_keys`, sin duplicar líneas ni borrar
   las existentes. Ajusta permisos y propietario; no copia claves privadas.
6. Cambia a `debian`, prepara `~/.local/bin` en PATH y pregunta por separado si
   quieres instalar Codex y Claude Code. Acepta `y`, `Y`, `s` o `si`; Enter omite.
7. Ejecuta los instaladores oficiales elegidos **como debian**, verifica sus
   versiones y termina en una shell de debian dentro de `/home/debian`.

Los comandos de instalación utilizados son:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
curl -fsSL https://claude.ai/install.sh | bash
```

Para trabajar después, conecta con `ssh debian@IP_DEL_CONTENEDOR`. La contraseña
de inicio de sesión es la que elegiste; sudo no la solicita. Las claves copiadas
también sirven si las reglas actuales de SSH permiten ese acceso. El script
conserva la configuración SSH y el acceso root.

Ejecuta `codex` o `claude` e inicia sesión en tu cuenta cuando quieras usarlos.
El script instala las CLI, pero no realiza sus logins. `exit` cierra la shell
de debian y regresa a la sesión desde la que lanzaste el instalador.

## Diferencias con la versión de Ubuntu 26.04

- **Usuario**: la cuenta administradora se llama `debian` (la convención de las
  imágenes de Debian) en lugar de `ubuntu`; la regla de sudo queda en
  `/etc/sudoers.d/99-debian-admin`.
- **sudo**: las plantillas LXC de Debian no lo traen; el script lo instala. Es
  el sudo clásico, no sudo-rs.
- **PATH de root**: en Debian, un root obtenido con `su` (sin guion) no tiene
  `/usr/sbin` en PATH. El script fija un PATH completo para encontrar `adduser`,
  `usermod` y `visudo` en cualquier caso.

## Volver a ejecutarlo

Puedes repetir el comando: conserva la cuenta, su contraseña y los archivos de
inicio existentes; no duplica las claves ni su bloque de PATH. Vuelve a consultar
las instalaciones opcionales. Si una falla, lo indica y permite intentar la otra.
No elimina paquetes con `autoremove` ni reinicia el contenedor automáticamente.

## Estado de las pruebas

Comprobado: sintaxis Bash y ShellCheck, que todos los paquetes instalados existen
en el archivo de `trixie`, y que el `adduser` de trixie acepta `--comment`. La
prueba de regresión del cambio a debian con terminal es la misma que en Ubuntu
y debe ejecutarse en Linux:

```bash
sudo python3 tests/terminal-regression.py
```

**Pendiente: recorrido completo en un LXC Debian 13 real** (APT, cuenta, sudo y
ambas instalaciones opcionales).

Referencias: [Codex CLI](https://learn.chatgpt.com/docs/codex/cli),
[Claude Code](https://code.claude.com/docs/en/setup),
[APT de Debian 13](https://manpages.debian.org/trixie/apt/apt-get.8.en.html) y
[adduser de Debian 13](https://manpages.debian.org/trixie/adduser/adduser.8.en.html).
