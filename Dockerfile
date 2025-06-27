# Użyj oficjalnego obrazu Node.js
FROM node:18-alpine

# Ustaw katalog roboczy
WORKDIR /juice-shop

# Skopiuj pliki package.json
COPY package*.json ./

# Zainstaluj zależności

# Skopiuj resztę aplikacji
COPY . .

# Ustaw zmienną środowiskową
ENV NODE_ENV=production

# Otwórz port 3000
EXPOSE 3000

# Utwórz użytkownika bez uprawnień root
RUN addgroup -g 1001 -S nodejs
RUN adduser -S juicer -u 1001
RUN chown -R juicer:nodejs /juice-shop
USER juicer

# Uruchom aplikację
CMD ["npm", "start"]
