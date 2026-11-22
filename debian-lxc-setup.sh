#!/usr/bin/env bash
# Debian 13 LXC: ejecutar como root, con terminal (también curl URL | bash).
# Todo queda dentro de main para consumir el script antes de cambiar de shell.
set -Eeuo pipefail

main() {
    trap 'printf "\nERROR en línea %s. Corrige el error indicado y vuelve a ejecutar el script.\n" "$LINENO" >&2' ERR
    if (( EUID != 0 )); then
        printf 'Ejecuta este script como root: sudo bash debian-lxc-setup.sh\n' >&2
        return 1
    fi
    # El stdin puede contener el propio script cuando se usa curl | bash.
    if ! { exec 3<>/dev/tty; }; then
        printf 'Hace falta una terminal interactiva; por SSH usa ssh -t.\n' >&2
        return 1
    fi
    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ ${ID:-} != debian || ${VERSION_ID:-} != 13 ]]; then
        printf 'Este script está preparado para Debian 13. Detectado: %s\n' "${PRETTY_NAME:-desconocido}" >&2
        return 1
    fi
    export LC_ALL=C.UTF-8
    # En Debian, un root obtenido con "su" (sin guion) no tiene sbin en PATH,
    # y ahí viven adduser, usermod y visudo.
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    local -a apt_options=(
        -y --no-install-recommends
        -o DPkg::Lock::Timeout=120
        -o Dpkg::Options::=--force-confdef
        -o Dpkg::Options::=--force-confold
    )
    printf '\n[1/4] Actualizando Debian 13 y preparando herramientas básicas…\n'
    # Error-Mode evita continuar con índices viejos si falla un repositorio.
    DEBIAN_FRONTEND=noninteractive apt-get -o APT::Update::Error-Mode=any update
    DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" --with-new-pkgs upgrade
    DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" install \
        sudo curl ca-certificates git nano libpam-systemd dbus-user-session
    apt-get clean
    # Las plantillas LXC de Debian no traen sudo; confirma que quedó instalado.
    local tool
    for tool in sudo visudo; do
        if ! command -v "$tool" >/dev/null; then
            printf 'No se encontró %s tras instalar sudo; revisa update-alternatives.\n' "$tool" >&2
            return 1
        fi
    done

    printf '\n[2/4] Preparando el usuario administrador debian…\n'
    if ! id debian >/dev/null 2>&1; then
        adduser --disabled-password --comment '' --shell /bin/bash debian
    fi
    local account_home account_uid account_group password_status sudo_tmp
    account_home=$(getent passwd debian | cut -d: -f6)
    account_uid=$(id -u debian)
    account_group=$(id -gn debian)
    if [[ $account_home != /home/debian || $account_uid -eq 0 ]]; then
        printf 'La cuenta debian existente tiene UID/home inesperados; revisa la cuenta antes de continuar.\n' >&2
        return 1
    fi
    usermod -s /bin/bash -aG sudo,adm debian
    install -d -m 0750 -o debian -g "$account_group" /home/debian
    # Completa sólo archivos de inicio ausentes; conserva personalizaciones.
    local startup
    for startup in .profile .bashrc .bash_logout; do
        if [[ ! -e /home/debian/$startup ]]; then
            install -m 0644 -o debian -g "$account_group" "/etc/skel/$startup" "/home/debian/$startup"
        fi
    done
    password_status=$(passwd -S debian | awk '{print $2}')
    if [[ $password_status != P ]]; then
        printf '\nElige la contraseña de debian para iniciar sesión. Sudo no la pedirá.\n' >&3
        passwd debian <&3 >&3 2>&3
    fi

    visudo -c >/dev/null
    sudo_tmp=$(mktemp /etc/sudoers.d/.debian-admin-XXXXXX)
    printf 'debian ALL=(ALL:ALL) NOPASSWD: ALL\n' > "$sudo_tmp"
    chmod 0440 "$sudo_tmp"
    visudo -c -f "$sudo_tmp" >/dev/null
    mv -f "$sudo_tmp" /etc/sudoers.d/99-debian-admin
    visudo -c >/dev/null
    runuser -u debian -- sudo -n true

    if [[ -s /root/.ssh/authorized_keys ]]; then
        install -d -m 0700 -o debian -g "$account_group" /home/debian/.ssh
        local public_key
        touch /home/debian/.ssh/authorized_keys
        while IFS= read -r public_key || [[ -n $public_key ]]; do
            [[ -z $public_key ]] && continue
            if ! grep -qxF -- "$public_key" /home/debian/.ssh/authorized_keys; then
                printf '\n%s\n' "$public_key" >> /home/debian/.ssh/authorized_keys
            fi
        done < /root/.ssh/authorized_keys
        chown debian:"$account_group" /home/debian/.ssh/authorized_keys
        chmod 0600 /home/debian/.ssh/authorized_keys
        printf 'Claves públicas autorizadas de root añadidas a debian.\n'
    fi

    printf '\n[3/4] Administración lista. Pasando a debian para instalar las CLI…\n'
    if [[ -f /var/run/reboot-required ]]; then
        printf 'Debian solicita reiniciar. Hazlo al terminar desde Proxmox o con sudo reboot.\n'
    fi
    # su --login proporciona HOME, grupos y entorno propios de debian.
    local user_stage
    user_stage=$(cat <<'DEBIAN_STAGE'
set -Eeuo pipefail
trap 'printf "\nERROR preparando el entorno de debian en línea %s.\n" "$LINENO" >&2' ERR
# Comprueba la terminal antes de tratar una pregunta fallida como respuesta no.
exec 3<>/dev/tty
cd "$HOME"
mkdir -p "$HOME/.local/bin"
for startup in "$HOME/.profile" "$HOME/.bashrc"; do
    if ! grep -qF '# debian-lxc-setup: local bin' "$startup"; then
        cat >> "$startup" <<'LOCAL_PATH'

# debian-lxc-setup: local bin
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
LOCAL_PATH
    fi
done
export PATH="$HOME/.local/bin:$PATH"
ask() {
    local answer
    while true; do
        printf '\n¿Instalar %s para debian? [y/N]: ' "$1" > /dev/tty
        IFS= read -r answer < /dev/tty || return 1
        case "$answer" in
            [yY]|[sS]|[yY][eE][sS]|[sS][iI]) return 0 ;;
            ''|[nN]|[nN][oO]) return 1 ;;
            *) printf 'Responde y o n.\n' > /dev/tty ;;
        esac
    done
}
failed=0
if ask 'Codex'; then
    if (set -o pipefail; curl -fsSL https://chatgpt.com/codex/install.sh | sh) && codex --version; then
        printf 'Codex instalado correctamente.\n'
    else
        printf 'ERROR: Codex no quedó verificado. Puedes reintentar ejecutando este script.\n' >&2
        failed=1
    fi
fi
if ask 'Claude Code'; then
    if (set -o pipefail; curl -fsSL https://claude.ai/install.sh | bash) && claude --version; then
        printf 'Claude Code instalado correctamente.\n'
    else
        printf 'ERROR: Claude Code no quedó verificado. Puedes reintentar ejecutando este script.\n' >&2
        failed=1
    fi
fi
printf '\n[4/4] Ya estás como debian en %s, con sudo sin contraseña.\n' "$HOME"
if (( failed )); then
    printf 'Quedaron instalaciones opcionales con errores (ver arriba).\n'
fi
printf 'Para usar las CLI, ejecuta codex o claude e inicia sesión.\n'
printf 'Para salir de esta sesión de debian: exit.\n\n'
exec /bin/bash -il < /dev/tty
DEBIAN_STAGE
    )
    # --command crea una sesión nueva; --pty le da su propia terminal de control.
    exec su --pty --login debian --shell /bin/bash --command "$user_stage" <&3 3>&-
}

main "$@"
