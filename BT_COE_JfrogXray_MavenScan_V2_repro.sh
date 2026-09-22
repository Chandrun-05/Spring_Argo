#!/bin/bash
# Reproduces Workday run 273 behaviour:
# SUCCESS + reportDetailsFlag=true + scan_output.json never written to workspace

echo "******** Setup Artifactory Connection for Dependency Installation ********"
echo "******** Download Dependencies from Artifactory ********"
jq --version || apt-get install -y -qq jq >/dev/null 2>&1

echo "******** Downloading the maven artifact created in the previous step ********"
ARTIFACT="app-0.0.1-SNAPSHOT.jar"
head -c 20000000 /dev/urandom > "${ARTIFACT}"
echo "Downloaded: ${ARTIFACT}"
ls -l "${ARTIFACT}"

echo "******** Installing JFrog CLI ********"
echo "jf version 2.11.1 (simulated)"

echo "******** Configuring JFrog CLI ********"
echo "Server ID:            artifactory.example.com"

echo "******** Running JFrog Xray Scan ********"
# THE DEFECT: results go to a temp dir, never to the workspace
TMPDIR_RESULT=$(mktemp -d /tmp/jfrog.cli.temp.XXXXXXXXXX)
cat > "${TMPDIR_RESULT}/results.json" <<'EOF'
{"scan":{"vulnerabilities":[],"summary":{"critical":0,"high":0,"medium":0,"low":0}}}
EOF
echo "[Info] [Thread 2] Indexing file: ${ARTIFACT}"
echo "The full scan results are available here: ${TMPDIR_RESULT}"
echo "Note: no context was provided, so no policy could be determined to scan against."
echo "[Info] Scan completed successfully."

echo "******** Parsing Vulnerability Report ********"
echo ""
echo "📋 Reading vulnerabilities…"
echo ""
echo "📊 ****************** Security Issues - Summary ******************"
echo "🔥 Critical=0"
echo "🛑 High=0"
echo "⚠️ Medium=0"
echo "ℹ️ Low=0"
echo "✅ No Critical, High or Medium vulnerabilities found."

OUT_DIR="${WORKSPACE:-$(pwd)}"
cp "${TMPDIR_RESULT}/results.json" "${OUT_DIR}/scan_output.json"

echo "===== DIAG ====="
echo "WORKSPACE='${WORKSPACE}'"
echo "PWD='$(pwd)'"
echo "OUT_DIR='${OUT_DIR}'"
ls -l "${OUT_DIR}/scan_output.json" || echo "scan_output.json NOT FOUND"
ls -l /scan_output.json 2>/dev/null && echo "!! landed at filesystem root — WORKSPACE was empty"
echo "================"

exit 0
