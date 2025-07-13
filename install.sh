#!/bin/bash

# Instalador de LoveBox - ¡Dios te bendiga mucho!
# Versión 1.0

# Verificar si se ejecuta como root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error while installing :C"
    echo "Cannot process action because you are not sudo :C"
    exit 1
fi

# Mostrar mensaje de bienvenida
echo ""
echo "Welcome and God bless to the LoveBox installer!"
echo "We will install LoveBox.."
echo ""
echo "Installing LoveBox.."
echo ""

# Crear el script en /usr/bin/lovebox
echo "Creating /usr/bin/lovebox..."
cat > /usr/bin/lovebox << 'EOF'
#!/usr/bin/python3
import os
import json
import argparse
import tempfile
import subprocess
import datetime
import struct
import shutil
import glob
from pathlib import Path

# Constantes
LOVEBOX_MAGIC = b'LOVEBOXv1'
QEMU_CMD = "qemu-system-x86_64"

def create_vm(name, storage, params):
    """Crea una nueva máquina virtual LoveBox"""
    # Crear estructura de directorios
    os.makedirs(name, exist_ok=True)
    os.makedirs(os.path.join(name, "disk"), exist_ok=True)
    os.makedirs(os.path.join(name, "LoveBox"), exist_ok=True)

    # Crear settings.json principal
    main_settings = {
        "name": name,
        "created_date": datetime.datetime.now().isoformat(),
        "qemu_params": params,
        "storage": storage,
        "last_modified": datetime.datetime.now().isoformat()
    }

    with open(os.path.join(name, "settings.json"), 'w') as f:
        json.dump(main_settings, f, indent=4)

    # Crear LoveBox settings
    lovebox_settings = {
        "type": "virtual_machine",
        "version": "1.0",
        "features": ["qemu_compatible", "persistent_storage"]
    }

    with open(os.path.join(name, "LoveBox", "settings.json"), 'w') as f:
        json.dump(lovebox_settings, f, indent=4)

    # Crear disco virtual
    disk_path = os.path.join(name, "disk", "disk.qcow2")
    subprocess.run(["qemu-img", "create", "-f", "qcow2", disk_path, storage], check=True)

    print(f"\nLoveBox '{name}' creada con éxito!")
    print(f"  Almacenamiento: {storage}")
    print(f"  Parámetros QEMU: {params}")

def pack_box():
    """Empaqueta el directorio actual en formato .box"""
    cwd = os.path.basename(os.getcwd())
    output_file = cwd + ".box"

    # Verificar estructura básica
    if not os.path.exists("settings.json") or not os.path.exists("LoveBox/settings.json"):
        print("Error: No se detectó una estructura LoveBox válida")
        return

    # Crear archivo .box
    with open(output_file, 'wb') as f:
        # Escribir cabecera
        f.write(LOVEBOX_MAGIC)

        # Empaquetar todos los archivos
        for file_path in glob.glob('**', recursive=True):
            if os.path.isdir(file_path):
                continue

            # Leer contenido
            with open(file_path, 'rb') as content_file:
                content = content_file.read()

            # Escribir metadata
            relative_path = Path(file_path).as_posix().encode('utf-8')
            f.write(struct.pack('I', len(relative_path)))
            f.write(relative_path)
            f.write(struct.pack('Q', len(content)))
            f.write(content)

    print(f"\nLoveBox empaquetada en '{output_file}'!")
    print("  Puedes ejecutarla con: lovebox run " + output_file)

