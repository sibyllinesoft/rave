"""
OAuth Manager - Shows status of pre-configured OAuth integrations
OAuth configurations are baked into the VM, this just provides visibility.
"""

import subprocess
from pathlib import Path
from typing import Dict, Optional


class OAuthManager:
    """Manages OAuth integration status (read-only, configs are baked in)."""
    
    def __init__(self):
        pass
    
    def _check_vm_oauth_status(self, company_name: str, service: str) -> Dict[str, any]:
        """Check OAuth status for a service in a VM."""
        # Import here to avoid circular dependency
        from vm_manager import VMManager
        
        vm_manager = VMManager(Path.home() / ".config" / "rave" / "vms")
        config = vm_manager._load_vm_config(company_name)
        
        if not config:
            return {"configured": False, "status": "VM not found"}
        
        if not vm_manager._is_vm_running(company_name):
            return {"configured": False, "status": "VM not running"}
        
        # Check service-specific OAuth configuration
        ports = config["ports"]
        ssh_cmd = [
            "ssh", "-i", config["keypair"], "-o", "StrictHostKeyChecking=no",
            "-p", str(ports["ssh"]), "root@localhost"
        ]
        
        if service == "penpot":
            # Check if Penpot is configured with GitLab OAuth
            check_cmd = ssh_cmd + ["curl", "-s", f"http://localhost/penpot/api/auth/providers"]
        elif service == "element":
            # Check if Element is configured with GitLab OAuth
            check_cmd = ssh_cmd + ["cat", "/etc/element-web/config.json"]
        else:
            return {"configured": False, "status": f"Unknown service: {service}"}
        
        try:
            result = subprocess.run(check_cmd, capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                # Parse response to determine if GitLab OAuth is configured
                if service == "penpot":
                    configured = "gitlab" in result.stdout.lower()
                elif service == "element":
                    configured = "oauth2_generic" in result.stdout
                else:
                    configured = False
                
                return {
                    "configured": configured,
                    "provider": "gitlab" if configured else "none",
                    "status": "configured" if configured else "not configured"
                }
            else:
                return {"configured": False, "status": "service not accessible"}
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            return {"configured": False, "status": "check failed"}
    
    def get_status(self, service: Optional[str] = None) -> Dict[str, any]:
        """Get OAuth configuration status."""
        # Get all VMs
        from vm_manager import VMManager
        vm_manager = VMManager(Path.home() / ".config" / "rave" / "vms")
        vm_statuses = vm_manager.status_all_vms()
        
        if not vm_statuses:
            return {"success": True, "configs": {}}
        
        configs = {}
        services = [service] if service else ["penpot", "element"]
        
        for company_name, vm_status in vm_statuses.items():
            if not vm_status["running"]:
                continue
                
            for svc in services:
                key = f"{svc} ({company_name})"
                status = self._check_vm_oauth_status(company_name, svc)
                configs[key] = status
        
        return {"success": True, "configs": configs}
    
    def configure_service(self, service: str, provider: str, client_id: str, 
                         client_secret: str, redirect_uri: Optional[str] = None) -> Dict[str, any]:
        """OAuth configuration is baked into VMs - this is not supported."""
        return {
            "success": False, 
            "error": "OAuth configuration is pre-baked into VMs. Use 'rave oauth status' to check current setup."
        }