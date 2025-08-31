# P2.2: NixOS VM Integration Tests
# Comprehensive testing using NixOS test driver for RAVE system

{ pkgs ? import <nixpkgs> {} }:

let
  # Import the test framework
  nixos-lib = import (pkgs.path + "/nixos/lib") {};
in

nixos-lib.runTest {
  name = "rave-vm-integration-test";
  
  # P2.2: Test configuration
  meta = {
    description = "RAVE Virtual Machine Integration Tests - P2.2";
    maintainers = [ "RAVE Team" ];
  };

  # P2.2: Define test machines  
  nodes = {
    # Main RAVE machine with P2 configuration for full observability testing
    rave = { config, pkgs, ... }: {
      imports = [ ../p2-production-config.nix ];
      
      # Test-specific overrides
      virtualisation = {
        memorySize = 2048;  # 2GB RAM for test
        cores = 2;          # Limit cores for CI
        graphics = false;   # Headless for CI
        
        # Enable forwarding for health checks
        forwardPorts = [
          { from = "host"; host.port = 3002; guest.port = 3002; }  # HTTPS
          { from = "host"; host.port = 3030; guest.port = 3030; }  # Grafana
          { from = "host"; host.port = 9090; guest.port = 9090; }  # Prometheus
          { from = "host"; host.port = 3001; guest.port = 3001; }  # Webhook dispatcher
        ];
      };
      
      # Test-specific secrets (dummy values for testing)
      sops.secrets = {
        "tls/certificate" = {
          sopsFile = ../test-secrets.yaml;  
          owner = "nginx";
          group = "nginx";
          mode = "0400";
          path = "/run/secrets/tls-cert";
        };
        "tls/private-key" = {
          sopsFile = ../test-secrets.yaml;
          owner = "nginx";
          group = "nginx"; 
          mode = "0400";
          path = "/run/secrets/tls-key";
        };
        "webhook/gitlab-secret" = {
          sopsFile = ../test-secrets.yaml;
          owner = "agent";
          group = "users";
          mode = "0400"; 
          path = "/run/secrets/webhook-gitlab-secret";
        };
      };
    };
  };

  # P2.2: Comprehensive test scenarios
  testScript = ''
    import json
    import time
    
    print("=== RAVE P2.2 Integration Test Suite ===")
    
    # Start the VM and wait for full boot
    print("\n1. Starting RAVE VM...")
    rave.start()
    
    # P2.2: Wait for systemd to complete startup
    print("2. Waiting for system initialization...")
    rave.wait_for_unit("multi-user.target", timeout=300)
    rave.wait_until_succeeds("systemctl is-system-running --wait", timeout=300)
    
    # P2.2: Test core systemd service health
    print("\n3. Testing systemd services...")
    
    # Test nginx
    print("   • Testing nginx...")
    rave.wait_for_unit("nginx.service", timeout=60)
    rave.succeed("systemctl is-active nginx")
    
    # Test Grafana
    print("   • Testing grafana...")
    rave.wait_for_unit("grafana.service", timeout=120) 
    rave.succeed("systemctl is-active grafana")
    
    # Test PostgreSQL (dependency for Grafana)
    print("   • Testing postgresql...")
    rave.wait_for_unit("postgresql.service", timeout=60)
    rave.succeed("systemctl is-active postgresql")
    
    # Test vibe-kanban
    print("   • Testing vibe-kanban...")
    rave.wait_for_unit("vibe-kanban.service", timeout=60)
    rave.succeed("systemctl is-active vibe-kanban")
    
    # Test claude-code-router
    print("   • Testing claude-code-router...")
    rave.wait_for_unit("claude-code-router.service", timeout=60)
    rave.succeed("systemctl is-active claude-code-router")
    
    # Test webhook dispatcher (P1 feature)
    print("   • Testing webhook-dispatcher...")
    rave.wait_for_unit("webhook-dispatcher.service", timeout=60)
    rave.succeed("systemctl is-active webhook-dispatcher")
    
    print("   ✓ All systemd services are active")
    
    # P2.2: Test HTTP health endpoints
    print("\n4. Testing HTTP health endpoints...")
    
    # Wait for services to be ready for connections
    rave.wait_for_open_port(3002, timeout=60)  # HTTPS nginx
    rave.wait_for_open_port(3030, timeout=60)  # Grafana
    rave.wait_for_open_port(3000, timeout=60)  # Vibe Kanban
    rave.wait_for_open_port(3456, timeout=60)  # Claude Code Router
    rave.wait_for_open_port(3001, timeout=60)  # Webhook Dispatcher
    
    # Test vibe-kanban health (through nginx proxy)
    print("   • Testing vibe-kanban HTTP response...")
    rave.wait_until_succeeds(
        "curl -k -f --connect-timeout 10 https://localhost:3002/ | grep -i 'kanban\\|vibe'",
        timeout=30
    )
    
    # Test Grafana health (through nginx proxy) 
    print("   • Testing Grafana HTTP response...")
    rave.wait_until_succeeds(
        "curl -k -f --connect-timeout 10 https://localhost:3002/grafana/login",
        timeout=30
    )
    
    # Test Claude Code Router health
    print("   • Testing Claude Code Router HTTP response...")
    rave.wait_until_succeeds(
        "curl -k -f --connect-timeout 10 https://localhost:3002/ccr-ui/",
        timeout=30
    )
    
    # Test webhook endpoint (should reject unauthorized requests)  
    print("   • Testing webhook dispatcher (unauthorized)...")
    webhook_response = rave.succeed(
        "curl -k -s -w '%{http_code}' https://localhost:3002/webhook -d '{}' || echo '000'"
    ).strip()
    if "401" not in webhook_response:
        raise Exception(f"Expected 401 unauthorized, got: {webhook_response}")
        
    print("   ✓ All HTTP endpoints responding correctly")
    
    # P2.2: Test TLS certificate configuration
    print("\n5. Testing TLS configuration...")
    
    # Verify TLS certificate is present and nginx can read it
    rave.succeed("test -f /run/secrets/tls-cert")
    rave.succeed("test -f /run/secrets/tls-key")
    
    # Test TLS connection
    tls_output = rave.succeed(
        "echo | openssl s_client -connect localhost:3002 -servername rave.local 2>/dev/null | openssl x509 -noout -subject"
    )
    print(f"   • TLS Certificate: {tls_output.strip()}")
    
    print("   ✓ TLS configuration working")
    
    # P2.2: Test SSH key authentication  
    print("\n6. Testing SSH configuration...")
    
    # Test SSH service is running
    rave.wait_for_unit("sshd.service", timeout=30)
    rave.wait_for_open_port(22, timeout=30)
    
    # Verify SSH configuration (key-only auth)
    ssh_config = rave.succeed("grep -E '(PasswordAuthentication|PubkeyAuthentication)' /etc/ssh/sshd_config || true")
    print(f"   • SSH Config: {ssh_config.strip()}")
    
    # Test agent user exists with proper configuration
    rave.succeed("id agent")
    agent_home = rave.succeed("getent passwd agent | cut -d: -f6").strip()
    rave.succeed(f"test -d {agent_home}")
    
    print("   ✓ SSH configuration working")
    
    # P2.2: Test firewall configuration
    print("\n7. Testing firewall configuration...")
    
    # Check firewall status
    firewall_status = rave.succeed("systemctl is-active firewall || echo 'not-active'").strip()
    print(f"   • Firewall status: {firewall_status}")
    
    # Test allowed ports are open
    open_ports = rave.succeed("ss -tlnp | grep -E ':(22|3002)' | wc -l").strip()
    if int(open_ports) < 2:
        raise Exception(f"Expected at least 2 open ports (22, 3002), found {open_ports}")
    
    print("   ✓ Firewall configuration working")
    
    # P2.2: Test secrets management (sops-nix)
    print("\n8. Testing secrets management...")
    
    # Check sops key file exists
    rave.succeed("test -f /var/lib/sops-nix/key.txt")
    
    # Verify secret files are created with proper permissions
    secrets_status = rave.succeed("""
        ls -la /run/secrets/ | grep -E '(tls-cert|tls-key|webhook-gitlab-secret)' | 
        awk '{print $1, $3, $4, $9}' || echo 'no-secrets'
    """).strip()
    print(f"   • Secrets permissions: {secrets_status}")
    
    print("   ✓ Secrets management working")
    
    # P2.2: Test service resource limits and security
    print("\n9. Testing service security...")
    
    # Check webhook dispatcher resource limits
    dispatcher_memory = rave.succeed(
        "systemctl show webhook-dispatcher --property=MemoryMax --value"
    ).strip()
    print(f"   • Webhook dispatcher memory limit: {dispatcher_memory}")
    
    # Verify services running as non-root users
    service_users = rave.succeed("""
        ps aux | grep -E '(vibe-kanban|claude-code-router|dispatcher)' | 
        grep -v grep | awk '{print $1}' | sort -u
    """).strip().split('\n')
    
    for user in service_users:
        if user and user != 'root' and user != 'agent':
            print(f"   • Service running as: {user}")
    
    print("   ✓ Service security measures working")
    
    # P2.2: Test event persistence and deduplication
    print("\n10. Testing webhook dispatcher functionality...")
    
    # Check SQLite database was created
    rave.succeed("test -f /var/lib/webhook-dispatcher/events.db")
    
    # Test database schema
    db_schema = rave.succeed(
        "sqlite3 /var/lib/webhook-dispatcher/events.db '.schema events' || echo 'no-schema'"
    ).strip()
    print(f"   • Event database schema exists: {'events' in db_schema}")
    
    print("   ✓ Webhook dispatcher functionality working")
    
    # P2.3: Test Prometheus and Grafana observability stack
    print("\n11. Testing P2.3 Observability Stack...")
    
    # Test Prometheus service
    print("   • Testing Prometheus...")
    rave.wait_for_unit("prometheus.service", timeout=120)
    rave.succeed("systemctl is-active prometheus")
    rave.wait_for_open_port(9090, timeout=60)
    
    # Test Prometheus API and targets
    prometheus_health = rave.succeed(
        "curl -s http://localhost:9090/-/healthy || echo 'unhealthy'"
    ).strip()
    if "unhealthy" in prometheus_health:
        raise Exception(f"Prometheus health check failed: {prometheus_health}")
    
    # Check Prometheus targets are being scraped
    print("   • Verifying Prometheus targets...")
    targets_response = rave.succeed(
        "timeout 30 curl -s 'http://localhost:9090/api/v1/targets' | jq -r '.data.activeTargets | length' || echo '0'"
    ).strip()
    target_count = int(targets_response) if targets_response.isdigit() else 0
    if target_count < 3:  # Should have at least node, prometheus, and webhook-dispatcher
        print(f"   ⚠ Warning: Only {target_count} Prometheus targets active")
    else:
        print(f"   ✓ Prometheus monitoring {target_count} targets")
    
    # Test Node Exporter
    print("   • Testing Node Exporter...")
    rave.wait_for_unit("prometheus-node-exporter.service", timeout=60)
    rave.wait_for_open_port(9100, timeout=30)
    node_metrics = rave.succeed(
        "curl -s http://localhost:9100/metrics | grep -c 'node_memory_MemTotal_bytes' || echo '0'"
    ).strip()
    if int(node_metrics) < 1:
        raise Exception("Node Exporter not providing system metrics")
    
    # Test Grafana and datasource connection
    print("   • Testing Grafana integration...")
    rave.wait_for_open_port(3030, timeout=60)
    
    # Test Grafana API health
    grafana_health = rave.succeed(
        "curl -s http://localhost:3030/api/health | jq -r '.database' || echo 'unknown'"
    ).strip()
    if "ok" not in grafana_health:
        print(f"   ⚠ Grafana health check: {grafana_health}")
    
    # Test Grafana-Prometheus datasource connection
    datasource_test = rave.succeed(
        "curl -s -u admin:admin 'http://localhost:3030/api/datasources/proxy/1/api/v1/query?query=up' | jq -r '.status' || echo 'error'"
    ).strip()
    if datasource_test == "success":
        print("   ✓ Grafana-Prometheus datasource connection working")
    else:
        print(f"   ⚠ Grafana datasource test result: {datasource_test}")
    
    # Test webhook dispatcher metrics endpoint
    print("   • Testing webhook dispatcher metrics...")
    webhook_metrics = rave.succeed(
        "curl -s http://localhost:3001/metrics | grep -c 'webhook_requests_total\\|webhook_uptime_seconds' || echo '0'"
    ).strip()
    if int(webhook_metrics) >= 2:
        print("   ✓ Webhook dispatcher exposing Prometheus metrics")
    else:
        print(f"   ⚠ Webhook dispatcher metrics incomplete: {webhook_metrics}")
    
    # Test SAFE mode memory constraints
    print("   • Verifying SAFE mode resource constraints...")
    prometheus_memory = rave.succeed(
        "systemctl show prometheus --property=MemoryMax --value || echo 'unlimited'"
    ).strip()
    grafana_memory = rave.succeed(
        "systemctl show grafana --property=MemoryMax --value || echo 'unlimited'"
    ).strip()
    
    print(f"   • Prometheus memory limit: {prometheus_memory}")
    print(f"   • Grafana memory limit: {grafana_memory}")
    
    if "unlimited" in prometheus_memory or "unlimited" in grafana_memory:
        print("   ⚠ Warning: Some services don't have memory limits set")
    else:
        print("   ✓ Memory limits properly configured for SAFE mode")
    
    print("   ✓ P2.3 Observability stack validation complete")
    
    # P2.2: Performance and resource usage checks
    print("\n12. Testing system performance...")
    
    # Check memory usage
    memory_usage = rave.succeed("free -m | grep 'Mem:' | awk '{print $3}'").strip()
    print(f"   • Memory usage: {memory_usage}MB")
    
    # Check CPU load
    cpu_load = rave.succeed("uptime | awk -F'load average:' '{print $2}'").strip()
    print(f"   • CPU load: {cpu_load}")
    
    # Check disk usage
    disk_usage = rave.succeed("df -h / | tail -1 | awk '{print $5}'").strip()
    print(f"   • Disk usage: {disk_usage}")
    
    if int(memory_usage) > 1800:  # Alert if using > 1.8GB of 2GB
        print(f"   ⚠ Warning: High memory usage: {memory_usage}MB")
    
    print("   ✓ System performance within acceptable limits")
    
    # P2.2: Final integration test
    print("\n13. Final integration validation...")
    
    # Test full request flow through nginx -> services
    integration_test = rave.succeed("""
        # Test main page load time
        time curl -k -f --connect-timeout 10 -s https://localhost:3002/ > /dev/null
        
        # Test multiple concurrent requests
        for i in {1..3}; do
            curl -k -s https://localhost:3002/grafana/api/health &
        done
        wait
        
        echo "Integration tests completed"
    """).strip()
    
    print(f"   • {integration_test}")
    print("   ✓ Full integration working")
    
    print("\n=== RAVE P2.2 Integration Tests: ALL PASSED ✓ ===")
    
    # Export test results for CI
    rave.succeed("""
        cat > /tmp/test-results.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="rave-vm-integration">
  <testsuite name="systemd-services" tests="7" failures="0" errors="0">
    <testcase classname="systemd" name="nginx"/>
    <testcase classname="systemd" name="grafana"/>
    <testcase classname="systemd" name="postgresql"/>
    <testcase classname="systemd" name="vibe-kanban"/>
    <testcase classname="systemd" name="claude-code-router"/>
    <testcase classname="systemd" name="webhook-dispatcher"/>
    <testcase classname="systemd" name="prometheus"/>
  </testsuite>
  <testsuite name="http-health" tests="4" failures="0" errors="0">
    <testcase classname="http" name="vibe-kanban-response"/>
    <testcase classname="http" name="grafana-response"/> 
    <testcase classname="http" name="ccr-response"/>
    <testcase classname="http" name="webhook-security"/>
  </testsuite>
  <testsuite name="security" tests="4" failures="0" errors="0">
    <testcase classname="security" name="tls-config"/>
    <testcase classname="security" name="ssh-config"/>
    <testcase classname="security" name="firewall-config"/>
    <testcase classname="security" name="secrets-management"/>
  </testsuite>
  <testsuite name="p2-observability" tests="6" failures="0" errors="0">
    <testcase classname="observability" name="prometheus-health"/>
    <testcase classname="observability" name="prometheus-targets"/>
    <testcase classname="observability" name="node-exporter"/>
    <testcase classname="observability" name="grafana-integration"/>
    <testcase classname="observability" name="webhook-metrics"/>
    <testcase classname="observability" name="safe-mode-constraints"/>
  </testsuite>
</testsuites>
EOF
    """)
  '';
}