def unpack_box(box_file):
    """Desempaqueta un archivo .box"""
    if not box_file.endswith('.box'):
        print("Error: El archivo debe tener extensión .box")
        return

    # Crear directorio de destino
    dir_name = os.path.basename(box_file)[:-4]
    os.makedirs(dir_name, exist_ok=True)

    with open(box_file, 'rb') as f:
        # Verificar cabecera
        magic = f.read(len(LOVEBOX_MAGIC))
        if magic != LOVEBOX_MAGIC:
            print("Error: Formato de archivo inválido")
            return

        # Extraer archivos
        while True:
            # Leer metadata
            len_path_data = f.read(4)
            if not len_path_data:
                break

            len_path = struct.unpack('I', len_path_data)[0]
            path = f.read(len_path).decode('utf-8')
            content_size = struct.unpack('Q', f.read(8))[0]
            content = f.read(content_size)

            # Crear directorios si son necesarios
            full_path = os.path.join(dir_name, path)
            os.makedirs(os.path.dirname(full_path), exist_ok=True)

            # Escribir contenido
            with open(full_path, 'wb') as out_file:
                out_file.write(content)

    print(f"\nLoveBox desempaquetada en '{dir_name}/'")
    print("  Puedes modificar los archivos y luego empaquetar con: lovebox pack")

def run_box(box_file):
    """Ejecuta una LoveBox desde un archivo .box"""
    if not os.path.exists(box_file):
        print(f"Error: Archivo '{box_file}' no encontrado")
        return

    # Crear directorio temporal
    with tempfile.TemporaryDirectory() as tmpdir:
        # Desempaquetar en temporal
        with open(box_file, 'rb') as f:
            magic = f.read(len(LOVEBOX_MAGIC))
            if magic != LOVEBOX_MAGIC:
                print("Error: Formato de archivo inválido")
                return

            while True:
                len_path_data = f.read(4)
                if not len_path_data:
                    break

                len_path = struct.unpack('I', len_path_data)[0]
                path = f.read(len_path).decode('utf-8')
                content_size = struct.unpack('Q', f.read(8))[0]
                content = f.read(content_size)

                full_path = os.path.join(tmpdir, path)
                os.makedirs(os.path.dirname(full_path), exist_ok=True)

                with open(full_path, 'wb') as out_file:
                    out_file.write(content)

        # Leer configuración
        config_path = os.path.join(tmpdir, "settings.json")
        if not os.path.exists(config_path):
            print("Error: Configuración no encontrada")
            return

        with open(config_path) as f:
            config = json.load(f)

        # Construir comando QEMU
        disk_path = os.path.join(tmpdir, "disk", "disk.qcow2")
        qemu_cmd = [
            QEMU_CMD,
            "-drive", f"file={disk_path},format=qcow2",
            "-name", config["name"]
        ]

        # Añadir parámetros adicionales
        if config["qemu_params"]:
            qemu_cmd.extend(config["qemu_params"].split())

        # Ejecutar QEMU
        print("\nIniciando LoveBox...")
        print(f"  Máquina: {config['name']}")
        print(f"  Comando: {' '.join(qemu_cmd)}\n")

        try:
            subprocess.run(qemu_cmd, check=True)
        except subprocess.CalledProcessError:
            print("\nQEMU terminó con errores")
        except KeyboardInterrupt:
            print("\nEjecución interrumpida")

        # Re-empaquetar después de ejecutar
        print("\nGuardando estado de la LoveBox...")
        temp_box = box_file + ".tmp"

        with open(temp_box, 'wb') as f:
            f.write(LOVEBOX_MAGIC)

            for root, _, files in os.walk(tmpdir):
                for file in files:
                    file_path = os.path.join(root, file)
                    rel_path = os.path.relpath(file_path, tmpdir)

                    with open(file_path, 'rb') as content_file:
                        content = content_file.read()

                    encoded_path = rel_path.encode('utf-8')
                    f.write(struct.pack('I', len(encoded_path)))
                    f.write(encoded_path)
                    f.write(struct.pack('Q', len(content)))
                    f.write(content)

        shutil.move(temp_box, box_file)
        print(f"LoveBox actualizada: {box_file}")

