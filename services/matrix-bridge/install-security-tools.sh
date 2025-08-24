#!/bin/bash
# Security Tools Installation Script for Matrix Bridge
# This script installs security scanning tools for the Matrix bridge

echo "🛡️ Matrix Bridge Security Tools Installation"
echo "================================================="

# Check if running as root or with sudo
if [[ $EUID -eq 0 ]]; then
    APT_CMD="apt"
elif command -v sudo &> /dev/null; then
    APT_CMD="sudo apt"
else
    echo "❌ This script requires root privileges or sudo access."
    echo "Please run with sudo or as root user."
    exit 1
fi

echo "🔧 Updating package repositories..."
$APT_CMD update

echo "🔧 Installing Python security tools..."

# Install system packages for security tools
PACKAGES=(
    "python3-bandit"           # Static security analysis
    "python3-flake8"           # Code quality checker
    "python3-pip"              # For safety installation via pip if needed
    "python3-venv"             # Virtual environment support
)

for package in "${PACKAGES[@]}"; do
    echo "Installing $package..."
    if $APT_CMD install -y "$package"; then
        echo "✅ $package installed successfully"
    else
        echo "⚠️ Failed to install $package (may already be installed)"
    fi
done

echo ""
echo "🔧 Installing safety tool via pip..."
# Safety is not available as a system package, so we'll create a virtual environment
python3 -m venv /tmp/security-tools-venv
source /tmp/security-tools-venv/bin/activate
pip install safety
deactivate

# Create wrapper script for safety
cat > /usr/local/bin/safety-wrapper << 'EOF'
#!/bin/bash
source /tmp/security-tools-venv/bin/activate
safety "$@"
deactivate
EOF

chmod +x /usr/local/bin/safety-wrapper

echo ""
echo "🔧 Creating security tool configuration files..."

# Create .bandit configuration
cat > .bandit << 'EOF'
[bandit]
# Bandit Security Configuration for Matrix Bridge
exclude_dirs = tests,.git,__pycache__,reports,docs
confidence = HIGH
severity = HIGH

[bandit.assert_used]
# Skip assert checks in test files
skips = ["**/test_*.py", "*/tests/*"]

[bandit.hardcoded_password_string]
# Skip enum constants that look like secrets but aren't
exclude = ["*/audit.py:*INVALID_TOKEN*"]
EOF

# Create .flake8 configuration
cat > .flake8 << 'EOF'
[flake8]
max-line-length = 100
max-complexity = 12
exclude = 
    .git,
    __pycache__,
    .pytest_cache,
    reports,
    tests/fixtures,
    docs

ignore = 
    E203,  # Whitespace before ':'
    W503,  # Line break before binary operator
    E501   # Line too long (handled by max-line-length)

per-file-ignores =
    __init__.py: F401  # Unused imports in __init__.py are OK
EOF

echo ""
echo "🔍 Running security scans..."

# Ensure reports directory exists
mkdir -p reports

# Run Bandit scan
echo "📊 Running Bandit security analysis..."
if command -v bandit &> /dev/null; then
    if bandit -r src/ -f json -o reports/bandit-report.json 2>/dev/null; then
        echo "✅ Bandit scan completed"
    else
        echo "⚠️ Bandit found potential security issues"
        echo "Check reports/bandit-report.json for details"
    fi
else
    echo "❌ Bandit not available"
fi

# Run Safety scan
echo "🛡️ Running Safety dependency scan..."
if /usr/local/bin/safety-wrapper check --json --output reports/safety-report.json 2>/dev/null; then
    echo "✅ Safety scan completed - no vulnerabilities found"
else
    echo "⚠️ Safety scan completed - check reports/safety-report.json"
fi

# Run Flake8 scan
echo "📝 Running Flake8 code quality check..."
if command -v flake8 &> /dev/null; then
    if flake8 src/ --output-file=reports/flake8-report.txt 2>/dev/null; then
        echo "✅ Flake8 check completed - no issues found"
    else
        echo "⚠️ Flake8 found code quality issues"
        echo "Check reports/flake8-report.txt for details"
    fi
else
    echo "❌ Flake8 not available"
fi

echo ""
echo "================================================="
echo "✅ Security tools installation completed!"
echo ""
echo "📊 Installed Tools:"
echo "   - Bandit: Python static security analysis"
echo "   - Flake8: Code quality and style checker"
echo "   - Safety: Dependency vulnerability scanner"
echo ""
echo "📋 Configuration Files Created:"
echo "   - .bandit: Bandit security scanner configuration"
echo "   - .flake8: Flake8 code quality configuration"
echo ""
echo "📁 Reports Generated:"
echo "   - reports/bandit-report.json: Security analysis results"
echo "   - reports/safety-report.json: Dependency vulnerability scan"
echo "   - reports/flake8-report.txt: Code quality analysis"
echo ""
echo "🔄 Next Steps:"
echo "   1. Review the generated reports for any security issues"
echo "   2. Run 'python3 security-validation.py' to verify fixes"
echo "   3. Address any remaining security findings"
echo "   4. Set up automated security scanning in CI/CD"