# Instalador de n8n

Este script automatiza la instalación de n8n usando Docker y Docker Compose, incluyendo Traefik como proxy inverso con soporte SSL automático.

## Requisitos

- Ubuntu 20.04 LTS
- Acceso root o sudo
- Dominio configurado apuntando al servidor

## Características

- Instalación automatizada de Docker y Docker Compose
- Configuración de Traefik como proxy inverso
- Certificados SSL automáticos con Let's Encrypt
- Base de datos PostgreSQL persistente
- Redis para caché
- Volúmenes Docker para persistencia de datos

## Uso

1. Descarga el script:
   ```bash
   wget https://raw.githubusercontent.com/tu-usuario/n8n-installer/main/n8n-installer.sh
   ```

2. Dale permisos de ejecución:
   ```bash
   chmod +x n8n-installer.sh
   ```

3. Ejecuta el script:
   ```bash
   ./n8n-installer.sh
   ```

4. Sigue las instrucciones en pantalla para configurar:
   - Dominio
   - Subdominio
   - Email (para certificados SSL)

## Notas Importantes

- Asegúrate de que los puertos 80 y 443 estén abiertos en tu firewall
- El script generará automáticamente las credenciales necesarias
- Toda la configuración se guardará en el archivo .env

