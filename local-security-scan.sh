#!/bin/bash

# Skrypt do lokalnego uruchamiania testów bezpieczeństwa
# Użycie: ./local-security-scan.sh

set -e

echo "🔒 Rozpoczynam lokalne testy bezpieczeństwa dla OWASP Juice Shop"

# Tworzenie katalogu na raporty
mkdir -p reports

echo "📦 1. SCA - Software Composition Analysis"
echo "Uruchamianie npm audit..."
npm audit --audit-level=high --production > reports/npm-audit.txt 2>&1 || true
npm audit --json --audit-level=high --production > reports/npm-audit.json 2>&1 || true

echo "Pobieranie OWASP Dependency Check..."
if [ ! -d "dependency-check" ]; then
    wget -q https://github.com/jeremylong/DependencyCheck/releases/download/v8.4.0/dependency-check-8.4.0-release.zip
    unzip -q dependency-check-8.4.0-release.zip
fi

echo "Uruchamianie OWASP Dependency Check..."
./dependency-check/bin/dependency-check.sh \
    --project "Juice Shop Local Scan" \
    --scan . \
    --format JSON \
    --format HTML \
    --out ./reports \
    --suppression ./suppress.xml 2>/dev/null || true

echo "🔍 2. SAST - Static Application Security Testing"
echo "Instalowanie i uruchamianie Semgrep..."
pip3 install semgrep --quiet 2>/dev/null || true
semgrep --config=p/security-audit --config=p/secrets --config=p/owasp-top-ten --json --output=reports/semgrep.json . || true

echo "Instalowanie i uruchamianie Bandit (dla plików Python)..."
pip3 install bandit --quiet 2>/dev/null || true
bandit -r . -f json -o reports/bandit.json 2>/dev/null || true

echo "🔑 3. Secrets Scanning"
echo "Instalowanie i uruchamianie TruffleHog..."
if ! command -v trufflehog &> /dev/null; then
    echo "Instalowanie TruffleHog..."
    if command -v go &> /dev/null; then
        go install github.com/trufflesecurity/trufflehog/v3@latest
    else
        echo "⚠️  Go nie jest zainstalowane. Pomijam TruffleHog."
    fi
fi

if command -v trufflehog &> /dev/null; then
    trufflehog filesystem --directory=. --json > reports/trufflehog.json 2>/dev/null || true
fi

echo "Instalowanie i uruchamianie GitLeaks..."
if ! command -v gitleaks &> /dev/null; then
    echo "Pobieranie GitLeaks..."
    wget -q https://github.com/gitleaks/gitleaks/releases/download/v8.18.0/gitleaks_8.18.0_linux_x64.tar.gz
    tar -xzf gitleaks_8.18.0_linux_x64.tar.gz
    sudo mv gitleaks /usr/local/bin/ 2>/dev/null || mv gitleaks ~/bin/ 2>/dev/null || true
fi

if command -v gitleaks &> /dev/null; then
    gitleaks detect --source . --report-format json --report-path reports/gitleaks.json 2>/dev/null || true
fi

echo "🌐 4. DAST - Dynamic Application Security Testing"
echo "Budowanie aplikacji Docker..."
docker build -t juice-shop:security-test . > /dev/null 2>&1

echo "Uruchamianie aplikacji..."
docker run -d --name juice-shop-security-test -p 3001:3000 juice-shop:security-test > /dev/null 2>&1

echo "Oczekiwanie na uruchomienie aplikacji..."
sleep 30

# Sprawdzenie czy aplikacja odpowiada
timeout 60 bash -c 'while ! curl -s http://localhost:3001 > /dev/null; do sleep 2; done' || {
    echo "⚠️  Aplikacja nie odpowiada. Sprawdź logi:"
    docker logs juice-shop-security-test
    docker stop juice-shop-security-test 2>/dev/null || true
    docker rm juice-shop-security-test 2>/dev/null || true
    exit 1
}

echo "Uruchamianie OWASP ZAP..."
docker run --rm -v $(pwd)/reports:/zap/wrk/:rw \
    --network host \
    owasp/zap2docker-stable \
    zap-baseline.py \
    -t http://127.0.0.1:3001 \
    -J zap-report.json \
    -r zap-report.html 2>/dev/null || true

echo "Uruchamianie Nikto..."
docker run --rm --network host \
    -v $(pwd)/reports:/tmp \
    sullo/nikto \
    -h http://127.0.0.1:3001 \
    -Format json \
    -output /tmp/nikto-report.json 2>/dev/null || true

echo "Zatrzymywanie kontenerów..."
docker stop juice-shop-security-test 2>/dev/null || true
docker rm juice-shop-security-test 2>/dev/null || true

echo "📊 5. Generowanie podsumowania"
cat > reports/security-summary.txt << EOF
=== RAPORT BEZPIECZEŃSTWA OWASP JUICE SHOP ===
Data: $(date)

1. SCA (Software Composition Analysis):
   - npm audit: reports/npm-audit.json
   - OWASP Dependency Check: reports/dependency-check-report.json

2. SAST (Static Application Security Testing):
   - Semgrep: reports/semgrep.json
   - Bandit: reports/bandit.json

3. Secrets Scanning:
   - TruffleHog: reports/trufflehog.json
   - GitLeaks: reports/gitleaks.json

4. DAST (Dynamic Application Security Testing):
   - OWASP ZAP: reports/zap-report.json, reports/zap-report.html
   - Nikto: reports/nikto-report.json

UWAGA: Sprawdź wszystkie raporty i napraw podatności o wysokim/krytycznym priorytecie.
EOF

echo "✅ Testy bezpieczeństwa zakończone!"
echo "📁 Raporty dostępne w katalogu: reports/"
echo "📄 Podsumowanie: reports/security-summary.txt"

# Pokaż podstawowe statystyki
echo ""
echo "📈 Podstawowe statystyki:"
echo "- Pliki przeskanowane: $(find . -type f -name "*.js" -o -name "*.json" -o -name "*.py" | wc -l)"
echo "- Rozmiar repozytorium: $(du -sh . | cut -f1)"

if [ -f "reports/semgrep.json" ]; then
    SEMGREP_ISSUES=$(jq '.results | length' reports/semgrep.json 2>/dev/null || echo "0")
    echo "- Problemy znalezione przez Semgrep: $SEMGREP_ISSUES"
fi

if [ -f "reports/zap-report.json" ]; then
    ZAP_ALERTS=$(jq '.site[0].alerts | length' reports/zap-report.json 2>/dev/null || echo "0")
    echo "- Alerty ZAP: $ZAP_ALERTS"
fi

echo ""
echo "🔧 Następne kroki:"
echo "1. Przejrzyj raporty w katalogu reports/"
echo "2. Zidentyfikuj podatności High/Critical"
echo "3. Napraw minimum 2-3 podatności w każdej kategorii"
echo "4. Zaktualizuj zależności i kod"
echo "5. Uruchom ponownie testy"