def main():
    parser = argparse.ArgumentParser(
        description="LoveBox - Herramienta para crear y ejecutar máquinas virtuales",
        epilog="Dios te bendiga mucho! ❤"
    )

    subparsers = parser.add_subparsers(dest='command', required=True)

    # Comando: create
    create_parser = subparsers.add_parser('create', help='Crear nueva LoveBox')
    create_parser.add_argument('name', help='Nombre de la LoveBox')
    create_parser.add_argument('--storage', required=True, help='Tamaño de almacenamiento (ej: 35G)')
    create_parser.add_argument('--params', default='', help='Parámetros adicionales para QEMU')

    # Comando: pack
    pack_parser = subparsers.add_parser('pack', help='Empaquetar LoveBox actual')

    # Comando: run
    run_parser = subparsers.add_parser('run', help='Ejecutar LoveBox')
    run_parser.add_argument('box_file', help='Archivo .box a ejecutar')

    # Comando: unpack
    unpack_parser = subparsers.add_parser('unpack', help='Desempaquetar LoveBox')
    unpack_parser.add_argument('box_file', help='Archivo .box a desempaquetar')

    args = parser.parse_args()

    try:
        if args.command == 'create':
            create_vm(args.name, args.storage, args.params)
        elif args.command == 'pack':
            pack_box()
        elif args.command == 'run':
            run_box(args.box_file)
        elif args.command == 'unpack':
            unpack_box(args.box_file)
    except Exception as e:
        print(f"\nError: {str(e)}")
        print("Por favor verifica tus parámetros e intenta nuevamente")

if __name__ == "__main__":
    main()
EOF

# Dar permisos de ejecución
echo "Giving execution permmisions.."
chmod +x /usr/bin/lovebox

# Verificar dependencias
echo ""
echo "Verificando dependencias..."
if ! command -v qemu-system-x86_64 &> /dev/null; then
    echo "  QEMU no está instalado. Intentando instalar..."
    if command -v apt &> /dev/null; then
        apt update
        apt install -y qemu-system qemu-utils
    elif command -v pacman &> /dev/null; then
        pacman -Sy --noconfirm qemu-full
    elif command -v dnf &> /dev/null; then
        dnf install -y qemu-system-x86-core qemu-img
    else
        echo "  No se pudo determinar el gestor de paquetes."
        echo "  Por favor instala QEMU manualmente:"
        echo "    Debian/Ubuntu: sudo apt install qemu-system qemu-utils"
        echo "    Arch/Manjaro: sudo pacman -S qemu-full"
        echo "    Fedora: sudo dnf install qemu-system-x86-core qemu-img"
    fi
fi

# Instalar archivo .desktop para integración
echo ""
echo "Configurando integración con el sistema..."
mkdir -p /usr/share/applications
cat > /usr/share/applications/lovebox.desktop << 'EOF'
[Desktop Entry]
Name=LoveBox Runner
Comment=Ejecuta máquinas virtuales LoveBox
Exec=lovebox run %f
Icon=virtualbox
Terminal=true
Type=Application
MimeType=application/x-lovebox;
Categories=System;Emulator;
Keywords=virtual;machine;emulator;
StartupNotify=true
EOF

# Configurar tipo MIME
mkdir -p /usr/share/mime/packages
cat > /usr/share/mime/packages/lovebox.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-lovebox">
    <comment>LoveBox Virtual Machine</comment>
    <glob pattern="*.box"/>
    <icon name="application-x-lovebox"/>
  </mime-type>
</mime-info>
EOF

# Actualizar bases de datos
update-mime-database /usr/share/mime
update-desktop-database /usr/share/applications

# Instalar icono
echo ""
echo "Installing icons.."
mkdir -p /usr/share/icons/hicolor/48x48/mimetypes
wget -q -O /usr/share/icons/hicolor/48x48/mimetypes/application-x-lovebox.png https://img.icons8.com/color/48/virtual-machine.png

# Crear asociación de archivos
xdg-mime default lovebox.desktop application/x-lovebox

# Mensaje final
echo ""
echo "The installation is Done thank GOD!"
echo "  LoveBox is now installed on the system with love!"
echo "  You can execute .box files with double click!"
echo ""
echo "Use examples:"
echo "  lovebox create \"MyVM\" --storage 20G --params=\"-m 2G -cdrom alpine.iso\""
echo "  lovebox pack (On the Virtual Machine directory)"
echo "  lovebox run MyVM.box"
echo ""
echo "Done! God bless you :D"
echo "God bless your day and projects with love! 🙏"
