#!/bin/bash
# Repro for Zendesk 4612 - Report tab on command-line step
# Toggle WRITE_REPORT to switch between failing (A) and working (B) case.

WRITE_REPORT=true   # false = reproduce Workday 273 (no report); true = expected working case

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
# Mirrors Workday V2: scan output lands in a temp dir, not the workspace
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
echo "Reading vulnerabilities..."
echo ""
echo "****************** Security Issues - Summary ******************"
echo "Critical=0"
echo "High=0"
echo "Medium=0"
echo "Low=0"
echo "No Critical, High or Medium vulnerabilities found."

OUT_DIR="${WORKSPACE:-$(pwd)}"

if [ "${WRITE_REPORT}" = "true" ]; then
    cp "${TMPDIR_RESULT}/results.json" "${OUT_DIR}/scan_output.json"
fi

echo "===== DIAG ====="
echo "WRITE_REPORT='${WRITE_REPORT}'"
echo "WORKSPACE='${WORKSPACE}'"
echo "PWD='$(pwd)'"
echo "OUT_DIR='${OUT_DIR}'"
ls -l "${OUT_DIR}/scan_output.json" || echo "scan_output.json NOT PRESENT"
echo "================"

exit 0
