# Dockerfile dla OWASP Juice Shop
FROM node:18-alpine

# Metadata
LABEL maintainer="adresmailowyfajny@com.com"
LABEL description="OWASP Juice Shop - DevSecOps Pipeline"

# Utworzenie użytkownika aplikacji (zasada najmniejszych uprawnień)
RUN addgroup -g 1001 -S nodejs && \
    adduser -S juiceshop -u 1001

# Ustawienie katalogu roboczego
WORKDIR /juice-shop

# Kopiowanie plików package
COPY package*.json ./

# Instalacja zależności produkcyjnych
RUN npm ci --only=production && npm cache clean --force

# Kopiowanie kodu aplikacji
COPY --chown=juiceshop:nodejs . .

# Ustawienie uprawnień
RUN chown -R juiceshop:nodejs /juice-shop

# Przełączenie na użytkownika aplikacji
USER juiceshop

# Ekspozycja portu
EXPOSE 3000

# Zdrowie kontenera
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/rest/admin/application-version || exit 1

# Uruchomienie aplikacji
CMD ["npm", "start"]
