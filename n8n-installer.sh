#!/bin/bash

# Colores para la salida
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Instalador de n8n ===${NC}"

# Solicitar información básica
read -p "Ingresa el subdominio para n8n (ej: n8n): " SUBDOMAIN
read -p "Ingresa el dominio (ej: ejemplo.com): " DOMAIN_NAME
read -p "Ingresa tu email (para SSL): " SSL_EMAIL

# Generar claves seguras
ENCRYPTION_KEY=$(openssl rand -hex 16)
POSTGRES_PASSWORD=$(openssl rand -hex 16)
POSTGRES_NON_ROOT_PASSWORD=$(openssl rand -hex 16)

# Instalar Docker y Docker Compose
echo -e "${BLUE}Instalando Docker y Docker Compose...${NC}"

# Actualizar sistema e instalar dependencias
sudo apt update
sudo apt install -y docker.io ca-certificates curl gnupg lsb-release

# Crear directorio para keyrings
sudo mkdir -p /etc/apt/keyrings

# Actualizar nuevamente
sudo apt-get update

# Iniciar y habilitar Docker
sudo systemctl start docker
sudo systemctl enable docker

# Instalar Docker Compose
echo -e "${BLUE}Instalando Docker Compose...${NC}"
sudo curl -L "https://github.com/docker/compose/releases/download/v2.32.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verificar instalaciones
if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Error: La instalación de Docker o Docker Compose falló.${NC}"
    exit 1
fi

echo -e "${GREEN}Docker y Docker Compose instalados correctamente${NC}"

# Crear directorio de instalación
mkdir -p n8n-docker && cd n8n-docker

# Crear archivo .env
cat > .env << EOF
DOMAIN_NAME=$DOMAIN_NAME
SUBDOMAIN=$SUBDOMAIN
SSL_EMAIL=$SSL_EMAIL
GENERIC_TIMEZONE=UTC

# PostgreSQL
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=n8n
POSTGRES_NON_ROOT_USER=n8n
POSTGRES_NON_ROOT_PASSWORD=$POSTGRES_NON_ROOT_PASSWORD

# N8N
ENCRYPTION_KEY=$ENCRYPTION_KEY
EOF

# Crear docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'

volumes:
  db_storage:
  n8n_storage:
  redis_storage:
  traefik_data:

x-n8n: &service-n8n
  restart: always
  image: n8nio/n8n:latest
  volumes:
    - n8n_storage:/home/node/.n8n
  depends_on:
    redis:
      condition: service_healthy
    postgres:
      condition: service_healthy

x-n8n-environment: &n8n-environment
  DB_TYPE: postgresdb
  DB_POSTGRESDB_HOST: postgres
  DB_POSTGRESDB_PORT: "5432"
  DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
  DB_POSTGRESDB_USER: ${POSTGRES_NON_ROOT_USER}
  DB_POSTGRESDB_PASSWORD: ${POSTGRES_NON_ROOT_PASSWORD}
  EXECUTIONS_MODE: queue
  QUEUE_BULL_REDIS_HOST: redis
  QUEUE_HEALTH_CHECK_ACTIVE: "true"
  N8N_ENCRYPTION_KEY: ${ENCRYPTION_KEY}
  N8N_HOST: ${SUBDOMAIN}.${DOMAIN_NAME}
  N8N_PORT: "5678"
  N8N_PROTOCOL: https
  NODE_ENV: production
  N8N_EDITOR_BASE_URL: https://${SUBDOMAIN}.${DOMAIN_NAME}
  WEBHOOK_URL: https://${SUBDOMAIN}.${DOMAIN_NAME}
  GENERIC_TIMEZONE: ${GENERIC_TIMEZONE}

services:
  traefik:
    image: traefik:latest
    restart: always
    command:
      - "--api=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.mytlschallenge.acme.tlschallenge=true"
      - "--certificatesresolvers.mytlschallenge.acme.email=${SSL_EMAIL}"
      - "--certificatesresolvers.mytlschallenge.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - traefik_data:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro

  postgres:
    image: postgres:16
    restart: always
    environment:
      - POSTGRES_USER
      - POSTGRES_PASSWORD
      - POSTGRES_DB
      - POSTGRES_NON_ROOT_USER
      - POSTGRES_NON_ROOT_PASSWORD
    volumes:
      - db_storage:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h localhost -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 10

  redis:
    image: redis:7-alpine
    restart: always
    volumes:
      - redis_storage:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 10

  n8n:
    <<: *service-n8n
    environment:
      <<: *n8n-environment
    labels:
      - traefik.enable=true
      - traefik.http.routers.n8n.rule=Host(`${SUBDOMAIN}.${DOMAIN_NAME}`)
      - traefik.http.routers.n8n.tls=true
      - traefik.http.routers.n8n.entrypoints=websecure
      - traefik.http.routers.n8n.tls.certresolver=mytlschallenge
EOF

# Crear script de inicialización de base de datos
cat > init-data.sh << 'EOF'
#!/bin/bash
set -e;

# Configuración para n8n
if [ -n "${POSTGRES_NON_ROOT_USER:-}" ] && [ -n "${POSTGRES_NON_ROOT_PASSWORD:-}" ]; then
	psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
		CREATE USER ${POSTGRES_NON_ROOT_USER} WITH PASSWORD '${POSTGRES_NON_ROOT_PASSWORD}';
		GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_NON_ROOT_USER};
		GRANT CREATE ON SCHEMA public TO ${POSTGRES_NON_ROOT_USER};
	EOSQL
	echo "SETUP INFO: Usuario para n8n creado correctamente."
else
	echo "SETUP INFO: No se proporcionaron variables de entorno para n8n!"
fi
EOF

chmod +x init-data.sh

echo -e "${GREEN}Instalación preparada!${NC}"
echo -e "${BLUE}Para iniciar n8n, ejecuta:${NC}"
echo "docker-compose up -d"
echo
echo -e "${BLUE}Tu n8n estará disponible en:${NC}"
echo "https://$SUBDOMAIN.$DOMAIN_NAME"
echo
echo -e "${BLUE}Credenciales generadas guardadas en el archivo .env${NC}" 