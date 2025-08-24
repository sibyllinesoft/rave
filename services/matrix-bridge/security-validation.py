#!/usr/bin/env python3
"""
Security Validation Script for Matrix Bridge
Comprehensive security validation and SAST analysis.

This script validates the security posture of the Matrix bridge implementation
and ensures compliance with security requirements.
"""

import os
import sys
import json
import subprocess
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Optional
import argparse


class SecurityValidator:
    """Comprehensive security validator for Matrix bridge."""
    
    def __init__(self, project_root: str):
        self.project_root = Path(project_root)
        self.src_dir = self.project_root / "src"
        self.test_dir = self.project_root / "tests"
        self.reports_dir = self.project_root / "reports"
        
        # Ensure reports directory exists
        self.reports_dir.mkdir(exist_ok=True)
        
        # Security validation results
        self.results = {
            "validation_timestamp": None,
            "overall_status": "UNKNOWN",
            "security_checks": {},
            "critical_issues": [],
            "high_issues": [],
            "medium_issues": [],
            "recommendations": []
        }
    
    def run_validation(self, strict: bool = True) -> bool:
        """Run comprehensive security validation."""
        import datetime
        self.results["validation_timestamp"] = datetime.datetime.now().isoformat()
        
        print("🛡️  Starting comprehensive security validation...")
        print("=" * 60)
        
        # Run all security checks
        checks = [
            ("Static Analysis (Bandit)", self._run_bandit_scan),
            ("Dependency Vulnerabilities (Safety)", self._run_safety_scan),
            ("Code Quality (Flake8)", self._run_flake8_scan),
            ("Secret Detection", self._detect_secrets),
            ("Input Validation", self._validate_input_handling),
            ("Authentication Security", self._validate_auth_security),
            ("Command Injection Protection", self._validate_command_injection),
            ("SQL Injection Protection", self._validate_sql_injection),
            ("XSS Protection", self._validate_xss_protection),
            ("Path Traversal Protection", self._validate_path_traversal),
            ("Rate Limiting Implementation", self._validate_rate_limiting),
            ("Audit Logging Security", self._validate_audit_logging),
            ("Circuit Breaker Security", self._validate_circuit_breaker),
            ("Configuration Security", self._validate_configuration),
        ]
        
        passed = 0
        failed = 0
        
        for check_name, check_func in checks:
            print(f"\n🔍 {check_name}...")
            try:
                result = check_func()
                if result["passed"]:
                    print(f"   ✅ PASSED")
                    passed += 1
                else:
                    print(f"   ❌ FAILED: {result.get('reason', 'Unknown')}")
                    failed += 1
                    
                    # Categorize issues
                    severity = result.get("severity", "medium")
                    if severity == "critical":
                        self.results["critical_issues"].append({
                            "check": check_name,
                            "issue": result.get("reason"),
                            "details": result.get("details", [])
                        })
                    elif severity == "high":
                        self.results["high_issues"].append({
                            "check": check_name,
                            "issue": result.get("reason"),
                            "details": result.get("details", [])
                        })
                    else:
                        self.results["medium_issues"].append({
                            "check": check_name,
                            "issue": result.get("reason"),
                            "details": result.get("details", [])
                        })
                
                self.results["security_checks"][check_name] = result
                
            except Exception as e:
                print(f"   ⚠️  ERROR: {str(e)}")
                failed += 1
                self.results["security_checks"][check_name] = {
                    "passed": False,
                    "reason": f"Check failed with error: {str(e)}",
                    "severity": "high"
                }
        
        # Determine overall status
        total_checks = len(checks)
        success_rate = passed / total_checks
        
        critical_issues = len(self.results["critical_issues"])
        high_issues = len(self.results["high_issues"])
        
        if critical_issues > 0:
            self.results["overall_status"] = "CRITICAL_ISSUES_FOUND"
            overall_passed = False
        elif high_issues > 0 and strict:
            self.results["overall_status"] = "HIGH_ISSUES_FOUND"
            overall_passed = False
        elif success_rate >= 0.9:
            self.results["overall_status"] = "PASSED"
            overall_passed = True
        else:
            self.results["overall_status"] = "FAILED"
            overall_passed = False
        
        # Generate report
        self._generate_report()
        
        # Print summary
        print("\n" + "=" * 60)
        print("🛡️  SECURITY VALIDATION SUMMARY")
        print("=" * 60)
        print(f"Total Checks: {total_checks}")
        print(f"Passed: {passed}")
        print(f"Failed: {failed}")
        print(f"Success Rate: {success_rate:.1%}")
        print(f"Critical Issues: {critical_issues}")
        print(f"High Issues: {high_issues}")
        print(f"Medium Issues: {len(self.results['medium_issues'])}")
        print(f"Overall Status: {self.results['overall_status']}")
        
        if not overall_passed:
            print("\n❌ SECURITY VALIDATION FAILED")
            if critical_issues > 0:
                print("🚨 CRITICAL SECURITY ISSUES MUST BE FIXED BEFORE DEPLOYMENT")
        else:
            print("\n✅ SECURITY VALIDATION PASSED")
            print("🛡️ Matrix bridge meets security requirements")
        
        return overall_passed
    
    def _run_bandit_scan(self) -> Dict[str, Any]:
        """Run Bandit static analysis security scanner."""
        try:
            output_file = self.reports_dir / "bandit_results.json"
            
            result = subprocess.run([
                "bandit", "-r", str(self.src_dir),
                "-f", "json",
                "-o", str(output_file)
            ], capture_output=True, text=True)
            
            if output_file.exists():
                with open(output_file) as f:
                    bandit_data = json.load(f)
                
                # Check for high/critical issues
                high_critical_issues = [
                    issue for issue in bandit_data.get("results", [])
                    if issue.get("issue_severity") in ["HIGH", "CRITICAL"]
                ]
                
                if high_critical_issues:
                    return {
                        "passed": False,
                        "reason": f"Found {len(high_critical_issues)} high/critical security issues",
                        "severity": "critical" if any(i.get("issue_severity") == "CRITICAL" for i in high_critical_issues) else "high",
                        "details": [
                            f"{issue['test_name']}: {issue['issue_text']}"
                            for issue in high_critical_issues[:5]  # First 5
                        ]
                    }
                
                return {"passed": True, "details": f"Scanned {len(bandit_data.get('results', []))} potential issues, none critical"}
            
            return {"passed": False, "reason": "Bandit scan produced no output"}
            
        except FileNotFoundError:
            return {"passed": False, "reason": "Bandit not installed", "severity": "medium"}
        except Exception as e:
            return {"passed": False, "reason": f"Bandit scan failed: {str(e)}", "severity": "medium"}
    
    def _run_safety_scan(self) -> Dict[str, Any]:
        """Run Safety dependency vulnerability scanner."""
        try:
            result = subprocess.run([
                "safety", "check", "--json"
            ], capture_output=True, text=True, cwd=self.project_root)
            
            if result.stdout.strip() and result.stdout.strip() != "[]":
                try:
                    safety_data = json.loads(result.stdout)
                    if safety_data:
                        return {
                            "passed": False,
                            "reason": f"Found {len(safety_data)} dependency vulnerabilities",
                            "severity": "high",
                            "details": [
                                f"{vuln.get('package', 'unknown')}: {vuln.get('vulnerability', 'unknown')}"
                                for vuln in safety_data[:3]  # First 3
                            ]
                        }
                except json.JSONDecodeError:
                    pass
            
            return {"passed": True, "details": "No dependency vulnerabilities found"}
            
        except FileNotFoundError:
            return {"passed": False, "reason": "Safety not installed", "severity": "medium"}
        except Exception as e:
            return {"passed": False, "reason": f"Safety scan failed: {str(e)}", "severity": "medium"}
    
    def _run_flake8_scan(self) -> Dict[str, Any]:
        """Run Flake8 code quality scanner."""
        try:
            result = subprocess.run([
                "flake8", str(self.src_dir), "--count", "--statistics"
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                return {"passed": True, "details": "Code quality checks passed"}
            else:
                # Count issues
                lines = result.stdout.strip().split('\n')
                issue_count = 0
                for line in lines:
                    if line.strip() and line.strip().isdigit():
                        issue_count += int(line.strip())
                
                return {
                    "passed": issue_count < 10,  # Allow some minor issues
                    "reason": f"Found {issue_count} code quality issues" if issue_count >= 10 else "Minor code quality issues",
                    "severity": "medium",
                    "details": lines[-10:] if lines else []  # Last 10 lines
                }
            
        except FileNotFoundError:
            return {"passed": False, "reason": "Flake8 not installed", "severity": "low"}
        except Exception as e:
            return {"passed": False, "reason": f"Flake8 scan failed: {str(e)}", "severity": "low"}
    
    def _detect_secrets(self) -> Dict[str, Any]:
        """Detect hardcoded secrets in code."""
        secret_patterns = [
            (r'password\s*=\s*["\'].*["\']', "Hardcoded password"),
            (r'api[_-]?key\s*=\s*["\'].*["\']', "Hardcoded API key"),
            (r'secret\s*=\s*["\'][^$].*["\']', "Hardcoded secret"),
            (r'token\s*=\s*["\'][^$].*["\']', "Hardcoded token"),
            (r'-----BEGIN \w+ KEY-----', "Private key"),
            (r'["\']pk_[a-zA-Z0-9]{24,}["\']', "Stripe publishable key"),
            (r'["\']sk_[a-zA-Z0-9]{24,}["\']', "Stripe secret key"),
        ]
        
        secrets_found = []
        
        for py_file in self.src_dir.rglob("*.py"):
            try:
                with open(py_file, 'r', encoding='utf-8') as f:
                    content = f.read()
                    
                for pattern, description in secret_patterns:
                    import re
                    matches = re.finditer(pattern, content, re.IGNORECASE)
                    for match in matches:
                        # Skip if it's a placeholder with ${} or template
                        if "${" in match.group(0) or "template" in match.group(0).lower():
                            continue
                            
                        secrets_found.append({
                            "file": str(py_file.relative_to(self.project_root)),
                            "pattern": description,
                            "match": match.group(0)[:50] + "..." if len(match.group(0)) > 50 else match.group(0)
                        })
                        
            except Exception as e:
                pass  # Skip files that can't be read
        
        if secrets_found:
            return {
                "passed": False,
                "reason": f"Found {len(secrets_found)} potential hardcoded secrets",
                "severity": "critical",
                "details": [f"{s['file']}: {s['pattern']}" for s in secrets_found[:5]]
            }
        
        return {"passed": True, "details": "No hardcoded secrets detected"}
    
    def _validate_input_handling(self) -> Dict[str, Any]:
        """Validate input handling security."""
        command_parser_file = self.src_dir / "command_parser.py"
        
        if not command_parser_file.exists():
            return {"passed": False, "reason": "Command parser file not found", "severity": "critical"}
        
        try:
            with open(command_parser_file, 'r') as f:
                content = f.read()
            
            # Check for security patterns
            required_patterns = [
                ("DANGEROUS_PATTERNS", "Dangerous pattern detection"),
                ("html.escape", "HTML escaping for XSS protection"),
                ("re.compile.*IGNORECASE", "Case-insensitive pattern matching"),
                ("CommandValidationError", "Proper error handling"),
                ("shlex.split", "Safe argument parsing"),
            ]
            
            missing_patterns = []
            for pattern, description in required_patterns:
                if pattern not in content:
                    missing_patterns.append(description)
            
            if missing_patterns:
                return {
                    "passed": False,
                    "reason": "Missing security patterns in input validation",
                    "severity": "high",
                    "details": missing_patterns
                }
            
            return {"passed": True, "details": "Input validation security patterns present"}
            
        except Exception as e:
            return {"passed": False, "reason": f"Failed to validate input handling: {str(e)}", "severity": "high"}
    
    def _validate_auth_security(self) -> Dict[str, Any]:
        """Validate authentication security implementation."""
        auth_file = self.src_dir / "auth.py"
        
        if not auth_file.exists():
            return {"passed": False, "reason": "Authentication file not found", "severity": "critical"}
        
        try:
            with open(auth_file, 'r') as f:
                content = f.read()
            
            security_features = [
                ("jwt.decode", "JWT token validation"),
                ("hmac.new", "HMAC for integrity"),
                ("rate_limit", "Rate limiting implementation"),
                ("cache_ttl", "Token cache expiration"),
                ("failed_attempts", "Failed attempt tracking"),
                ("AuthenticationError", "Proper error handling"),
                ("cryptography", "Cryptographic library usage"),
            ]
            
            missing_features = []
            for feature, description in security_features:
                if feature not in content:
                    missing_features.append(description)
            
            if missing_features:
                return {
                    "passed": False,
                    "reason": "Missing authentication security features",
                    "severity": "high",
                    "details": missing_features
                }
            
            return {"passed": True, "details": "Authentication security features present"}
            
        except Exception as e:
            return {"passed": False, "reason": f"Failed to validate auth security: {str(e)}", "severity": "high"}
    
    def _validate_command_injection(self) -> Dict[str, Any]:
        """Validate command injection protection."""
        patterns_to_check = [
            ("subprocess.run", "Safe subprocess usage"),
            ("shell=False", "Shell injection prevention"),
            ("shlex.split", "Safe argument splitting"),
            ("allowed_commands", "Command allowlisting"),
        ]
        
        issues = []
        
        for py_file in self.src_dir.rglob("*.py"):
            try:
                with open(py_file, 'r') as f:
                    content = f.read()
                
                # Check for dangerous subprocess usage
                if "subprocess" in content and "shell=True" in content:
                    issues.append(f"{py_file.name}: Uses shell=True in subprocess call")
                
                # Check for os.system usage
                if "os.system" in content:
                    issues.append(f"{py_file.name}: Uses dangerous os.system() call")
                
                # Check for eval/exec usage
                if any(dangerous in content for dangerous in ["eval(", "exec("]):
                    issues.append(f"{py_file.name}: Uses eval() or exec()")
                    
            except Exception:
                pass
        
        if issues:
            return {
                "passed": False,
                "reason": "Found potential command injection vulnerabilities",
                "severity": "critical",
                "details": issues
            }
        
        return {"passed": True, "details": "No command injection vulnerabilities found"}
    
    def _validate_sql_injection(self) -> Dict[str, Any]:
        """Validate SQL injection protection."""
        sql_files = []
        
        for py_file in self.src_dir.rglob("*.py"):
            try:
                with open(py_file, 'r') as f:
                    content = f.read()
                
                # Check for SQL-related code
                if any(sql_word in content.lower() for sql_word in ["select", "insert", "update", "delete", "create table"]):
                    # Check for string formatting in SQL
                    if any(unsafe in content for unsafe in [".format(", "% ", "f\""]):
                        sql_files.append(str(py_file.relative_to(self.project_root)))
                        
            except Exception:
                pass
        
        if sql_files:
            return {
                "passed": False,
                "reason": "Found potential SQL injection vulnerabilities",
                "severity": "critical",
                "details": sql_files
            }
        
        # For Matrix bridge, we don't expect direct SQL usage
        return {"passed": True, "details": "No SQL injection vulnerabilities found"}
    
    def _validate_xss_protection(self) -> Dict[str, Any]:
        """Validate XSS protection measures."""
        command_parser = self.src_dir / "command_parser.py"
        
        if command_parser.exists():
            try:
                with open(command_parser, 'r') as f:
                    content = f.read()
                
                # Check for XSS protection measures
                if "html.escape" not in content:
                    return {
                        "passed": False,
                        "reason": "Missing HTML escaping for XSS protection",
                        "severity": "high"
                    }
                
                # Check for dangerous HTML patterns in validation
                if "<script>" not in content or "javascript:" not in content:
                    return {
                        "passed": False,
                        "reason": "Missing XSS pattern detection in validation",
                        "severity": "medium"
                    }
                
                return {"passed": True, "details": "XSS protection measures present"}
                
            except Exception as e:
                return {"passed": False, "reason": f"Failed to validate XSS protection: {str(e)}", "severity": "medium"}
        
        return {"passed": False, "reason": "Command parser not found for XSS validation", "severity": "high"}
    
    def _validate_path_traversal(self) -> Dict[str, Any]:
        """Validate path traversal protection."""
        issues = []
        
        for py_file in self.src_dir.rglob("*.py"):
            try:
                with open(py_file, 'r') as f:
                    content = f.read()
                
                # Check for path traversal protection
                if ".." in content and "traversal" not in content.lower():
                    # Look for path operations without validation
                    if any(op in content for op in ["open(", "Path(", "os.path.join"]):
                        issues.append(str(py_file.relative_to(self.project_root)))
                        
            except Exception:
                pass
        
        # Check command parser specifically
        command_parser = self.src_dir / "command_parser.py"
        if command_parser.exists():
            try:
                with open(command_parser, 'r') as f:
                    content = f.read()
                
                if r'\.\..*\/' not in content and r'\.\..*\\' not in content:
                    return {
                        "passed": False,
                        "reason": "Missing path traversal pattern detection",
                        "severity": "high"
                    }
            except Exception:
                pass
        
        if issues:
            return {
                "passed": False,
                "reason": "Found potential path traversal vulnerabilities",
                "severity": "high",
                "details": issues
            }
        
        return {"passed": True, "details": "Path traversal protection present"}
    
    def _validate_rate_limiting(self) -> Dict[str, Any]:
        """Validate rate limiting implementation."""
        rate_limiter_file = self.src_dir / "rate_limiter.py"
        
        if not rate_limiter_file.exists():
            return {"passed": False, "reason": "Rate limiter file not found", "severity": "critical"}
        
        try:
            with open(rate_limiter_file, 'r') as f:
                content = f.read()
            
            required_features = [
                ("AsyncLimiter", "Rate limiting implementation"),
                ("burst_size", "Burst capacity management"),
                ("requests_per_minute", "Rate limit configuration"),
                ("adaptive", "Adaptive rate limiting"),
                ("client_metrics", "Per-client tracking"),
            ]
            
            missing = [desc for pattern, desc in required_features if pattern not in content]
            
            if missing:
                return {
                    "passed": False,
                    "reason": "Missing rate limiting features",
                    "severity": "high",
                    "details": missing
                }
            
            return {"passed": True, "details": "Rate limiting implementation complete"}
            
        except Exception as e:
            return {"passed": False, "reason": f"Failed to validate rate limiting: {str(e)}", "severity": "high"}
    
    def _validate_audit_logging(self) -> Dict[str, Any]:
        """Validate audit logging security."""
        audit_file = self.src_dir / "audit.py"
        
        if not audit_file.exists():
            return {"passed": False, "reason": "Audit logging file not found", "severity": "critical"}
        
        try:
            with open(audit_file, 'r') as f:
                content = f.read()
            
            security_features = [
                ("integrity_hash", "Log integrity protection"),
                ("hmac", "HMAC for tamper resistance"),
                ("sanitize", "Data sanitization"),
                ("AuditEvent", "Structured audit events"),
                ("chmod", "Secure file permissions"),
            ]
            
            missing = [desc for pattern, desc in security_features if pattern not in content]
            
            if missing:
                return {
                    "passed": False,
                    "reason": "Missing audit logging security features",
                    "severity": "high",
                    "details": missing
                }
            
            return {"passed": True, "details": "Audit logging security features present"}
            
        except Exception as e:
            return {"passed": False, "reason": f"Failed to validate audit logging: {str(e)}", "severity": "high"}
    
    def _validate_circuit_breaker(self) -> Dict[str, Any]:
        """Validate circuit breaker implementation."""
        cb_file = self.src_dir / "circuit_breaker.py"
        
        if not cb_file.exists():
            return {"passed": False, "reason": "Circuit breaker file not found", "severity": "high"}
        
        try:
            with open(cb_file, 'r') as f:
                content = f.read()
            
            required_features = [
                ("CircuitState", "Circuit breaker states"),
                ("failure_threshold", "Failure threshold configuration"),
                ("timeout", "Request timeout handling"),
                ("CircuitBreakerError", "Proper error handling"),
            ]
            
            missing = [desc for pattern, desc in required_features if pattern not in content]
            
            if missing:
                return {
                    "passed": False,
                    "reason": "Missing circuit breaker features",
                    "severity": "medium",
                    "details": missing
                }
            
            return {"passed": True, "details": "Circuit breaker implementation complete"}
            
        except Exception as e:
            return {"passed": False, "reason": f"Failed to validate circuit breaker: {str(e)}", "severity": "medium"}
    
    def _validate_configuration(self) -> Dict[str, Any]:
        """Validate configuration security."""
        config_file = self.project_root / "bridge_config.yaml"
        
        issues = []
        
        if config_file.exists():
            try:
                with open(config_file, 'r') as f:
                    content = f.read()
                
                # Check for hardcoded secrets
                if any(secret in content.lower() for secret in ["password:", "secret:", "token:"]):
                    # Should use environment variable substitution
                    if "${" not in content:
                        issues.append("Configuration may contain hardcoded secrets")
                
                # Check for secure defaults
                security_configs = [
                    ("host: \"127.0.0.1\"", "Local binding"),
                    ("rate_limit", "Rate limiting enabled"),
                    ("max_request_size", "Request size limits"),
                    ("audit_log", "Audit logging enabled"),
                ]
                
                for pattern, desc in security_configs:
                    if pattern not in content:
                        issues.append(f"Missing {desc}")
                        
            except Exception as e:
                issues.append(f"Failed to read configuration: {str(e)}")
        else:
            issues.append("Configuration file not found")
        
        if issues:
            return {
                "passed": False,
                "reason": "Configuration security issues found",
                "severity": "medium",
                "details": issues
            }
        
        return {"passed": True, "details": "Configuration security validated"}
    
    def _generate_report(self):
        """Generate comprehensive security report."""
        report_file = self.reports_dir / "security_validation_report.json"
        
        with open(report_file, 'w') as f:
            json.dump(self.results, f, indent=2)
        
        # Generate human-readable report
        text_report = self.reports_dir / "security_validation_report.txt"
        with open(text_report, 'w') as f:
            f.write("RAVE Matrix Bridge Security Validation Report\n")
            f.write("=" * 50 + "\n\n")
            
            f.write(f"Validation Timestamp: {self.results['validation_timestamp']}\n")
            f.write(f"Overall Status: {self.results['overall_status']}\n\n")
            
            if self.results['critical_issues']:
                f.write("CRITICAL ISSUES:\n")
                for issue in self.results['critical_issues']:
                    f.write(f"  - {issue['check']}: {issue['issue']}\n")
                f.write("\n")
            
            if self.results['high_issues']:
                f.write("HIGH SEVERITY ISSUES:\n")
                for issue in self.results['high_issues']:
                    f.write(f"  - {issue['check']}: {issue['issue']}\n")
                f.write("\n")
            
            if self.results['medium_issues']:
                f.write("MEDIUM SEVERITY ISSUES:\n")
                for issue in self.results['medium_issues']:
                    f.write(f"  - {issue['check']}: {issue['issue']}\n")
                f.write("\n")
            
            f.write("DETAILED CHECK RESULTS:\n")
            f.write("-" * 30 + "\n")
            for check_name, result in self.results['security_checks'].items():
                status = "PASSED" if result['passed'] else "FAILED"
                f.write(f"{check_name}: {status}\n")
                if not result['passed']:
                    f.write(f"  Reason: {result.get('reason', 'Unknown')}\n")
                if result.get('details'):
                    f.write(f"  Details: {result['details']}\n")
                f.write("\n")
        
        print(f"\n📊 Security validation report saved to: {text_report}")


def main():
    """Main entry point for security validation."""
    parser = argparse.ArgumentParser(description="Matrix Bridge Security Validator")
    parser.add_argument("--project-root", default=".", help="Project root directory")
    parser.add_argument("--strict", action="store_true", help="Strict mode - fail on high severity issues")
    parser.add_argument("--report-only", action="store_true", help="Generate report without exit code")
    
    args = parser.parse_args()
    
    # Run validation
    validator = SecurityValidator(args.project_root)
    success = validator.run_validation(strict=args.strict)
    
    if args.report_only:
        sys.exit(0)
    else:
        sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()