#!/bin/bash

# Lokalny skrypt do uruchamiania skanów bezpieczeństwa

set -e

echo "🔍 Uruchamianie lokalnych skanów bezpieczeństwa..."

# Tworzenie katalogu raportów
mkdir -p reports

# 1. GitLeaks - skanowanie sekretów
echo "📄 Skanowanie sekretów (GitLeaks)..."
if command -v gitleaks &> /dev/null; then
    gitleaks detect --source . --report-format json --report-path reports/gitleaks-report.json
    echo "✅ GitLeaks - zakończone"
else
    echo "⚠️  GitLeaks nie jest zainstalowany"
fi

# 2. NPM Audit - zależności
echo "📦 Skanowanie zależności NPM..."
npm audit --json > reports/npm-audit.json || true
echo "✅ NPM Audit - zakończone"

# 3. OWASP Dependency Check
echo "🔍 OWASP Dependency Check..."
if command -v dependency-check &> /dev/null; then
    dependency-check \
        --project "juice-shop" \
        --scan . \
        --format JSON \
        --format HTML \
        --out reports/ \
        --enableExperimental \
        --failOnCVSS 7 || true
    echo "✅ Dependency Check - zakończone"
else
    echo "⚠️  OWASP Dependency Check nie jest zainstalowany"
fi

# 4. Semgrep - SAST
echo "🔍 Analiza statyczna (Semgrep)..."
if command -v semgrep &> /dev/null; then
    semgrep --config=auto --json --output=reports/semgrep-results.json . || true
    echo "✅ Semgrep - zakończone"
else
    echo "⚠️  Semgrep nie jest zainstalowany"
fi

# 5. Budowanie i skanowanie obrazu Docker
echo "🐳 Budowanie obrazu Docker..."
docker build -t juice-shop-security:latest -f docker/Dockerfile .

echo "🔍 Skanowanie obrazu Docker (Trivy)..."
if command -v trivy &> /dev/null; then
    trivy image --format json --output reports/trivy-report.json juice-shop-security:latest
    echo "✅ Trivy - zakończone"
else
    echo "⚠️  Trivy nie jest zainstalowany"
fi

# 6. Uruchomienie DAST (ZAP)
echo "🕷️  Przygotowanie do DAST..."
docker-compose -f docker/docker-compose.yml up -d

# Oczekiwanie na uruchomienie aplikacji
echo "⏳ Oczekiwanie na uruchomienie aplikacji..."
timeout 120 bash -c 'until curl -f http://localhost:3000/rest/admin/application-version; do sleep 5; done'

echo "🔍 OWASP ZAP Baseline Scan..."
docker run -v $(pwd):/zap/wrk/:rw \
    -t owasp/zap2docker-stable \
    zap-baseline.py \
    -t http://host.docker.internal:3000 \
    -J zap-report.json \
    -r zap-report.html || true

mv zap-report.* reports/ 2>/dev/null || true

# Zatrzymanie kontenerów
docker-compose -f docker/docker-compose.yml down

echo "✅ Wszystkie skany zakończone!"
echo "📊 Raporty dostępne w katalogu: reports/"

# Generowanie podsumowania
echo "📋 Generowanie podsumowania..."
cat > reports/summary.txt << EOF
=== PODSUMOWANIE SKANÓW BEZPIECZEŃSTWA ===
Data: $(date)
Commit: $(git rev-parse --short HEAD)

Wykonane skany:
- GitLeaks (secrets): $([ -f reports/gitleaks-report.json ] && echo "✅" || echo "❌")
- NPM Audit (dependencies): $([ -f reports/npm-audit.json ] && echo "✅" || echo "❌")
- OWASP Dependency Check: $([ -f reports/dependency-check-report.json ] && echo "✅" || echo "❌")
- Semgrep (SAST): $([ -f reports/semgrep-results.json ] && echo "✅" || echo "❌")
- Trivy (container): $([ -f reports/trivy-report.json ] && echo "✅" || echo "❌")
- OWASP ZAP (DAST): $([ -f reports/zap-report.json ] && echo "✅" || echo "❌")

Sprawdź szczegółowe raporty w katalogu reports/
EOF

echo "✅ Skrypt zakończony pomyślnie!"
